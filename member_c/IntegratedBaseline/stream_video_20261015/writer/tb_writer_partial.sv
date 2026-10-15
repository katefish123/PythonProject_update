`timescale 1ns/1ps
module tb_writer_partial;
reg clk=0,ui_clk=0;always #5 clk=~clk;always #3 ui_clk=~ui_clk;
reg rst_n=0,ui_rst_n=0,frame_start=0,abort_frame=0,frame_bank=1,write_valid=0;
reg[23:0]write_addr=0,write_rgb=0;wire write_ready,drained,fault,cmd_valid,cmd_write;
reg cmd_ready=1;wire rsp_valid=cmd_valid&&cmd_ready;wire rsp_write=1;
wire[27:0]cmd_addr;wire[255:0]cmd_wdata;wire[31:0]cmd_wstrb;
integer beat=0,p,l;reg[255:0]expected;
ddr_result_writer_stream #(.OUT_W(3),.OUT_H(3),.FIFO_ADDR_BITS(2)) dut(.*);
always @(posedge ui_clk)if(cmd_valid&&cmd_ready)begin
 expected=0;
 if(beat==0)for(l=0;l<8;l=l+1)expected[l*32+:32]=l+24'h123400;
 else expected[31:0]=24'h123408;
 if(cmd_addr!==(28'h400000+beat*8)||cmd_wdata!==expected||cmd_wstrb!==(beat==0?32'hffffffff:32'h0000000f))$fatal(1,"partial final beat mismatch");
 beat=beat+1;
end
initial begin
 #30;rst_n=1;ui_rst_n=1;repeat(10)@(negedge clk);frame_start=1;@(negedge clk);frame_start=0;
 for(p=0;p<9;p=p+1)begin
  write_valid=1;write_addr=p;write_rgb=24'h123400+p;#1;
  while(!write_ready)@(negedge clk);
  @(posedge clk);#1;write_valid=0;@(negedge clk);
 end
 while(!drained)@(negedge clk);
 if(beat!=2||fault)$fatal(1,"partial frame completion");
 $display("PASS 9-pixel frame partial strobes/zero unused lanes and zero-latency UI response");$finish;
end
initial begin #100000;$fatal(1,"partial watchdog");end
endmodule
