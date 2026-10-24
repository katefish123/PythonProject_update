"""Reproduce a packaged display test in a fresh directory; never accesses hardware."""
from pathlib import Path
import argparse,hashlib,json,re,shutil,subprocess

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok,message):
    if not ok:raise RuntimeError(message)

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--case',choices=['shared_raw_sparse','native_corrected','continuous6','late_mode_reset','midblank_wrap'],required=True)
    ap.add_argument('--output',type=Path,required=True);ap.add_argument('--modelsim',type=Path,default=Path('D:/softwares/modelsim/win64'))
    ap.add_argument('--prepare-only',action='store_true');a=ap.parse_args();root=a.package.resolve()
    q=json.loads((root/'release/qualification.json').read_text());record=q['display_regressions'][a.case]
    source=root/'validation/display_lookahead'/a.case/'source_snapshot'
    bench_name='tb_lens_board.sv' if a.case in ['shared_raw_sparse','native_corrected','continuous6'] else 'tb.sv'
    require(sha(source/bench_name)==record['testbench_sha256'],'Testbench evidence drift')
    for n,h in record['production_sha256'].items():require(sha(source/n)==h and sha(root/'sources'/n)==h,'Production drift '+n)
    fixtures=root/'validation/golden_fixtures'
    for n,h in q['fixtures']['fixtures_sha256'].items():require(sha(fixtures/n)==h,'Fixture drift '+n)
    a.output.mkdir(parents=True,exist_ok=False);shutil.copytree(source,a.output/'source_snapshot')
    tb=a.output/'source_snapshot'/bench_name;old_sha=sha(tb)
    text=tb.read_text().replace('D:/FPGA/output/b_lens_board_fixtures_20261022',fixtures.as_posix());tb.write_text(text)
    binding={'qualified_testbench_sha256':old_sha,'relocated_testbench_sha256':sha(tb),
        'change':'Fixture path relocation only','case':a.case,'hardware_accessed':False}
    (a.output/'relocation_binding.json').write_text(json.dumps(binding,indent=2)+'\n')
    files=[str(p.resolve()) for p in (a.output/'source_snapshot').iterdir() if p.suffix in ['.v','.sv','.vp']]
    module='tb_raw_pipeline' if bench_name!='tb.sv' else 'tb_raw_corrected'
    sim=[str(a.modelsim/'vsim.exe'),'-c','-do','onfinish stop;run -all;quit -f']
    if a.case=='shared_raw_sparse':sim+=['-gCORRECTED=0']
    if a.case=='continuous6':sim+=['-gFRAMES=6']
    sim+=['work.'+module]
    if not a.prepare_only:
        for name,cmd in [('library',[str(a.modelsim/'vlib.exe'),'work']),('compile',[str(a.modelsim/'vlog.exe'),'-sv',*files]),('simulation',sim)]:
            with (a.output/(name+'.log')).open('wb') as f:r=subprocess.run(cmd,cwd=a.output,stdout=f,stderr=subprocess.STDOUT)
            require(r.returncode==0,name+' process failed')
        log=(a.output/'simulation.log').read_text(errors='replace')
        require(record['pass_token'] in re.sub(r'\s+',' ',log) and 'Errors: 0, Warnings: 0' in log and not re.search(r'\*\* (Fatal|Error|Warning):',log),'Simulation did not pass')
        print('RELOCATED_DISPLAY_REGRESSION_PASS',a.case)
    else:print('RELOCATED_TEST_PREPARED; no simulation or hardware access')
