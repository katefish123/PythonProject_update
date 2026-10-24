"""Create a local, relocatable source/PDS/CRAM candidate only after qualification."""
from pathlib import Path
import argparse,hashlib,json,re,shutil,subprocess,zipfile

def require(ok,msg):
    if not ok:raise RuntimeError(msg)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def verify_display_evidence(test,record):
    require(sha(test/'simulation.log')==record['simulation_sha256'],'Display simulation drift')
    require(sha(test/'compile.log')==record['compile_sha256'],'Display compile drift')
    src=test/record['source_subdirectory'];bench=src/record['testbench_name']
    require(sha(bench)==record['testbench_sha256'],'Display testbench drift')
    actual={p.name for p in src.iterdir() if p.suffix in ['.v','.sv','.vp'] and p.name!=bench.name}
    require(actual==set(record['production_sha256']),'Unbound display test source')
    for n,h in record['production_sha256'].items():require(sha(src/n)==h,'Display compiled source drift '+n)
    for name in ['source_binding','credit_binding','cache_binding','payload_binding']:
        if name+'_sha256' in record:require(sha(test/(name+'.json'))==record[name+'_sha256'],'Display metadata drift '+name)
    return src

def verify_route_metadata(root,record):
    require(set(record)=={'route.tcl','input_binding.json','performance.pds'},'Incomplete route metadata binding')
    for n,h in record.items():require(sha(root/n)==h,'Qualified route metadata drift '+n)
    b=json.loads((root/'input_binding.json').read_text())
    require(b['route_tcl_sha256']==sha(root/'route.tcl'),'Route Tcl not bound to checkpoints')

def verify_writer_credit_evidence(root,record):
    require(sha(root/'verification.json')==record['verification_sha256'],'Writer credit verification drift')
    require(set(record['records'])=={'original','registered'},'Writer credit comparison missing')
    for mode,r in record['records'].items():
        for name,key in [('ddr_result_writer_burst64.v','writer_sha256'),('tb_writer_burst.sv','bench_sha256'),('step1.log','compile_sha256'),('step2.log','simulation_sha256')]:
            require(sha(root/mode/name)==r[key],'Writer credit evidence drift '+mode+'/'+name)

