from pathlib import Path
import argparse,json,hashlib,shutil

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--candidate',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);args=ap.parse_args()
    top=args.candidate/'sources/video_correct_ddr_top.v';s=top.read_text()
    start=s.index(' assign overlay_on=');end=s.index(' assign preview_valid',start)
    if ' // BEGIN_PRESENTATION_POLICY' in s:start=s.index(' // BEGIN_PRESENTATION_POLICY')
    body=s[start:end]
    args.output.mkdir(parents=True,exist_ok=False)
    module='''`timescale 1ns/1ps
module presentation_policy #(parameter DIAGNOSTIC_HOLD_CYCLES=500000,PRESENTATION_STALE_FRAMES=30)(
input cfg_clk,pix_clk,cfg_rst,pix_rst,key1_pattern_n,key2_nearest_n,scan_start,image_valid,
input[4:0]pix_status,input status_on,telemetry_on,input[23:0]status_rgb,telemetry_rgb,input[31:0]debug_display_id,
output overlay_on,output[23:0]overlay_rgb,output[4:0]observed_status);
'''+('wire[4:0]presentation_status;\n' if 'assign presentation_status=' in body else '')+body+'\nassign observed_status='+('presentation_status' if 'presentation_status' in body else 'pix_status')+';\nendmodule\n'
    (args.output/'presentation_policy.v').write_text(module)
    shutil.copy2(Path(__file__).with_name('tb_presentation.sv'),args.output/'tb.sv')
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    (args.output/'binding.json').write_text(json.dumps({'top_sha256':sha(top),'extracted_sha256':sha(args.output/'presentation_policy.v'),'bench_sha256':sha(args.output/'tb.sv')},indent=2)+'\n')
    (args.output/'run.ps1').write_text("& D:/softwares/modelsim/win64/vlib.exe work *> library.log\n& D:/softwares/modelsim/win64/vlog.exe -sv presentation_policy.v tb.sv *> compile.log\n& D:/softwares/modelsim/win64/vsim.exe -c -do 'onfinish stop;run -all;quit -f' work.tb *> simulation.log\nGet-Content simulation.log -Tail 10\n")
if __name__=='__main__':main()
