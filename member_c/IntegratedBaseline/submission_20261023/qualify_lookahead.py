"""Qualify exact four-row delta and new regressions, never physical acceptance."""
from pathlib import Path
import argparse,hashlib,json,re,shutil
from prepare_display_lookahead import transform
from prepare_writer_credit import transform as credit_transform

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return p.read_text(encoding='utf-8-sig',errors='replace')
def require(ok,msg):
    if not ok:raise RuntimeError(msg)

def verify_credit_delta(root,record):
    parent=Path(record['parent']);name='ddr_result_writer_burst64.v'
    require(sha(parent/'source_manifest.json')==record['parent_manifest_sha256'],'Credit parent manifest drift')
    require(sha(parent/'sources'/name)==record['old_sha256'],'Credit parent source drift')
    require(sha(root/'sources'/name)==record['new_sha256'],'Credit source drift')
    require(sha(Path(__file__).with_name('prepare_writer_credit.py'))==record['generator_sha256'],'Credit generator drift')
    require(read(root/'sources'/name)==credit_transform(read(parent/'sources'/name)),'Unexpected credit transformation')

def verify_cache_delta(root,record):
    from prepare_cache_decision import transform as cache_transform
    parent=Path(record['parent']);name='ddr_quad_tile_cache.v'
    require(sha(parent/'source_manifest.json')==record['parent_manifest_sha256'],'Cache parent manifest drift')
    require(sha(parent/'sources'/name)==record['old_sha256'] and sha(root/'sources'/name)==record['new_sha256'],'Cache source drift')
    require(sha(Path(__file__).with_name('prepare_cache_decision.py'))==record['generator_sha256'],'Cache generator drift')
    require(read(root/'sources'/name)==cache_transform(read(parent/'sources'/name)),'Unexpected cache transformation')

