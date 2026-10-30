"""Audit all native timing rows and actual package/electrical IO bindings."""
from pathlib import Path
import argparse,hashlib,json,math,re
ROOT=Path(__file__).resolve().parents[1]
PARENT=Path('C:/D/FPGA/A_board_20261029/candidate_de_frame_guard_v2')
PARENT_TIMING=PARENT/'build/pds_selected_20261029_181422/report_timing/video_correct_ddr_top.rtr'
PARENT_IO=PARENT/'build/pds_selected_20261029_181422/input/selected_resources.prr'
PARENT_PINS=PARENT/'build/pds/place_route/video_correct_ddr_top_prr.prt'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()

def timing_rows(text,require_pass=True):
    if require_pass and ('Design Summary : All Constraints Met.' not in text or 'Design Summary : Some Constraints Violated.' in text):
        raise ValueError('Native report does not meet all constraints')
    for expected in ['PG2L100H','FBG676','2022.2-SP6.4','Timing analysis mode : multi corner']:
        if expected not in text:raise ValueError('Missing native target/version/mode: '+expected)
    sections=re.findall(r'(?m)^(Setup|Hold|Recovery|Removal|Minimum Pulse Width) Summary\((Slow|Fast) Corner\):\s*\n([\s\S]*?)(?=^={10,})',text)
    if len(sections)!=10 or len({(a,b) for a,b,_ in sections})!=10:raise ValueError('Missing or duplicated slow/fast timing section')
    rows=[];keys=set()
    for kind,corner,body in sections:
        count=0
        for line in body.splitlines():
            fields=line.split()
            if len(fields)<5:continue
            try:slack,total=float(fields[-4]),float(fields[-3]);fail,ends=int(fields[-2]),int(fields[-1])
            except ValueError:continue
            clocks=tuple(fields[:-4]);key=(kind,corner,clocks)
            if key in keys:raise ValueError('Duplicated timing row '+str(key))
            keys.add(key);count+=1
            if not all(math.isfinite(v) for v in [slack,total]) or ends<1 or fail<0 or fail>ends:raise ValueError('Invalid timing row '+line)
            if require_pass and (slack<0 or total<0 or fail):raise ValueError('Timing violation '+line)
            rows.append({'kind':kind,'corner':corner,'clocks':list(clocks),'slack_ns':slack,'total_slack_ns':total,'failing_endpoints':fail,'total_endpoints':ends})
        if not count:raise ValueError('Empty timing section '+kind+' '+corner)
    for kind in ['Setup','Hold','Recovery','Removal','Minimum Pulse Width']:
        if {tuple(v['clocks']) for v in rows if v['kind']==kind and v['corner']=='Slow'}!={tuple(v['clocks']) for v in rows if v['kind']==kind and v['corner']=='Fast'}:
            raise ValueError('Different slow/fast clock coverage for '+kind)
    return rows

def audit_timing(path,processing_period=10.774410):
    text=path.read_text(errors='replace');rows=timing_rows(text)
    baseline=timing_rows(PARENT_TIMING.read_text(errors='replace'))
    keys=lambda rr:{(r['kind'],r['corner'],tuple(r['clocks'])) for r in rr}
    a,b=keys(baseline),keys(rows)
    if not a<=b:raise ValueError('Baseline timing-clock coverage was removed: '+str(a-b))
    allowed={(kind,corner,('sys_clk_27m','sys_clk_27m')) for kind in ['Recovery','Removal'] for corner in ['Slow','Fast']}
    if not (b-a)<=allowed:raise ValueError('Unreviewed extra timing-clock rows: '+str(b-a))
    expected={'sys_clk_27m':37.037037,'rx_pixel':6.734007,'cfg_clock':100.,'processing_clock':processing_period,
              'pixel_clock':13.468013,'tx_pixel':13.468013,'ref_clk':8.,'rst_clk':8.,'ddrphy_sysclk':8.,
              'phy_dq_clk_0':1.,'phy_dq_clk_1':1.,'phy_dq_sysclk_0':8.,'phy_dq_sysclk_1':8.}
    for name,period in expected.items():
        m=re.search(r'(?m)^\s*'+re.escape(name)+r'\s+([0-9.]+)\s+\{',text)
        if not m or abs(float(m[1])-period)>.00011:raise ValueError('Clock period mismatch '+name)
    return {'passed':True,'report_sha256':sha(path),'baseline_sha256':sha(PARENT_TIMING),'rows':rows,
            'row_count':len(rows),'additional_reviewed_rows':[[a,b,list(c)] for a,b,c in sorted(b-a)],
            'minimum_slack_ns':min(v['slack_ns'] for v in rows),
            'minimum_setup_ns':min(v['slack_ns'] for v in rows if v['kind']=='Setup'),
            'minimum_hold_ns':min(v['slack_ns'] for v in rows if v['kind']=='Hold')}

def read_pinout(path):
    result={}
    for line in path.read_text(errors='replace').splitlines():
        f=[v.strip() for v in line.split('|')]
        if len(f)>=7 and f[4] and f[5] in ['input','output','inout']:
            match=re.match(r'^(?:DIFFIO|SIO)_([LR][0-9]+)_',f[3])
            if not match or f[4] in result:raise ValueError('Invalid/duplicated package pin '+line)
            result[f[4]]={'pad':f[0],'cell':f[1],'reported_bank':f[2],'function':f[3],'direction':f[5],'constrained':f[6],'physical_bank':'BANK'+match[1]}
    if len({r['pad'] for r in result.values()})!=len(result):raise ValueError('Two ports share one pad')
    return result

