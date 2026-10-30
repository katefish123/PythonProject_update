"""Verify the actual vendor PLL simulation model and bound clock constraints."""
from pathlib import Path
import datetime,hashlib,json,re,shutil,subprocess
ROOT=Path(__file__).resolve().parents[1]
R=ROOT/'candidate_host_angle_v2_product_stage';TOOLS=Path('C:/modeltech64_2020.4/win64')
MODEL=Path('C:/pango/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation/GTP_GPLL.v')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()

def main():
    out=ROOT/'verification'/('video_clocks_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
    pll=R/'sources/video_pll_27m_148m5.v';fdc=R/'sources/board_ddr.fdc';top=R/'sources/video_correct_ddr_top.v'
    assert 'create_clock -name processing_clock -period 10.774410' in fdc.read_text()
    assert 'create_clock -name pixel_clock -period 13.468013' in fdc.read_text()
    assert '.PROC_CYCLES_PER_MS(92813),.CAPTURE_TIMEOUT(185625000),.RETRY_CYCLES(928125)' in top.read_text()
    test=out/'tb_clocks.sv'
    test.write_text(r'''`timescale 1ns/1ps
module tb_clocks;
 reg clkin1=0;always #18.518518 clkin1=~clkin1;
 wire clkout0,clkout57,lock;video_pll_27m_148m5 dut(.*);
 realtime pp=0,pc=0,dp,dc;integer np=0,nc=0;
 always @(posedge clkout0)if(lock)begin
  dp=$realtime-pp;if(np>20&&(dp<13.466||dp>13.470))$fatal(1,"PIXEL_PLL_PERIOD %f",dp);
  pp=$realtime;np=np+1;
 end
 always @(posedge clkout57)if(lock)begin
  dc=$realtime-pc;if(nc>20&&(dc<10.772||dc>10.777))$fatal(1,"PROCESSING_PLL_PERIOD %f",dc);
  pc=$realtime;nc=nc+1;
 end
 initial begin
  wait(lock);wait(np>=1000&&nc>=1000);
  $display("VIDEO_CLOCKS_PASS pixel_mhz=74.25 processing_mhz=92.8125 pixel_period_ns=%f processing_period_ns=%f pixel_samples=%0d proc_samples=%0d",dp,dc,np,nc);$finish;
 end
 initial begin #2000000;$fatal(1,"PLL_LOCK_TIMEOUT");end
endmodule
''')
    inputs={str(p):sha(p) for p in [pll,fdc,top,MODEL,Path(__file__)]}
    (out/'inputs.json').write_text(json.dumps({'input_sha256':inputs,'bench_sha256':sha(test),'hardware_accessed':False},indent=2))
    ini=out/'modelsim.ini';shutil.copyfile(TOOLS.parent/'modelsim.ini',ini)
    def run(args,name):
        with (out/name).open('w') as log:r=subprocess.run([p.as_posix() if isinstance(p,Path) else str(p) for p in args],cwd=out,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        if r.returncode:raise RuntimeError(str(out/name))
    run([TOOLS/'vlib.exe',out/'work'],'library.log');run([TOOLS/'vmap.exe','-modelsimini',ini,'work',out/'work'],'mapping.log')
    run([TOOLS/'vlog.exe','-sv','-modelsimini',ini,MODEL,pll,test],'compile.log')
    do=out/'run.do';do.write_text('onerror {quit -code 2 -f}\nonbreak {resume}\nonfinish stop\nrun -all\nquit -f\n')
    try:run([TOOLS/'vsim.exe','-c','-modelsimini',ini,'work.tb_clocks','-do',do],'simulation.log')
    except RuntimeError:pass
    log=(out/'simulation.log').read_text(errors='replace')
    passed='VIDEO_CLOCKS_PASS' in log and not re.search(r'\*\* (?:Warning|Fatal|Error)(?:\s|:)',log)
    assert all(sha(p)==h for p,h in inputs.items())
    record={'passed':passed,'hardware_accessed':False,'inputs_sha256':sha(out/'inputs.json'),'simulation_log_sha256':sha(out/'simulation.log'),
            'observations':[v for v in log.splitlines() if '_PASS' in v or '** Warning' in v or '** Fatal' in v or '** Error' in v]}
    (out/'verification.json').write_text(json.dumps(record,indent=2));print(json.dumps({'directory':str(out),**record},indent=2))
    raise SystemExit(0 if passed else 1)

if __name__=='__main__':main()
