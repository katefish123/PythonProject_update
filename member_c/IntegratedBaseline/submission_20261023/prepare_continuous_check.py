"""Prepare tests only: keep every qualified production RTL byte unchanged."""
from pathlib import Path
import argparse,hashlib,json,shutil

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--baseline',type=Path,required=True)
    ap.add_argument('--previous-test',type=Path,required=True)
    ap.add_argument('--fixtures',type=Path,required=True)
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--frames',type=int,default=6)
    a=ap.parse_args()
    if a.frames<3:raise ValueError('Use at least three publications')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    q=json.loads((a.baseline/'release/qualification.json').read_text())
    if not q['timing_qualified']:raise ValueError('Unqualified baseline')
    a.output.mkdir(parents=True,exist_ok=False)
    snap=a.output/'source_snapshot';shutil.copytree(a.previous_test/'source_snapshot',snap)
    for p in snap.iterdir():
        if p.name!='tb_lens_board.sv' and sha(p)!=q['candidate_source_sha256'].get(p.name):raise ValueError('Production drift '+p.name)
    p=snap/'tb_lens_board.sv';s=p.read_text()
    declaration=' function[23:0]pattern(input integer g,x,y);'
    s=s.replace(declaration,''' // Channel permutation commutes exactly with the channel-independent
 // bilinear arithmetic, extending the independent golden images without
 // deriving expected pixels from DUT responses.
 function[23:0]permute(input[23:0]v,input integer g);
 case((g/2)%6)
 0:permute=v;
 1:permute={v[15:8],v[7:0],v[23:16]};
 2:permute={v[7:0],v[23:16],v[15:8]};
 3:permute={v[23:16],v[7:0],v[15:8]};
 4:permute={v[15:8],v[23:16],v[7:0]};
 5:permute={v[7:0],v[15:8],v[23:16]};
 endcase endfunction
'''+declaration)
    old="pattern=CORRECTED?(BAD_FRAME>0&&g==BAD_FRAME?24'hb0b0b0:g%2==0?source_alt[y*SW+x]:source_fixture[y*SW+x]):RGB_PATTERN?{r,gc,b}:{v,v,v};"
    new="pattern=CORRECTED?(BAD_FRAME>0&&g==BAD_FRAME?24'hb0b0b0:permute(g%2==0?source_alt[y*SW+x]:source_fixture[y*SW+x],g)):RGB_PATTERN?{r,gc,b}:{v,v,v};"
    if s.count(old)!=1:raise ValueError('Unexpected camera pattern')
    s=s.replace(old,new)
    s=s.replace('expected_pixel=g%2==0?expected_alt[index]:expected_fixture[index];','expected_pixel=permute(g%2==0?expected_alt[index]:expected_fixture[index],g);')
    s=s.replace('D:/FPGA/output/b_lens_board_fixtures_20261022',a.fixtures.resolve().as_posix())
    marker=' integer checked=0,scans=0,seen_pub=0'
    profile=''' longint proc_busy_ticks=0,request_stall_ticks=0,write_stall_ticks=0;
 longint ui_ticks_profile=0,cache_blocked_ticks=0,cache_fill_ticks=0;
 longint cache_command_wait_ticks=0,cache_memory_wait_ticks=0;
 always @(posedge proc_clk)if(rst_n)begin
  if(dut.stream_path.p_busy)proc_busy_ticks++;
  if(dut.stream_path.q_valid&&!dut.stream_path.q_ready)request_stall_ticks++;
  if(dut.stream_path.write_valid&&!dut.stream_path.write_ready)write_stall_ticks++;
 end
 always @(posedge ui_clk)if(rst_n)begin
  ui_ticks_profile++;
  if(dut.stream_path.req_valid&&!dut.stream_path.req_ready)cache_blocked_ticks++;
  if(dut.stream_path.cache.fill_state!=0)cache_fill_ticks++;
  if(dut.stream_path.cache.fill_state==1&&!dut.stream_path.g_ready)cache_command_wait_ticks++;
  if(dut.stream_path.cache.fill_state==2)cache_memory_wait_ticks++;
 end
'''
    if s.count(marker)!=1:raise ValueError('Unexpected scoreboard')
    s=s.replace(marker,profile+marker)
    s=s.replace(' $display("PASS RAW_PIPELINE', ''' $display("PROFILE PROC busy=%0d request_stall=%0d write_stall=%0d",proc_busy_ticks,request_stall_ticks,write_stall_ticks);
 $display("PROFILE UI ticks=%0d cache_blocked=%0d cache_fill=%0d command_wait=%0d memory_wait=%0d",ui_ticks_profile,cache_blocked_ticks,cache_fill_ticks,cache_command_wait_ticks,cache_memory_wait_ticks);
 $display("PASS RAW_PIPELINE''')
    p.write_text(s)
    hashes={p.name:sha(p) for p in snap.iterdir()}
    fixtures=json.loads((a.fixtures/'manifest.json').read_text())
    for n,h in fixtures['fixtures_sha256'].items():
        if sha(a.fixtures/n)!=h:raise ValueError('Fixture drift '+n)
    binding=dict(production_sha256={n:h for n,h in hashes.items() if n!='tb_lens_board.sv'},testbench_sha256=sha(p),qualified_bitstream_sha256=q['bitstream_sha256'],frames=a.frames,fixtures=fixtures,hardware_acceptance=False)
    (a.output/'binding.json').write_text(json.dumps(binding,indent=2)+'\n')
    (a.output/'run.ps1').write_text("$ErrorActionPreference='Stop'\n& D:/softwares/modelsim/win64/vlib.exe work *> library.log\n$files=(Get-ChildItem source_snapshot -File).FullName\n& D:/softwares/modelsim/win64/vlog.exe -sv @files *> compile.log\nif($LASTEXITCODE -ne 0){throw 'Compile failed'}\n"+f"& D:/softwares/modelsim/win64/vsim.exe -c -do 'onfinish stop;run -all;quit -f' work.tb_raw_pipeline -gFRAMES={a.frames} *> simulation.log\n"+"if($LASTEXITCODE -ne 0 -or -not(Select-String simulation.log -Pattern 'PASS RAW_PIPELINE' -Quiet)){throw 'Simulation failed'}\nGet-Content simulation.log | Select-String 'PASS RAW_PIPELINE|PIPELINE_PUBLICATION|PROFILE|Errors:'\n")
    print(a.output)

if __name__=='__main__':main()