def io_props(path):
    result={}
    for line in path.read_text(errors='replace').splitlines():
        f=[v.strip() for v in line.split('|')[1:]]
        if len(f)>=21 and f[1] in ['input','output','inout']:
            if f[0] in result:raise ValueError('Duplicate IO row '+f[0])
            result[f[0]]=f[1:]
    return result

def audit_io(report,pins):
    a,b=io_props(PARENT_IO),io_props(report);pa,pb=read_pinout(PARENT_PINS),read_pinout(pins)
    if len(a)!=142 or set(a)!=set(pa) or set(b)!=set(pb) or set(b)!=set(a)|{'uart_rx','uart_tx'}:
        raise ValueError('Unexpected IO inventory')
    issues=[];normalized={}
    for label,props,physical in [('parent',a,pa),('current',b,pb)]:
        for name,row in props.items():
            pin=physical[name]
            if row[:2]!=[pin['direction'],pin['pad']]:raise ValueError('Electrical/package mismatch '+name)
            if row[2]!=pin['physical_bank']:issues.append({'report':label,'port':name,'reported':row[2],'physical':pin['physical_bank']})
        if any(v['report']==label for v in issues) and len({r[2] for r in props.values()})!=1:
            raise ValueError('Unreviewed nonuniform BANK-label mismatch')
    for name in a:
        for field in ['pad','cell','function','direction','constrained','physical_bank']:
            if pa[name][field]!=pb[name][field]:raise ValueError('Existing physical IO changed '+name+' '+field)
        ra,rb=a[name].copy(),b[name].copy();ra[2]=pa[name]['physical_bank'];rb[2]=pb[name]['physical_bank']
        if ra!=rb:raise ValueError('Existing electrical IO attribute changed '+name)
        normalized[name]=rb
    for name,pad,direction in [('uart_rx','B24','input'),('uart_tx','C24','output')]:
        pin=pb[name];row=b[name].copy();row[2]=pin['physical_bank']
        if row[:5]!=[direction,pad,'BANKL3','3.3','LVCMOS33'] or pin['constrained']!='YES' or 'YES' not in row[18:]:
            raise ValueError('UART pad/electrical binding mismatch '+name)
        normalized[name]=row
    return {'passed':True,'pad_count':len(b),'preserved_baseline_pads':len(a),'added_uart_pads':2,'normalized_io':normalized,
            'bank_label_discrepancies':issues,'input_sha256':{str(p):sha(p) for p in [report,pins,PARENT_IO,PARENT_PINS]}}

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--build',type=Path);ap.add_argument('--self-check',action='store_true');a=ap.parse_args()
    if a.self_check:
        text=PARENT_TIMING.read_text(errors='replace');assert len(audit_timing(PARENT_TIMING,13.468013)['rows'])==100
        mutants=[text.replace('35.151       0.000','-0.001       0.000',1),text.replace('Hold Summary(Fast Corner):','Hold Summary(Fast MUTATED):',1),text.replace('All Constraints Met.','Some Constraints Violated.',1)]
        for t in mutants:
            try:timing_rows(t)
            except ValueError:pass
            else:raise AssertionError('Timing mutant escaped')
        print('NATIVE_AUDITOR_SELF_CHECK_PASS baseline_rows=100 mutations_rejected=3');return
    if a.build is None:ap.error('--build is required')
    build=a.build.resolve();r=build.parents[1]
    record=json.loads((build/'offline_build_inputs.json').read_text())
    actual={p.name:sha(p) for p in (r/'sources').iterdir() if p.is_file()}
    if record['status']!='completed' or not record['sources_unchanged'] or record['source_sha256']!=actual:raise ValueError('Build not completed against current exact sources')
    failures=[];timing_path=build/'report_timing/video_correct_ddr_top.rtr'
    try:timing=audit_timing(timing_path)
    except ValueError as e:
        failures.append(str(e));rows=timing_rows(timing_path.read_text(errors='replace'),False)
        timing={'passed':False,'report_sha256':sha(timing_path),'negative_rows':[v for v in rows if v['slack_ns']<0 or v['failing_endpoints']],
                'row_count':len(rows),'minimum_slack_ns':min(v['slack_ns'] for v in rows)}
    try:io=audit_io(build/'place_route/video_correct_ddr_top.prr',build/'place_route/video_correct_ddr_top_prr.prt')
    except ValueError as e:failures.append(str(e));io={'passed':False,'error':str(e)}
    result={'passed':not failures,'hardware_accessed':False,'failures':failures,'timing':timing,'io':io,'source_sha256':actual,
            'native_inputs_sha256':sha(build/'offline_build_inputs.json'),'auditor_sha256':sha(Path(__file__))}
    (build/'native_audit.json').write_text(json.dumps(result,indent=2));print(json.dumps({'passed':result['passed'],'timing_rows':timing['row_count'],'minimum_slack_ns':timing['minimum_slack_ns'],'pads':io.get('pad_count'),'failures':failures},indent=2))
    if failures:raise SystemExit(1)

if __name__=='__main__':main()