def copy_rx_fallback(out):
    src=Path('D:/FPGA/output/rx_preview_retime_20261023/release')
    proof=json.loads((src/'qualification.json').read_text())
    expected='10de7a0df18a12c5b8cab8afdf8f0c00a07a648c629933e93414120beb11e85f'
    require(proof['timing_qualified'] and proof['timing_rows_checked']==40 and proof['bitstream_sha256']==expected,'Unqualified RX fallback')
    for key in ['bitstream','mask']:
        require(sha(Path(proof[key]))==proof[key+'_sha256'],'RX fallback artifact drift '+key)
    require(proof['mask_sha256']=='61b8ca82799a668e83ec93a4c5916febd4f7dfbe049933fb6a9f3dbad0b5a58d','RX fallback mask changed')
    report=Path(proof['final_timing_report']);require(sha(report)==proof['final_timing_sha256'],'RX fallback timing drift')
    evidence=Path('C:/Users/Lenovo/Documents/ChatGPT/FPGA/initial_display_fix')
    program=evidence/'rx_isolation_program_20261023_124628'
    receipt=json.loads((program/'hardware_programming.json').read_text())
    require(receipt['bitstream_sha256']==expected and receipt['program_verified'] and not receipt['flash_programmed'],'RX fallback program receipt differs')
    motion=evidence/'board_rx_isolation_20261023_124804/motion_observation.json'
    observed=json.loads(motion.read_text())
    require(observed['bitstream_sha256']==expected and observed['live_following_user_confirmed'] and not observed['full_engineering_acceptance'],'RX motion evidence differs')
    dst=out/'fallback/rx_only';dst.mkdir(parents=True)
    for p in [Path(proof['bitstream']),Path(proof['mask']),src/'qualification.json',program/'hardware_programming.json',program/'program.log',motion]:shutil.copy2(p,dst/p.name)
    shutil.copy2(report,dst/'final_timing.rtr')
    (dst/'SCOPE.md').write_text('降采样RX-only诊断回退；原Program/Verify及运动观察记录仅证明当时可跟随运动，不是当前完整校正链路验收。硬件仅由烧录窗口操作，CRAM，不写Flash。\n',encoding='utf-8')

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--candidate',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);args=ap.parse_args()
    source=args.candidate.resolve();out=args.output.resolve();helpers=Path(__file__).parent
    submission=helpers.parent/'submission_20261023'
    source_manifest=json.loads((source/'source_manifest.json').read_text())
    presentation='presentation' in source_manifest
    q=json.loads((source/'release/qualification.json').read_text())
    require(q['timing_qualified'] and q['ready_for_authorized_cram_experiment'],'Candidate not qualified')
    require(sha(source/'interface_audit.json')==q['interface_audit_sha256'],'Qualified interface audit changed')
    selected_log=source/'performance/pds_console.log' if q.get('implementation')=='performance' else source/'pds_console.log'
    require(sha(selected_log)==q['implementation_log_sha256'],'Qualified implementation log changed')
    records=q.get('ancestor_native_regressions',q['native_regressions'])
    fixture_root=Path('D:/FPGA/output/b_lens_board_fixtures_20261022')
    require(json.loads((fixture_root/'manifest.json').read_text())==q['fixtures'],'Qualified fixture manifest changed')
    for n,h in q['fixtures']['fixtures_sha256'].items():require(sha(fixture_root/n)==h,'Qualified fixture changed '+n)
    for n,h in q['candidate_source_sha256'].items():require(sha(source/'sources'/n)==h,'Source drift '+n)
    for name,key in [('bitstream','bitstream_sha256'),('mask','mask_sha256'),('final_timing_report','final_timing_sha256')]:require(sha(Path(q[name]))==q[key],'Qualified artifact drift '+name)
    require(not out.exists(),'Preserve existing delivery');out.mkdir(parents=True)
    shutil.copytree(source/'sources',out/'sources')
    for name in ['project','release','validation','tools']:(out/name).mkdir()
    for ext in ['sbit','smsk']:shutil.copy2(source/f'release/video_correct_ddr_top.{ext}',out/'release')
    shutil.copy2(source/'release/qualification.json',out/'release')
    shutil.copy2(Path(q['final_timing_report']),out/'validation/final_timing.rtr')
    shutil.copy2(source/'interface_audit.json',out/'validation')
    shutil.copy2(source/'source_manifest.json',out/'validation')
    shutil.copy2(helpers/'TEAM_SNAPSHOT_20261023.json',out/'validation')
    shutil.copy2(source/'pds_console.log',out/'validation')
    if q.get('implementation')=='performance':
        if 'display_lookahead' in source_manifest:
            verify_route_metadata(source/'performance',q['implementation_metadata_sha256'])
        d=out/'validation/performance';d.mkdir()
        for n in ['pds_console.log','route.tcl','input_binding.json','performance.pds']:shutil.copy2(source/'performance'/n,d/n)
        route_binding=json.loads((d/'input_binding.json').read_text());(d/'inputs').mkdir()
        for original,entry in route_binding['inputs'].items():
            require(sha(Path(original))==entry['sha256'] and sha(Path(entry['upstream']))==entry['sha256'],'Reroute checkpoint drift')
            shutil.copy2(Path(original),d/'inputs'/Path(original).name)
    shutil.copy2(Path('D:/FPGA/output/b_lens_board_fixtures_20261022/manifest.json'),out/'validation/fixture_manifest.json')
    shutil.copy2(Path('D:/FPGA/team_downloads/20261022_B_lens_v2/member_b_lens_pipeline_v2/calibration/r50_18mm_hdmi_trial.json'),out/'validation/trial_calibration.json')
    prefix='b_lens_release2' if 'physical_counter_frontend' in (source/'source_manifest.json').read_text() else 'b_lens_release'
    phase_name='rx_frontend_phase_test_20261023_release2' if prefix.endswith('2') else 'rx_frontend_phase_test_20261023_valid'
    for rate in [30,60]:
        t=Path(f'D:/FPGA/output/{prefix}_input{rate}_20261023')
        record=records[f'input{rate}']
        require(sha(t/'simulation.log')==record['simulation_log_sha256'],'Qualified video regression changed')
        require(json.loads((t/'compiled_hashes.json').read_text())==record['compiled_sha256'],'Qualified compiled source record changed')
        require(json.loads((t/'candidate_binding.json').read_text())==record['candidate_binding'],'Qualified test binding changed')
        d=out/f'validation/input{rate}';d.mkdir()
        for n in ['compile.log','simulation.log','compiled_hashes.json','candidate_binding.json']:shutil.copy2(t/n,d/n)
    d=out/'validation/frontend_vs_recovery';d.mkdir()
    test=Path(f'D:/FPGA/output/{prefix}_frontsync_20261023');record=records['frontend_and_vs_recovery']
    require(sha(test/'simulation.log')==record['simulation_log_sha256'] and sha(test/'simulation_raw.log')==record['raw_log_sha256'],'Qualified frontend/RAW results changed')
    require(json.loads((test/'compiled_hashes.json').read_text())==record['compiled_sha256'],'Qualified frontend sources changed')
    for n in ['compile.log','simulation.log','simulation_raw.log','compiled_hashes.json','candidate_binding.json']:shutil.copy2(Path(f'D:/FPGA/output/{prefix}_frontsync_20261023')/n,d/n)
    phase=out/'validation/frontend_phase';phase.mkdir()
    require(sha(Path('D:/FPGA/output')/phase_name/'green/simulation.log')==q['frontend_phase_sha256'],'Qualified frontend phase result changed')
    for mode in ['red','green']:
        d=phase/mode;d.mkdir()
        for n in ['compile.log','simulation.log','binding.json','rx_frontend.v','tb.sv']:shutil.copy2(Path('D:/FPGA/output')/phase_name/mode/n,d/n)
    if prefix.endswith('2'):
        require(sha(Path('D:/FPGA/output/lens_telemetry_phase_20261023/green/simulation.log'))==records['physical_telemetry']['simulation_log_sha256'],'Qualified telemetry result changed')
        for mode in ['red','green']:
            d=out/'validation/physical_telemetry'/mode;d.mkdir(parents=True)
            for n in ['compile.log','simulation.log','binding.json','telemetry.v','tb.sv','hdmi_vs_recover.v']:shutil.copy2(Path('D:/FPGA/output/lens_telemetry_phase_20261023')/mode/n,d/n)
    config=out/'validation/hdmi_configuration';config.mkdir()
    ownership=out/'validation/source_ownership';ownership.mkdir()
    test=Path(f'D:/FPGA/output/{prefix}_ownership_20261023');record=records['ownership_and_invalid_input']
    require(sha(test/'simulation.log')==record['simulation_log_sha256'],'Qualified ownership result changed')
    require(json.loads((test/'compiled_hashes.json').read_text())==record['compiled_sha256'],'Qualified ownership sources changed')
    require(sha(Path('D:/FPGA/output/b_lens_rxretime_config_clean_20261023/simulation.log'))==q['config_regression_sha256'],'Qualified configuration result changed')
    for n in ['compile.log','simulation.log','compiled_hashes.json']:shutil.copy2(Path(f'D:/FPGA/output/{prefix}_ownership_20261023')/n,ownership/n)
    for n in ['compile.log','simulation.log','source_binding.json']:shutil.copy2(Path('D:/FPGA/output/b_lens_rxretime_config_clean_20261023')/n,config/n)
    shutil.copy2(helpers/'program_package.py',out/'tools')
    shutil.copy2(helpers/'ACCEPTANCE_20261023.md',out/'验收步骤.md')
    shutil.copy2(helpers/'INTERFACES_20261023.md',out/'接口核对.md')
    if not presentation:shutil.copy2(helpers/'OFFLINE_RELEASE_20261023.md',out/'离线检查与待验收项.md')
    else:
        data=records['presentation'];test=Path('D:/FPGA/output/presentation_green3_20261023')
        require(sha(test/'simulation.log')==data['simulation_log_sha256'],'Qualified presentation result changed')
        continuous=Path('D:/FPGA/output/b_lens_submission_continuous6_20261023')
        require(sha(continuous/'verification.json')==records['continuous6']['verification_sha256'],'Qualified continuous verification changed')
        require(sha(continuous/'simulation.log')==records['continuous6']['simulation_log_sha256'],'Qualified continuous results changed')
        dst=out/'validation/presentation';dst.mkdir()
        for n in ['compile.log','simulation.log','binding.json','presentation_policy.v','tb.sv']:shutil.copy2(test/n,dst/n)
        dst=out/'validation/continuous6';dst.mkdir()
        for n in ['compile.log','simulation.log','binding.json','verification.json']:shutil.copy2(continuous/n,dst/n)
        shutil.copytree(continuous/'source_snapshot',dst/'source_snapshot')
        shutil.copy2(Path('D:/FPGA/output/submission_continuous6_metrics_20261023.json'),dst/'metrics.json')
        metrics=json.loads((dst/'metrics.json').read_text())
        require(metrics['new_result_events']==6 and metrics['input_sha256']==sha(continuous/'simulation.log') and metrics['analyzer_sha256']==sha(submission/'video_metrics.py'),'Continuous metrics/report binding changed')
        previous=Path('D:/FPGA/output/b_lens_release2_frontsync_20261023')
        shutil.copytree(previous/'source_snapshot',out/'validation/baseline_test/source_snapshot')
        shutil.copytree(Path('D:/FPGA/output/b_lens_board_fixtures_20261022'),out/'validation/golden_fixtures')
        for n in ['video_metrics.py','board_geometry.py','prepare_continuous_check.py','test_video_metrics.py','test_board_geometry.py']:shutil.copy2(submission/n,out/'tools'/n)
        shutil.copy2(submission/'README.md',out/'测量工具与回归说明.md')
        shutil.copy2(submission/'上板采集与最终缺项.md',out/'上板采集与最终缺项.md')
        shutil.copy2(Path('D:/FPGA/output/submission_measurement_tests_20261023.log'),out/'validation/measurement_tests.log')
        example=out/'validation/geometry_example';example.mkdir()
        original=Path('D:/FPGA/team_downloads/20261022_B_lens_v2/member_b_lens_pipeline_v2')
        shutil.copy2(original/'examples/real_18mm_input.png',example/'raw.png')
        shutil.copy2(original/'results/lens_autocrop_demo/fixed.png',example/'corrected.png')
        shutil.copy2(Path('D:/FPGA/output/submission_geometry_example_20261023.json'),example/'diagnostic_not_acceptance.json')
        geometry=json.loads((example/'diagnostic_not_acceptance.json').read_text())
        require(geometry['raw']['sha256']==sha(example/'raw.png') and geometry['corrected']['sha256']==sha(example/'corrected.png') and geometry['analyzer_sha256']==sha(submission/'board_geometry.py'),'Geometry diagnostic binding changed')
        (out/'离线检查与待验收项.md').write_text('# 离线资格与未完成项\n\n本次码流SHA256：`'+q['bitstream_sha256']+'`。全部100行最终时序通过，实际报告见validation/final_timing.rtr。展示控制已独立红绿验证，六幅变化内容的全高清数据通路回归通过；复用证据对应的生产模块字节未改变。\n\n默认干净全幅画面；双键稳定按住约50ms切换诊断，在帧边界生效。双键期间仍沿用原KEY1 RAW/KEY2最近邻功能，松开回到默认双线性校正，诊断显示状态保留。约30次扫描不换图（60Hz时约0.5s）显示HELD，实际故障提示优先。\n\n本版未上板验收：颜色、清晰度、真实标定、实际新图率/延迟、长期稳定性及重连均待测。仍是固定镜头试标定，deploy_to_fpga=false；局部纸框/框外保持及动态控制未完成，不能称为交赛成品。用户接受实际吞吐不足60张/秒，约10.02张/秒目前仍只是短时仿真。\n',encoding='utf-8')
    (out/'program.ps1').write_text("$ErrorActionPreference='Stop'\n& python (Join-Path $PSScriptRoot 'tools/program_package.py')\nif($LASTEXITCODE -ne 0){throw 'Programming or verification failed; inspect program_logs'}\n")
    (out/'program.cmd').write_text('@echo off\npython "%~dp0tools\\program_package.py"\nif errorlevel 1 echo Programming or verification failed. Inspect program_logs.\npause\n',encoding='ascii')
    text=(source/'build.tcl').read_text();cut=text.index('compile -top_module')
    setup=text[:cut].replace((source/'sources').as_posix(),(out/'sources').as_posix())
    script=out/'tools/create_project.tcl';script.write_text(setup+'compile -top_module video_correct_ddr_top\n')
    with (out/'validation/project_creation.log').open('wb') as f:
        result=subprocess.run(['D:/softwares/PDS/PDS_2022.2-SP6.4/bin/pds_shell.exe','-file',str(script),'-project_name','FullHD_Lens_RXRetimed'],cwd=out/'project',stdout=f,stderr=subprocess.STDOUT)
    require(result.returncode==0,'PDS source project creation failed')
    creation=(out/'validation/project_creation.log').read_text(errors='replace')
    require('Process "Compile" done.' in creation and not re.search(r'^E:|ERROR:',creation,re.M),'Relocated source project compile failed')
    project=out/'project/FullHD_Lens_RXRetimed.pds';require(project.is_file(),'Missing PDS')
    p=project.read_text();source_paths=re.findall(r'_file "(\.\./sources/[^"]+)"',p)
    require('(_option top_module (_string "video_correct_ddr_top"))' in p,'Packaged PDS top module not selected')
    require(len(source_paths)==148 and all((project.parent/n).is_file() for n in source_paths),'PDS source resolution failed')
    require(not re.search(r'_file "[A-Za-z]:',p),'PDS contains absolute source paths')
    # The regeneration script derives its paths from its own location.
    local_setup='set root [file normalize [file join [file dirname [info script]] ..]]\n'
    for line in setup.splitlines():
        match=re.match(r'(add_design|add_constraint)\s+\{([^}]+)\}',line)
        local_setup+=f'{match[1]} [file join $root sources {Path(match[2]).name}]\n' if match else line+'\n'
    script.write_text(local_setup+'compile -top_module video_correct_ddr_top\n')
    (out/'tools/rebuild.tcl').write_text(local_setup+text[cut:])
    if q.get('implementation')=='performance':
        route=(source/'performance/route.tcl').read_text()
        command=next(line for line in route.splitlines() if line.startswith('pnr '))
        for original in route_binding['inputs']:
            command=command.replace('{'+Path(original).as_posix()+'}', '[file join $root validation performance inputs '+Path(original).name+']')
        checkpoint_setup=local_setup+'add_constraint [file join $root validation performance inputs video_correct_ddr_top.pcf]\n'
        (out/'tools/reroute_from_checkpoint.tcl').write_text(checkpoint_setup+command+'\nreport_timing\ngen_bit_stream\n')
    (out/'README.md').write_text('# 全高清镜头校正集成候选\n\n入口：`project/FullHD_Lens_RXRetimed.pds`；直接临时烧录：`program.ps1`。\n\n已通过源码/接口/仿真及最终时序检查，尚未完成这份完整码流的实板验收。不是最终比赛成品。请先读 `验收步骤.md`。\n\n保留 1920×1080 和 16:9，B 镜头数学模块不变。临时 CRAM，未写 Flash。包内验证记录绑定本码流；修改源文件后不能沿用。当前诊断曾见偏绿，颜色、清晰度、刷新率及稳定性均须现场验收。\n\n本地私有交付含已有厂商依赖，不自动上传公开仓库。\n',encoding='utf-8')
    if presentation:
        with (out/'README.md').open('a',encoding='utf-8') as f:f.write('\n本轮加入干净演示画面、可切换诊断及停更告警；操作说明和剩余交赛缺项见“离线检查与待验收项.md”。测量工具在tools，完整六幅回归及黄金图在validation。\n')
    if 'status_rom_repair' in source_manifest:
        repair=source_manifest['status_rom_repair'];proof=records['status_rom_repair']
        require(sha(source/'sources/status_overlay.v')==proof['new_sha256'],'Status repair RTL drift')
        for mode,key in [('red','red_log_sha256'),('green','green_log_sha256')]:
            test=Path(repair[mode+'_test']);require(sha(test/'simulation.log')==proof[key],'Status repair regression drift')
            require(sha(test/'tb.sv')==proof['testbench_sha256'],'Status repair testbench drift')
            dst=out/'validation/status_rom'/mode;dst.mkdir(parents=True)
            for n in ['status_overlay.v','tb.sv','compile.log','simulation.log','binding.json']:shutil.copy2(test/n,dst/n)
        shutil.copy2(submission/'BOARD_FAILURE_20261023.md',out/'实板失败与诊断修正.md')
        with (out/'README.md').open('a',encoding='utf-8') as f:f.write('\n本版另修复状态字库重复定义造成的RAW/HELD/RECOVERING文字错误。原版已确认实板白灰画面验收失败，这项文字修正不会解决像素内容。当前完整码流尚未上板，须由烧录窗口受控验收；不得称为画面已修复。\n')
    if 'display_lookahead' in source_manifest:
        require('display_regressions' in q,'Missing new display qualification')
        for key,record in q['display_regressions'].items():
            test=Path(record['directory']);src=verify_display_evidence(test,record)
            dst=out/'validation/display_lookahead'/key;dst.mkdir(parents=True)
            for n in ['simulation.log','compile.log','binding.json','source_binding.json','credit_binding.json','cache_binding.json','payload_binding.json','run.ps1']:
                if (test/n).is_file():shutil.copy2(test/n,dst/n)
            if 'metrics_sha256' in record:
                require(sha(Path(record['metrics_path']))==record['metrics_sha256'],'New display metrics drift')
                shutil.copy2(Path(record['metrics_path']),dst/'metrics.json')
            if src.is_dir():
                target=dst/'source_snapshot';target.mkdir()
                for f in src.iterdir():
                    if f.suffix in ['.v','.sv','.vp']:shutil.copy2(f,target/f.name)
        for n in ['prepare_display_lookahead.py','prepare_writer_credit.py','qualify_lookahead.py','prepare_shared_service_check.py','reproduce_display.py','decode_board_hud.py']:
            shutil.copy2(submission/n,out/'tools'/n)
        shutil.copy2(submission/'LOOKAHEAD_ACCEPTANCE.md',out/'四行预取复验步骤.md')
        shutil.copy2(submission/'PORTABLE_REPRODUCTION.md',out/'新目录复现步骤.md')
        copy_rx_fallback(out)
        with (out/'README.md').open('a',encoding='utf-8') as f:f.write('\n本版的新目录仿真/工程复现入口见“新目录复现步骤.md”，使用tools/reproduce_display.py；不要用历史父版生成器替代当前回归。已验证RX-only回退码流及证据见fallback/rx_only。\n')
        shutil.copy2(Path('D:/FPGA/output/lookahead_release_gate_tests_20261023_v5.log'),out/'validation/release_gate_tests.log')
        (out/'离线检查与待验收项.md').write_text('# 四行前瞻候选：离线资格与实板待验收\n\n码流SHA256：`'+q['bitstream_sha256']+'`。最终100行时序通过；完整源码与匹配PDS工程已核对。B、RX、DDR engine及帧归属控制未改变。\n\n改动：显示器采用4物理行、最多提前3行取数，完整行ACK后才可见，保留帧/银行/模式/行号匹配及当前扫描银行写保护；继承状态字库修正。\n\n本版显示器的新回归：1920×1080共享RAW稀疏长等待模型旧版第3行缺黑像素，新版同激励通过4147200像素；完整校正链路通过14515200像素、两幅变化内容校正图；本版六幅变化图另核对64281600显示像素，短时仿真约10.0146张/秒。迟到响应/模式切换/硬复位及前消隐窗口中途换帧/种子代号回绕通过。更密的每16事务长等待模型仍缺行；这些频率是假设，不代表实板服务分布。\n\n父版本六幅回归等记录只支持字节不变的数学/采集/内存协议模块，不能当作本版显示器的六幅回归；本版已新增独立六幅记录，见validation/display_lookahead/continuous6，未作为实板结果。实板白灰和RX预览是否连续更新仍未验收，此新码流尚未上板，不是已修复或可交赛成品。正式标定、光学与画质、实测吞吐/延迟、长时间稳定性、纸框局部校正等缺项仍保留。\n\n诊断控制：默认干净有效图，双键稳定50ms切换诊断，长停更及原有故障提示保留。实板由烧录窗口统一CRAM Program/Verify；不要写Flash。\n',encoding='utf-8')
        with (out/'README.md').open('a',encoding='utf-8') as f:f.write('\n当前发布为四行前瞻显示候选，以“离线检查与待验收项.md”和release/qualification.json的本版说明为准。父版本六幅数据通路记录不是当前显示器的六幅资格；本版新增RAW/完整校正、六幅连续变化图及迟到换帧回归记录见validation/display_lookahead。仅改善已复现的服务间隙模型，实板白灰尚待受控验收。\n')
        if 'writer_credit' in source_manifest:
            proof=q['writer_credit_regression'];test=Path(proof['directory'])
            verify_writer_credit_evidence(test,proof)
            dst=out/'validation/writer_credit';dst.mkdir()
            shutil.copy2(test/'verification.json',dst/'verification.json')
            for mode in proof['records']:
                (dst/mode).mkdir()
                for n in ['ddr_result_writer_burst64.v','tb_writer_burst.sv','step1.log','step2.log']:shutil.copy2(test/mode/n,dst/mode/n)
            for n in ['prepare_credit_board.py','prepare_credit_regression.py']:shutil.copy2(submission/n,out/'tools'/n)
            metrics=json.loads(Path(q['display_regressions']['continuous6']['metrics_path']).read_text())
            (out/'离线检查与待验收项.md').write_text('# 四行预取与ACK授权寄存候选\n\n码流SHA256：`'+q['bitstream_sha256']+'`。最终100行时序通过；完整源码及PDS工程已核对。B数学、RX、DDR engine、时钟和约束保持；显示器及结果writer有改动，各自有新回归。\n\n显示器采用4物理行、最多提前3行取数，保留整行完成、帧/银行/模式/行号匹配和扫描银行保护。结果writer登记独占ACK空位许可，在ACK写入同拍撤销许可，切断实时满信号至命令有效的组合路径；每次响应后可能增加一个UI拍重新授权。\n\n当前组合版本共享RAW稀疏等待模型核对4147200像素，完整校正核对14515200像素，两幅变化内容通过；六幅连续变化核对64281600显示像素。新模型新结果率为'+str(metrics['new_result_fps_between_events'])+'张/秒，属于短时仿真，不能作为实板FPS。迟到/模式/复位/中途发布/epoch回绕沿用相同显示器的独立回归；writer另检查异步时钟、背压稳定、ACK满/恢复、零延迟响应、abort/epoch及共同复位。每16事务长等待模型仍缺行，不代表任意带宽下均可工作。\n\n父版本记录仅支持字节未变的模块，不能替代新版显示器和writer的回归。旧完整码流的实板白灰问题尚未由本候选实测验收；当前独立RX-only预览已由用户确认运动跟随。正式标定、画质与光学指标、实际新图率/延迟、长时间运行、局部纸框与框外保持等未完成。\n\n按“四行预取复验步骤.md”由烧录窗口独占硬件，CRAM Program/Verify，不写Flash。此包是待验收候选，不能称为可交赛成品。\n',encoding='utf-8')
        if 'cache_decision' in source_manifest:
            import sys
            sys.path.insert(0,str(submission))
            from cache_evidence import verify_cache_archive
            proof=q['cache_decision_regression'];test=Path(proof['directory'])
            safe_files=verify_cache_archive(test,proof)
            dst=out/'validation/cache_decision';dst.mkdir()
            for name in safe_files:
                target=dst/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(test/name,target)
            for n in ['cache_evidence.py','prepare_cache_decision.py','prepare_cache_board.py','prepare_cache_regression.py']:shutil.copy2(submission/n,out/'tools'/n)
            with (out/'离线检查与待验收项.md').open('a',encoding='utf-8') as f:f.write('\n本包另包含缓存决策路径拆分：L阶段保存保护位图、替换指针和缺失角标，在原有fill_start拍计算同顺序五候选victim及L快照tag；接口、命中/缺失周期和事务顺序保持。此缓存不继承父版缓存资格：包内包含旧/新64行和8行同激励逐拍等价证据，并用当前显示器、writer、cache重新完成上述三组整链路回归。逐拍等价不能替代当前PDS最终报告或实际DDR PHY数据验收。\n')
        if 'native_payload' in source_manifest:
            from native_evidence import verify_native_archive
            proof=q['native_payload_regression'];test=Path(proof['directory']);safe_files=verify_native_archive(test,proof)
            dst=out/'validation/native_payload';dst.mkdir()
            for name in safe_files:
                target=dst/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(test/name,target)
            for n in ['native_evidence.py','prepare_native_payload.py','prepare_payload_board.py','prepare_payload_regression.py']:shutil.copy2(submission/n,out/'tools'/n)
            with (out/'离线检查与待验收项.md').open('a',encoding='utf-8') as f:f.write('\n本包另开启默认关闭的BIST_ONLY_NATIVE_WDATA静态参数：只在core和engine的capture均为8时，将native单拍写数据直送BIST；视频capture/result仍使用原独立8beat数据总线，valid/地址/byte mask/owner/响应不改。未来新增native写客户时必须撤销或扩展此契约。当前整链路bench实际开启参数1；专项分别跑旧版、新版开启、新版默认、非法参数guard，使用真实core/BIST/engine并在客户边界注入，非真实PHY或相机验证。\n')
    files={p.relative_to(out).as_posix():sha(p) for p in out.rglob('*') if p.is_file()}
    (out/'MANIFEST_SHA256.json').write_text(json.dumps(files,indent=2)+'\n')
    for n,h in files.items():require(sha(out/n)==h,'Delivery copy drift '+n)
    archive=out.with_suffix('.zip');require(not archive.exists(),'Preserve existing zip')
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
        for p in out.rglob('*'):
            if p.is_file():z.write(p,out.name+'/'+p.relative_to(out).as_posix())
    with zipfile.ZipFile(archive) as z:require(z.testzip() is None,'Archive CRC failed')
    print('DELIVERY_VERIFIED',out,'ZIP_SHA256',sha(archive))
if __name__=='__main__':main()
