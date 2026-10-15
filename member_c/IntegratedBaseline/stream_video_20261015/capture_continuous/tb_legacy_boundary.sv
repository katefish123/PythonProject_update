`timescale 1ns/1ps
module tb_legacy_boundary #(parameter NATIVE=0);
localparam W=128,H=48;
reg clk=0;always #3.367003367 clk=~clk;
reg rst_n=0,vs=0,de=0,request=1;reg[23:0]rgb=24'habcdef;
wire complete,okay;wire[3:0]reason;wire we;wire[284:0]data;
integer completed=0;reg seen=0;
ddr_snapshot_capture #(.IN_W(W),.IN_H(H),.SRC_W(W),.SRC_H(H)) dut(
.rx_clk(clk),.rx_rst_n(rst_n),.rx_vs(vs),.rx_de(de),.rx_rgb(rgb),.request_toggle(request),
.sample_valid(),.sample_first(),.sample_last(),.sample_token(),.fifo_full(1'b0),
.rx_complete_toggle(complete),.capture_ok(okay),.failure_reason(reason),.fifo_wr_en(we),.fifo_wr_data(data));
always @(posedge clk)if(rst_n&&complete!=seen)begin
seen<=complete;completed<=completed+1;request<=~request;
if(!okay)$fatal(1,"unexpected malformed legacy fixture reason=%0d",reason);
end
task frame;begin
@(negedge clk);vs=1;de=0;repeat(4)@(negedge clk);vs=0;
for(integer y=0;y<H;y=y+1)begin de=1;repeat(W)@(negedge clk);de=0;repeat(8)@(negedge clk);end
repeat(8)@(negedge clk);
end endtask
initial begin
repeat(4)@(negedge clk);rst_n=1;repeat(8)@(negedge clk);
repeat(6)frame();@(negedge clk);vs=1;repeat(12)@(negedge clk);
$display("LEGACY_NATIVE_BOUNDARIES=6 completed_captures=%0d",completed);
if(completed!=6)$fatal(1,"continuous frame admission missing: expected6 completed frames got%0d",completed);
$display("PASS legacy continuity");$finish;
end
endmodule

