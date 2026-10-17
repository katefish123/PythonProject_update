"""Isolated ALU resource/internal-timing probes, never board qualification."""
from pathlib import Path
import hashlib,json,shutil,sys
H=Path(__file__).resolve().parent
root=Path(sys.argv[1] if len(sys.argv)>1 else 'D:/FPGA/output/lens_alu_registered_probe_20261017_v2')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for name,source,top in [('reference',H.parent/'lens_model_next/q30_alu.v','q30_alu'),('fast',H/'q30_alu_fast.v','q30_alu_fast')]:
 out=root/name
 if out.exists():raise SystemExit('Use a new probe root; preserve old evidence')
 (out/'build').mkdir(parents=True)
 target=out/source.name;shutil.copyfile(source,target)
 wrapper=out/'q30_probe_top.v'
 wrapper.write_text('''module q30_probe_top(input wire clk,rst_n,start,input wire[1:0]op,input wire signed[63:0]a,b,
 output reg ready,done,error,output reg signed[63:0]value);
 reg start_q;reg[1:0]op_q;reg signed[63:0]a_q,b_q;
 wire ready_d,done_d,error_d;wire signed[63:0]value_d;
 @TOP@ dut(.clk(clk),.rst_n(rst_n),.start(start_q),.op(op_q),.a(a_q),.b(b_q),.ready(ready_d),.done(done_d),.error(error_d),.value(value_d));
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin start_q<=0;op_q<=0;a_q<=0;b_q<=0;ready<=0;done<=0;error<=0;value<=0;end
 else begin start_q<=start;op_q<=op;a_q<=a;b_q<=b;ready<=ready_d;done<=done_d;error<=error_d;value<=value_d;end
 end endmodule
'''.replace('@TOP@',top))
 fdc=out/'probe.fdc'
 fdc.write_text('create_clock -name processing_clock -period 17.508 [get_ports {clk}]\nset_false_path -from [get_ports {rst_n}]\n')
 script='set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676\n'
 script+=f'add_design {{{target.as_posix()}}}\nadd_design {{{wrapper.as_posix()}}}\nadd_constraint {{{fdc.as_posix()}}}\n'
 script+='compile -top_module q30_probe_top\nsynthesize -ads\ndev_map\npnr -gplace_seed 17 -groute_seed 17 -optimize_multi_corner_timing -slack_prior_in_global_router TRUE\nreport_timing\n'
 (out/'build.tcl').write_text(script)
 (out/'input_manifest.json').write_text(json.dumps({'probe_only':True,'board_timing_qualified':False,
  'scope':'Isolated ALU resource and same-clock internal timing; external IO delays and board pins are not defined; no bitstream generated.',
  'source_original':source.as_posix(),'source_sha256':sha(source),'frozen_source_sha256':sha(target),
  'wrapper_sha256':sha(wrapper),
  'fdc_sha256':sha(fdc),'tcl_sha256':sha(out/'build.tcl')},indent=2)+'\n')
 print('Prepared isolated probe',name)
