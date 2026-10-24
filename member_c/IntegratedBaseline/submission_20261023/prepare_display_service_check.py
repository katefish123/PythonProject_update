"""Bounded full-width display service stress; no physical timing inference."""
from pathlib import Path
import argparse,hashlib,json,shutil

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--profile',choices=['normal','sparse332','every332'],required=True);a=p.parse_args()
    root=Path(__file__).resolve().parents[1];base=Path('D:/FPGA/output/b_lens_board_presentation3_20261023/sources')
    original=root/'board_next_20261016/display/tb_raw_corrected.sv';text=original.read_text()
    text=text.replace('parameter NATIVE=0,LATE=0,PUBLINE=0','parameter NATIVE=1,LATE=0,PUBLINE=5')
    text=text.replace('OW=NATIVE?768:64,SH=NATIVE?1080:8','OW=NATIVE?1920:64,SH=NATIVE?32:8')
    delay={'normal':'28+(commands%7)','sparse332':'28+((commands%128==127)?304:0)','every332':'332'}[a.profile]
    text=text.replace('delay_left<=2+(commands%7)','delay_left<='+delay)
    text=text.replace('if(!LATE&&black_border==0)$fatal(1,"corrected black border not scored");','if(NATIVE&&black_border!=0)$fatal(1,"unexpected border in full-width result");')
    text=text.replace('PASS RAW_CORRECTED native=','PASS FULL_WIDTH_SERVICE profile='+a.profile+' native=')
    a.output.mkdir(parents=True,exist_ok=False);(a.output/'tb.sv').write_text(text)
    files=['ddr_result_display_raw_corrected.v','video_timing_vtc.v']
    for n in files:shutil.copyfile(base/n,a.output/n)
    sha=lambda x:hashlib.sha256(x.read_bytes()).hexdigest()
    (a.output/'binding.json').write_text(json.dumps({'profile':a.profile,'width':1920,'height':32,
        'scope':'Full-width line deadline test, abstract block responses; not fullHD video or hardware evidence',
        'production_sha256':{n:sha(base/n) for n in files},'original_test_sha256':sha(original),'testbench_sha256':sha(a.output/'tb.sv')},indent=2)+'\n')
    (a.output/'run.ps1').write_text("& D:/softwares/modelsim/win64/vlib.exe work *> library.log\n& D:/softwares/modelsim/win64/vlog.exe -sv ddr_result_display_raw_corrected.v video_timing_vtc.v tb.sv *> compile.log\n& D:/softwares/modelsim/win64/vsim.exe -c -do 'onfinish stop;run -all;quit -f' work.tb_raw_corrected *> simulation.log\nGet-Content simulation.log -Tail 9\n")
    print(a.output)
