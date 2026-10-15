`timescale 1ns/1ps
module tb_writer_full;
reg clk=0,ui_clk=0;
always #5 clk=~clk;
always #3 ui_clk=~ui_clk;
reg rst_n=0,ui_rst_n=0,frame_start=0,abort_frame=0,frame_bank=0,write_valid=0;
reg[23:0]write_addr=0,write_rgb=0;wire write_ready,drained,fault,cmd_valid,cmd_write;
reg cmd_ready=1,rsp_valid=0,rsp_write=1;wire[27:0]cmd_addr;wire[255:0]cmd_wdata;wire[31:0]cmd_wstrb;
integer beat=0,frame=0,p=0,l=0,total=0,cycles=0,stalls=0;reg[27:0]wanted;reg[31:0]pixel;
ddr_result_writer_stream dut(.*);
always @(posedge ui_clk)begin
 if(!ui_rst_n)rsp_valid<=0;
 else begin
  rsp_valid<=cmd_valid&&cmd_ready;
  if(cmd_valid&&cmd_ready)begin
   wanted=(frame==0?28'h200000:28'h400000)+beat*8;
   if(cmd_addr!==wanted||cmd_wstrb!==32'hffffffff||!cmd_write)$fatal(1,"full frame address/strobe mismatch");
   for(l=0;l<8;l=l+1)begin pixel={8'b0,24'h100000+(beat*8+l)};if(cmd_wdata[l*32+:32]!==pixel)$fatal(1,"full frame RGB/padding mismatch");end
   beat=beat+1;total=total+1;
  end
 end
end
initial begin
 #30;rst_n=1;ui_rst_n=1;repeat(10)@(negedge clk);
 for(frame=0;frame<2;frame=frame+1)begin
  beat=0;@(negedge clk);frame_bank=frame;frame_start=1;@(negedge clk);frame_start=0;
  for(p=0;p<768*1080;p=p+1)begin
   write_valid=1;write_addr=p;write_rgb=24'h100000+p;frame_bank=~frame_bank;#1;
   while(!write_ready)begin @(negedge clk);stalls=stalls+1;end
   @(posedge clk);#1;@(negedge clk);
  end
  write_valid=0;while(!drained)@(negedge clk);
  if(fault||beat!=768*1080/8)$fatal(1,"full frame did not complete");
  $display("PASS default 768x1080 frame=%0d beats=%0d source_stalls=%0d",frame,beat,stalls);
 end
 if(stalls!=0)$fatal(1,"continuous source had avoidable bubbles");
 $display("PASS two default frames, every RGB/padding/address checked, 1 pixel/source clock, total_beats=%0d",total);$finish;
end
initial begin #30000000;$display("p=%0d frame=%0d beat=%0d ready=%b fault=%b expected=%0d owned=%0d",p,frame,beat,write_ready,fault,dut.expected_addr,dut.owned);$fatal(1,"full frame watchdog");end
endmodule