def verify_native_payload_delta(root,record):
    from prepare_native_payload import transform_core,transform_top
    parent=Path(record['parent'])
    require(sha(parent/'source_manifest.json')==record['parent_manifest_sha256'],'Native payload parent drift')
    require(sha(Path(__file__).with_name('prepare_native_payload.py'))==record['generator_sha256'],'Native payload generator drift')
    functions={'video_correct_ddr_continuous_core.v':transform_core,'video_correct_ddr_top.v':transform_top}
    require(set(record['files'])==set(functions),'Unexpected native payload scope')
    for n,fn in functions.items():
        require(sha(parent/'sources'/n)==record['files'][n]['old_sha256'] and sha(root/'sources'/n)==record['files'][n]['new_sha256'],'Native payload source drift '+n)
        require(read(root/'sources'/n)==fn(read(parent/'sources'/n)),'Unexpected native payload transform '+n)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--candidate',type=Path,required=True);ap.add_argument('--implementation',choices=['build','performance'],default='build');a=ap.parse_args();o=a.candidate.resolve()
    m=json.loads(read(o/'source_manifest.json'));delta=m['display_lookahead'];parent=Path(delta['qualified_parent'])
    pq=json.loads(read(parent/'release/qualification.json'))
    require(pq['timing_qualified'] and sha(parent/'release/qualification.json')==delta['parent_qualification_sha256'],'Parent qualification drift')
    name='ddr_result_display_raw_corrected.v'
    credit=m.get('writer_credit');writer='ddr_result_writer_burst64.v';cache=m.get('cache_decision');cache_name='ddr_quad_tile_cache.v';payload=m.get('native_payload');native_core='video_correct_ddr_continuous_core.v'
    require(not cache or credit,'Cache cut requires bound ACK candidate')
    require(not payload or cache,'Native payload requires bound cache candidate')
    expected=['video_correct_ddr_top.v','continuous_source_path.v','status_overlay.v',name]+([writer] if credit else [])+([cache_name] if cache else [])+([native_core] if payload else [])
    require(m['changed']==expected,'Unexpected scope')
    if credit:verify_credit_delta(o,credit)
    if cache:verify_cache_delta(o,cache)
    if payload:verify_native_payload_delta(o,payload)
    for n,h in pq['candidate_source_sha256'].items():
        require(sha(parent/'sources'/n)==h,'Parent source drift '+n)
        if n!=name and not(credit and n==writer) and not(cache and n==cache_name) and not(payload and n in payload['files']):require(sha(o/'sources'/n)==h,'Unexpected changed module '+n)
        if credit and n==writer:require(h==credit['old_sha256'],'Credit differs from qualified ancestor')
        if cache and n==cache_name:require(h==cache['old_sha256'],'Cache differs from qualified ancestor')
        if payload and n in payload['files']:require(h==payload['files'][n]['old_sha256'],'Native payload differs from qualified ancestor')
    require(sha(parent/'sources'/name)==delta['old_sha256'] and sha(o/'sources'/name)==delta['new_sha256'],'Display delta hash drift')
    require(read(o/'sources'/name)==transform(read(parent/'sources'/name)),'Unexpected display transformation')
    require(sha(Path(__file__).with_name('prepare_display_lookahead.py'))==delta['generator_sha256'],'Display generator drift')
    for n,h in m['candidate_source_sha256'].items():require(sha(o/'sources'/n)==h,'Candidate source drift '+n)
    for k in ['bitstream','mask','final_timing_report']:require(sha(Path(pq[k]))==pq[k+'_sha256' if k!='final_timing_report' else 'final_timing_sha256'],'Parent artifact drift '+k)
    fixture_root=Path('D:/FPGA/output/b_lens_board_fixtures_20261022')
    for n,h in pq['fixtures']['fixtures_sha256'].items():require(sha(fixture_root/n)==h,'Golden fixture drift '+n)
    audit=json.loads(read(o/'interface_audit.json'));require(audit['all_pass'] and audit['physical_port_bits']==144 and audit['pds_source_count']==147,'Interface audit failed')
    require(sha(o/'build.tcl')==audit['pds_build_tcl_sha256'],'Audit build drift')
    for n,h in audit['pds_input_sha256'].items():require(sha(Path(n))==h,'PDS input drift '+n)
    actual=[(o/'build'/n).resolve() for n in re.findall(r'_file "(\.\./sources/[^"]+)"',read(o/'build/build.pds'))]
    require(actual==[Path(n) for n in audit['pds_input_sha256']],'Actual project input drift')
    tests={
        'shared_raw_sparse':('D:/FPGA/output/shared_raw_lookahead128_20261023','PASS RAW_PIPELINE corrected=0 native=1 pixels=4147200 unique_scans=2 published=2',True),
        'native_corrected':('D:/FPGA/output/lookahead_native_regression_20261023','PASS RAW_PIPELINE corrected=1 native=1 pixels=14515200 unique_scans=2 published=2',True),
        'continuous6':('D:/FPGA/output/lookahead_continuous6_20261023','PASS RAW_PIPELINE corrected=1 native=1 pixels=64281600 unique_scans=6 published=6',True),
        'late_mode_reset':('D:/FPGA/output/lookahead_mode_late_20261023','PASS RAW_CORRECTED native=0 late=1 checked=3072',False),
        'midblank_wrap':('D:/FPGA/output/lookahead_midblank_wrap_20261023','COVERAGE mid_window_swaps=3 epoch_wraps=1',False),
    }
    if credit:
        for key,path in [('shared_raw_sparse','credit_shared_raw128_20261023'),('native_corrected','credit_native_corrected_20261023'),('continuous6','credit_continuous6_20261023')]:
            tests[key]=(str(Path('D:/FPGA/output')/path),tests[key][1],True)
    if cache:
        for key,path in [('shared_raw_sparse','cache_shared_raw128_20261023'),('native_corrected','cache_native_corrected_20261023'),('continuous6','cache_continuous6_20261023')]:
            tests[key]=(str(Path('D:/FPGA/output')/path),tests[key][1],True)
    if payload:
        for key,path in [('shared_raw_sparse','payload_shared_raw128_20261023'),('native_corrected','payload_native_corrected_20261023'),('continuous6','payload_continuous6_20261023')]:
            tests[key]=(str(Path('D:/FPGA/output')/path),tests[key][1],True)
    records={}
    for key,(path,token,snapshot) in tests.items():
        root=Path(path);src=root/'source_snapshot' if snapshot else root
        log=read(root/'simulation.log');comp=read(root/'compile.log')
        require(token in re.sub(r'\s+',' ',log) and 'Errors: 0, Warnings: 0' in log and not re.search(r'\*\* (Fatal|Error|Warning):',log+comp),'Regression failed '+key)
        require('Errors: 0, Warnings: 0' in comp,'Compile failed '+key)
        sources={}
        for f in src.iterdir():
            if f.suffix not in ['.v','.sv','.vp']:continue
            if f.name not in ['tb.sv','tb_lens_board.sv']:
                require(sha(f)==sha(o/'sources'/f.name),'Test production mismatch '+f.name);sources[f.name]=sha(f)
        require(name in sources,'Display absent from regression '+key)
        bench=src/('tb_lens_board.sv' if snapshot else 'tb.sv')
        records[key]={'directory':str(root),'source_subdirectory':'source_snapshot' if snapshot else '.',
            'simulation_sha256':sha(root/'simulation.log'),'compile_sha256':sha(root/'compile.log'),
            'testbench_name':bench.name,'testbench_sha256':sha(bench),'production_sha256':sources,'pass_token':token}
        if payload and snapshot:
            from prepare_native_payload import enable_bench
            pb=json.loads(read(root/'payload_binding.json'));before=Path(pb['previous'])/'source_snapshot/tb_lens_board.sv'
            require(sha(before)==pb['previous_bench_sha256'] and sha(bench)==pb['enabled_bench_sha256'],'Payload bench binding drift')
            require(pb['generator_sha256']==payload['generator_sha256'] and read(bench)==enable_bench(read(before)),'Native opt-in not actually tested or stimulus changed')
            records[key]['payload_binding_sha256']=sha(root/'payload_binding.json')
            records[key]['pre_payload_bench_sha256']=sha(before)
    six=Path(tests['continuous6'][0]);six_original=six
    if credit:
        cb=json.loads(read(six/'credit_binding.json'));six_original=Path(cb['previous'])
        require(cb['writer_new_sha256']==credit['new_sha256'] and cb['transform_sha256']==credit['generator_sha256'],'Credit six-frame binding drift')
        require(cb['previous_bench_sha256']==records['continuous6'].get('pre_payload_bench_sha256',sha(six/'source_snapshot/tb_lens_board.sv')),'Credit stimulus changed')
        records['continuous6']['credit_binding_sha256']=sha(six/'credit_binding.json')
    sb=json.loads(read(six_original/'source_binding.json'))
    if cache:
        cb=json.loads(read(six/'cache_binding.json'))
        require(cb['cache_new_sha256']==cache['new_sha256'] and cb['cache_old_sha256']==cache['old_sha256'] and cb['transform_sha256']==cache['generator_sha256'],'Cache six-frame binding drift')
        require(cb['previous_bench_sha256']==records['continuous6'].get('pre_payload_bench_sha256',sha(six/'source_snapshot/tb_lens_board.sv')),'Cache stimulus changed')
        records['continuous6']['cache_binding_sha256']=sha(six/'cache_binding.json')
    six_parent=Path(sb['parent']);old_six=json.loads(read(six_parent/'verification.json'))
    require(sha(six_parent/'binding.json')==sb['original_binding_sha256'] and records['continuous6'].get('pre_payload_bench_sha256',sha(six/'source_snapshot/tb_lens_board.sv'))==sb['testbench_sha256'],'Six-frame stimulus drift')
    require(sb['testbench_sha256']==old_six['testbench_sha256'] and len(set(old_six['distinct_source_patterns_sha256_uint32le'].values()))==6,'Six varied input patterns missing')
    records['continuous6']['source_binding_sha256']=sha(six_original/'source_binding.json')
    records['continuous6']['distinct_patterns_sha256']=old_six['distinct_source_patterns_sha256_uint32le']
    metric_path=Path('D:/FPGA/output')/('payload_continuous6_metrics_20261023.json' if payload else 'cache_continuous6_metrics_20261023.json' if cache else 'credit_continuous6_metrics_20261023.json' if credit else 'lookahead_continuous6_metrics_20261023.json');metrics=json.loads(read(metric_path))
    require(metrics['input_sha256']==sha(six/'simulation.log') and metrics['analyzer_sha256']==sha(Path(__file__).with_name('video_metrics.py')) and metrics['new_result_events']==6 and not metrics['hardware_acceptance'],'New six-frame metrics binding failed')
    records['continuous6']['metrics_path']=str(metric_path)
    records['continuous6']['metrics_sha256']=sha(metric_path)
    red=Path('D:/FPGA/output/shared_raw_service128_20261023');green=Path(tests['shared_raw_sparse'][0])
    require('Fatal: RAW pixel mismatch id=1 x=0 y=3 actual=000000' in read(red/'simulation.log'),'Missing shared-service red')
    if payload:require(read(green/'source_snapshot/tb_lens_board.sv')==enable_bench(read(red/'source_snapshot/tb_lens_board.sv')),'Shared red/green stimulus changed beyond native opt-in')
    else:require(sha(red/'source_snapshot/tb_lens_board.sv')==sha(green/'source_snapshot/tb_lens_board.sv'),'Shared red/green stimulus differs')
    require(sha(red/'source_snapshot'/name)==delta['old_sha256'],'Shared red production drift')
    for f in (red/'source_snapshot').iterdir():
        if f.suffix in ['.v','.sv','.vp'] and f.name not in [name,'tb_lens_board.sv']:
            require(sha(f)==pq['candidate_source_sha256'][f.name],'Shared red ancestor source drift '+f.name)
        if f.suffix in ['.v','.sv','.vp'] and f.name not in [name,'tb_lens_board.sv']+([writer] if credit else [])+([cache_name] if cache else [])+(list(payload['files']) if payload else []):
            require(sha(f)==sha(o/'sources'/f.name),'Shared red unchanged source drift '+f.name)
    def negative_record(root,scope):
        src=root/'source_snapshot'
        return {'directory':str(root),'source_subdirectory':'source_snapshot','scope':scope,
            'simulation_sha256':sha(root/'simulation.log'),'compile_sha256':sha(root/'compile.log'),
            'testbench_name':'tb_lens_board.sv','testbench_sha256':sha(src/'tb_lens_board.sv'),
            'production_sha256':{f.name:sha(f) for f in src.iterdir() if f.suffix in ['.v','.sv','.vp'] and f.name!='tb_lens_board.sv'}}
    records['shared_red']=negative_record(red,'Old two-row design fails identical sparse-load stimulus')
    dense=Path('D:/FPGA/output')/('payload_shared_raw16_20261023' if payload else 'cache_shared_raw16_20261023' if cache else 'credit_shared_raw16_20261023' if credit else 'shared_raw_lookahead16_20261023')
    require('Fatal: RAW pixel mismatch id=1 x=0 y=8 actual=000000' in read(dense/'simulation.log'),'Missing documented dense-load limit')
    require(sha(dense/'source_snapshot'/name)==delta['new_sha256'],'Dense source drift')
    if credit:require(sha(dense/'source_snapshot'/writer)==credit['new_sha256'],'Dense writer source drift')
    if cache:require(sha(dense/'source_snapshot'/cache_name)==cache['new_sha256'],'Dense cache source drift')
    if payload:require(sha(dense/'source_snapshot'/native_core)==payload['files'][native_core]['new_sha256'],'Dense native payload core drift')
    for f in (dense/'source_snapshot').iterdir():
        if f.suffix in ['.v','.sv','.vp'] and f.name!='tb_lens_board.sv':require(sha(f)==sha(o/'sources'/f.name),'Dense compiled source drift '+f.name)
    records['dense_limit']=negative_record(dense,'Hypothetical denser long waits still miss deadlines; not physical distribution')
    if credit:
        micro=Path('D:/FPGA/output/writer_credit_pipeline2_20261023')
        proof=json.loads(read(micro/'verification.json'))
        require(proof['parent_writer_sha256']==credit['old_sha256'],'Writer stress parent drift')
        for mode,h in [('original',credit['old_sha256']),('registered',credit['new_sha256'])]:
            d=micro/mode;r=proof['tests'][mode]
            require(sha(d/writer)==r['writer_sha256'] and sha(d/'tb_writer_burst.sv')==r['bench_sha256'] and sha(d/'step2.log')==r['simulation_sha256'],'Writer stress source/log drift')
            if mode=='original':
                require(read(d/writer)==read(Path(credit['parent'])/'sources'/writer),'Original writer stress changed beyond newline normalization')
            else:require(sha(d/writer)==h,'Registered stress writer differs from candidate')
            require(all('Errors: 0, Warnings: 0' in read(d/n) for n in ['step1.log','step2.log']) and 'PASS burst writer credit pipeline stress' in read(d/'step2.log') and not re.search(r'\*\* (Fatal|Error|Warning):',read(d/'step1.log')+read(d/'step2.log')),'Writer stress failed')
        credit_proof={'directory':str(micro),'verification_sha256':sha(micro/'verification.json'),
            'original_source_scope':'Same qualified ancestor text with normalized newline bytes; registered writer bytes exactly match candidate',
            'records':{mode:dict(r,compile_sha256=sha(micro/mode/'step1.log')) for mode,r in proof['tests'].items()}}
    if cache:
        from cache_evidence import verify_cache_evidence
        cache_proof=verify_cache_evidence(Path('D:/FPGA/output/cache_decision_20261023'),cache['old_sha256'],cache['new_sha256'],cache['generator_sha256'])
    if payload:
        from native_evidence import verify_native_evidence
        payload_proof=verify_native_evidence(Path('D:/FPGA/output/native_payload_20261023'),o/'sources',payload)
    impl=o/a.implementation
    if a.implementation=='performance':
        binding=json.loads(read(impl/'input_binding.json'))
        require(binding['candidate_manifest_sha256']==sha(o/'source_manifest.json') and binding['upstream_build_tcl_sha256']==sha(o/'build.tcl'),'Route parent changed')
        require(binding['route_tcl_sha256']==sha(impl/'route.tcl'),'Route definition drift')
        for path,entry in binding['inputs'].items():require(sha(Path(path))==entry['sha256'] and sha(Path(entry['upstream']))==entry['sha256'],'Mapped/placed checkpoint drift')
        parentlog=read(o/'pds_console.log')
        require(all(f'Process "{n}" done.' in parentlog for n in ['Compile','Synthesize','Device Map','Place & Route']) and not re.search(r'^E:|ERROR:',parentlog,re.M),'Incomplete reroute parent')
        route_inputs=[(impl/n).resolve() for n in re.findall(r'_file "(\.\./sources/[^"]+)"',read(impl/'performance.pds'))]
        require(route_inputs==[Path(n) for n in audit['pds_input_sha256']],'Reroute source project drift')
        require(sha(o/'sources/board_ddr.fdc')==m['candidate_source_sha256']['board_ddr.fdc'],'Reroute FDC drift')
    selected_log=impl/'pds_console.log' if a.implementation=='performance' else o/'pds_console.log'
    log=read(selected_log);require('Process "Generate Bitstream" done.' in log and not re.search(r'^E:|ERROR:',log,re.M),'PDS incomplete/error')
    reports=list((impl/'report_timing').glob('*.rtr'));require(len(reports)==1,'Final timing missing')
    report=reports[0];timing=read(report);require('Design Summary : All Constraints Met.' in timing,'Final timing failed')
    pattern=r'(?:Setup|Hold|Recovery|Removal|Minimum Pulse Width) Summary\((?:Slow|Fast) Corner\):\s*\n(.*?)(?=\n\s*\n)'
    sections=re.findall(pattern,timing,re.S);require(len(sections)==10,'Missing timing sections');rows=[]
    for section in sections:
        for line in section.splitlines():
            v=re.search(r'(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+(\d+)\s+(\d+)\s*$',line)
            if v:require(float(v[1])>=0 and int(v[3])==0,'Failing endpoint '+line);rows.append(line.strip())
    require(len(rows)==100,'Missing timing domain rows')
    domains=lambda rs:[re.sub(r'\s+-?\d+\.\d+\s+-?\d+\.\d+\s+\d+\s+\d+\s*$','',v).split() for v in rs]
    require(domains(rows)==domains(pq['timing_summary_rows']),'Timing clock-domain coverage changed')
    out=o/'release';require(not out.exists(),'Preserve release')
    bit=impl/'generate_bitstream/video_correct_ddr_top.sbit';mask=bit.with_suffix('.smsk')
    require(bit.stat().st_size>1000000 and mask.stat().st_size>0,'Bit/mask missing')
    out.mkdir()
    for f in [bit,mask]:shutil.copyfile(f,out/f.name)
    q=dict(pq);q.update(bitstream=str(out/bit.name),mask=str(out/mask.name),bitstream_sha256=sha(bit),mask_sha256=sha(mask),
        final_timing_report=str(report),final_timing_sha256=sha(report),timing_summary_rows=rows,
        candidate_source_sha256=m['candidate_source_sha256'],implementation=a.implementation,implementation_log_sha256=sha(selected_log),
        interface_audit_sha256=sha(o/'interface_audit.json'),display_regressions=records,
        parent_qualification_sha256=delta['parent_qualification_sha256'],
        inherited_regressions_scope='Parent records apply only to byte-identical B/RX/DDR/control modules; changed display is covered by display_regressions',
        hardware_programmed=False,real_video_acceptance=False,white_gray_hardware_problem_resolved=False,
        scope='Native fullHD trial with four-row display lookahead; fixes a reproducible sparse-latency model miss; dense service limits and physical white/gray failure not yet accepted')
    q['ancestor_native_regressions']=q['native_regressions']
    q['native_regressions']={}
    q['current_full_chain_evidence']='display_regressions:shared_raw_sparse/native_corrected/continuous6'
    q['current_changed_datapath_modules']=[name]+([writer] if credit else [])+([cache_name] if cache else [])+(list(payload['files']) if payload else [])
    if a.implementation=='performance':
        q['implementation_metadata_sha256']={n:sha(impl/n) for n in ['route.tcl','input_binding.json','performance.pds']}
    if credit:
        q['writer_credit_regression']=credit_proof
        q['inherited_regressions_scope']='Parent records apply only to byte-identical modules; changed display and writer have new full-chain and writer stress regressions'
        q['scope']+='; registered exclusive ACK-slot grant, no physical video acceptance'
    if cache:
        q['cache_decision_regression']=cache_proof
        q['inherited_regressions_scope']='Parent records apply only to byte-identical modules; display/writer/cache changes have current full-chain and module-specific evidence'
        q['scope']+='; registered cache decision inputs with unchanged transaction cycles/order'
    if payload:
        q['native_payload_regression']=payload_proof
        q['scope']+='; opt-in native single-beat WDATA reserved for BIST with capture8, video block payloads unchanged'
    (out/'qualification.json').write_text(json.dumps(q,indent=2)+'\n')
    print('LOOKAHEAD_QUALIFIED',sha(bit))

if __name__=='__main__':main()
