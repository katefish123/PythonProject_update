from pathlib import Path
import subprocess
r=Path(__file__).resolve().parent;c=r/'candidate_v2/sources';out=r/'observer_sim_v3';out.mkdir(exist_ok=False)
t=(c/'video_correct_ddr_top.v').read_text();body=t[t.index(' // Read-only diagnosis;'):t.index(' wire[1919:0]trace_data;')]
tb='''`timescale 1ns/1ps
module tb;
reg pix_clk=0,proc_clk57=0,ui_clk=0,clocks_ready=0,ui_rst=0;
always #3.367 pix_clk=~pix_clk;always #8.754 proc_clk57=~proc_clk57;always #4 ui_clk=~ui_clk;
reg scan_start=0,scan_reset_n=0,underrun=0,awvalid=0,awready=0,arvalid=0,arready=0,wready=0,rvalid=0;
reg[3:0]service_stage=0;
''' + body + '''
initial begin
#40;clocks_ready=1;ui_rst=1;
@(negedge pix_clk);scan_start=1;repeat(10)@(negedge pix_clk);
if(diag_scan_count!==0)$fatal(1,"Counted held-reset scan origin");
scan_reset_n=1;repeat(7)@(negedge pix_clk);scan_start=0;
@(negedge ui_clk);awvalid=1;awready=1;arvalid=1;arready=1;service_stage=1;
repeat(11)@(negedge ui_clk);awvalid=0;arvalid=0;service_stage=2;wready=1;
repeat(4)@(negedge ui_clk);service_stage=3;
repeat(13)@(negedge ui_clk);service_stage=4;rvalid=1;
repeat(5)@(negedge ui_clk);service_stage=0;underrun=1;
#3000;
if(diag_scan_count!==7||proc_scan_count!==7)$fatal(1,"PIX scan or CDC count");
if(proc_service_totals!=={32'd11,32'd11,32'd11,32'd13})$fatal(1,"service counts %h",proc_service_totals);
if(underrun_proc!==7)$fatal(1,"sticky observation not transferred");
clocks_ready=0;ui_rst=0;#3;
if(diag_scan_count!==0||diag_write_commands!==0||underrun_proc!==0)$fatal(1,"reset failed");
$display("PASS LIVE_DIAGNOSTIC_OBSERVERS clocks phases counters CDC reset");$finish;
end
initial begin #10000;$fatal(1,"timeout");end
endmodule
'''
(out/'tb.sv').write_text(tb)
commands=[['vlib.exe','work'],['vlog.exe','-sv',str(c/'snapshot_cdc.v'),'tb.sv'],['vsim.exe','-c','tb','-do','run -all;quit -f']]
for i,args in enumerate(commands):
 args[0]='D:/softwares/modelsim/win64/'+args[0]
 with (out/f'step{i}.log').open('w') as f:p=subprocess.run(args,cwd=out,stdout=f,stderr=subprocess.STDOUT)
 if p.returncode:raise RuntimeError('Simulation command failed')
text=(out/'step2.log').read_text()
assert 'PASS LIVE_DIAGNOSTIC_OBSERVERS' in text and 'Errors: 0, Warnings: 0' in text,text
print('PASS dynamic frozen observer block and CDC/reset')
