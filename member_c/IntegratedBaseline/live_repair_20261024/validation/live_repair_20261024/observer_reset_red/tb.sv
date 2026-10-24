`timescale 1ns/1ps
module tb;
reg pix_clk=0,proc_clk57=0,ui_clk=0,clocks_ready=0,ui_rst=0;
always #3.367 pix_clk=~pix_clk;always #8.754 proc_clk57=~proc_clk57;always #4 ui_clk=~ui_clk;
reg scan_start=0,scan_reset_n=0,underrun=0,awvalid=0,awready=0,arvalid=0,arready=0,wready=0,rvalid=0;
reg[3:0]service_stage=0;
 // Read-only diagnosis; no protection, memory command or timing outputs.
 reg[31:0]diag_scan_count;
 always @(posedge pix_clk or negedge clocks_ready)
 if(!clocks_ready)diag_scan_count<=0;else if(scan_start)diag_scan_count<=diag_scan_count+1'b1;
 wire[31:0]proc_scan_count;
 snapshot_cdc #(.WIDTH(32)) scan_observer(.s_clk(pix_clk),.d_clk(proc_clk57),.rst_n(clocks_ready),.s_data(diag_scan_count),.d_data(proc_scan_count),.d_valid());
 (* ASYNC_REG="TRUE" *)reg[2:0]underrun_proc;
 always @(posedge proc_clk57 or negedge clocks_ready)
 if(!clocks_ready)underrun_proc<=0;else underrun_proc<={underrun_proc[1:0],underrun};
 reg[31:0]diag_write_commands,diag_read_commands,diag_write_wait,diag_read_wait;
 always @(posedge ui_clk or negedge ui_rst)begin
 if(!ui_rst)begin diag_write_commands<=0;diag_read_commands<=0;diag_write_wait<=0;diag_read_wait<=0;end
 else begin
 if(awvalid&&awready)diag_write_commands<=diag_write_commands+1'b1;
 if(arvalid&&arready)diag_read_commands<=diag_read_commands+1'b1;
 if((service_stage==1||service_stage==2)&&!wready)diag_write_wait<=diag_write_wait+1'b1;
 if((service_stage==3||service_stage==4)&&!rvalid)diag_read_wait<=diag_read_wait+1'b1;
 end end
 wire[127:0]ui_service_totals={diag_write_commands,diag_read_commands,diag_write_wait,diag_read_wait};
 wire[127:0]proc_service_totals;
 snapshot_cdc #(.WIDTH(128)) service_totals_observer(.s_clk(ui_clk),.d_clk(proc_clk57),.rst_n(clocks_ready),.s_data(ui_service_totals),.d_data(proc_service_totals),.d_valid());

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
