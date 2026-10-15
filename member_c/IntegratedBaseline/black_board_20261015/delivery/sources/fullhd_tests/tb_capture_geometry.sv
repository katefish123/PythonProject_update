`timescale 1ns/1ps
module tb_capture_geometry;
 reg clk=0,pclk=0;always #3.367 clk=~clk;always #18.519 pclk=~pclk;
 reg rst=0,pv=0,pf=0,pl=0,token=0,bank=0,rx_done=0;
 reg [23:0] rgb=0;wire mt,mid,mb,mok;wire [95:0] corners;
 reg test_passed=0;integer publications=0;reg edge_pattern=0,dense=0;
 capture_geometry #(.SRC_W(16),.SRC_H(8),.MIN_PIXELS(1),.MAX_PIXELS(64),.MAX_SPAN(16),.FIFO_ADDR_BITS(2)) dut(
  .rx_clk(clk),.rx_rst_n(rst),.proc_clk(pclk),.proc_rst_n(rst),
  .sample_valid(pv),.sample_first(pf),.sample_last(pl),.sample_rgb(rgb),
  .sample_token(token),.sample_bank(bank),.rx_complete_toggle(rx_done),
  .metadata_toggle(mt),.metadata_token(mid),.metadata_bank(mb),.metadata_ok(mok),.metadata_corners(corners));
 task send(input integer missing,input integer short_frame);
  begin
   for(integer k=0;k<(short_frame?60:128);k=k+1)begin
    @(negedge clk);pv=1;pf=(k==0);pl=(k==127);rgb=dense?24'h0:24'h808080;
    if(k==(edge_pattern?0:17))rgb=0;
    if(k==(edge_pattern?15:30))rgb=0;
    if(k==(edge_pattern?127:110))rgb=0;
    if(k==(edge_pattern?112:97)&&!missing)rgb=0;
   end
   @(negedge clk);pv=0;pf=0;pl=0;
   repeat(4)@(negedge clk);rx_done=token;
   wait(mt==token);@(negedge pclk);
   if(mid!==token||mb!==bank||mok!==(missing==0&&short_frame==0&&!dense))$fatal(1,"filtered metadata bank/status mismatch");
   if(dense&&!dut.rx_overflow)$fatal(1,"dense overflow stimulus did not overflow");
   if(mok&&corners!==(edge_pattern?{12'd0,12'd0,12'd15,12'd0,12'd15,12'd7,12'd0,12'd7}:
      {12'd1,12'd1,12'd14,12'd1,12'd14,12'd6,12'd1,12'd6}))$fatal(1,"filtered centroid mismatch %h",corners);
   publications=publications+1;repeat(12)@(negedge pclk);
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst=1;repeat(20)@(negedge clk);
  token=1;bank=0;send(0,0);
  token=0;bank=1;send(1,0);
  token=1;bank=0;send(0,1);
  token=0;bank=1;send(0,0);
  edge_pattern=1;token=1;bank=0;send(0,0);
  dense=1;token=0;bank=1;send(0,0);
  dense=0;token=1;bank=0;send(0,0);
  if(publications!=7)$fatal(1,"filtered metadata transaction lost");
  test_passed=1;$display("CAPTURE_GEOMETRY_PASS filtered_original_B dual_clock edge_pixels short_frame FIFO_overflow recovery");$finish;
 end
 initial begin #300000;$fatal(1,"filtered geometry timeout");end
endmodule
