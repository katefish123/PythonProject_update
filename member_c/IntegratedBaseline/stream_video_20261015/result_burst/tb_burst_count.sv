`timescale 1ns/1ps
module tb_burst_count;
reg clk=0,ui_clk=0;always #9.259259 clk=~clk;always #4 ui_clk=~ui_clk;
reg rst_n=0,ui_rst_n=0,frame_start=0,abort_frame=0,frame_bank=0,write_valid=0;wire write_ready,drained,fault,cmd_valid,cmd_write,cmd_write_block;reg cmd_ready=1,rsp_valid=0,rsp_write=1;
reg[23:0]write_addr=0,write_rgb=0;wire[27:0]cmd_addr;wire[255:0]cmd_wdata;wire[31:0]cmd_wstrb;wire[2047:0]cmd_block_data;
integer commands=0,p;
`ifdef LEGACY
 ddr_result_writer #(.OUT_W(64),.OUT_H(1),.BASE0(28'h200000),.BASE1(28'h400000)) dut(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),.abort_frame(abort_frame),.frame_bank(frame_bank),.write_valid(write_valid),.write_ready(write_ready),.write_addr(write_addr),.write_rgb(write_rgb),.drained(drained),.fault(fault),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_write(cmd_write),.cmd_addr(cmd_addr),.cmd_wdata(cmd_wdata),.cmd_wstrb(cmd_wstrb),.rsp_valid(rsp_valid),.rsp_write(rsp_write));
 always @(posedge clk)rsp_valid<=cmd_valid&&cmd_ready;
 always @(posedge clk)if(cmd_valid&&cmd_ready)commands=commands+1;
`else
 ddr_result_writer_burst64 #(.OUT_W(64),.OUT_H(1)) dut(.*);
 always @(posedge ui_clk)rsp_valid<=cmd_valid&&cmd_ready;
 always @(posedge ui_clk)if(cmd_valid&&cmd_ready)commands=commands+1;
`endif
initial begin
 #50;rst_n=1;ui_rst_n=1;repeat(10)@(negedge clk);frame_start=1;@(negedge clk);frame_start=0;
 for(p=0;p<64;p=p+1)begin write_valid=1;write_addr=p;write_rgb=p;#1;while(!write_ready)@(negedge clk);@(posedge clk);#1;write_valid=0;@(negedge clk);end
 while(!drained)@(negedge clk);
 $display("MEASURE64pixels sourceUIcommands=%0d desired=1",commands);
 if(commands!=1)$fatal(1,"64pixels must issue one8beat command");
 $display("PASS command reduction64pixels1command");$finish;
end
initial begin #1000000;$fatal(1,"count watchdog");end
endmodule
