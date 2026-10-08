`timescale 1ns/1ps
module tb_hdmi_bram_probe;
reg wc=0,rc=0,rst=0,de=0,fs=0,re=0;
reg [23:0] pixel=0;reg [15:0] ra=0;
wire [23:0] q;wire valid;
reg test_failed=0;integer test_passed=0;
integer y,x,n;
always #5 wc=~wc;always #7.3 rc=~rc;
hdmi_bram_probe #(.SAMPLE_STEP(12),.FRAME_WORDS(4),.FRAME_GAP(8)) dut(.wr_clk(wc),.wr_reset_n(rst),.de(de),.pixel(pixel),.rd_clk(rc),.rd_reset_n(rst),.frame_start(fs),.rd_enable(re),.rd_addr(ra),.rd_pixel(q),.frame_valid(valid));
task send_frame;input [23:0] base;
begin
 for(y=0;y<24;y=y+1)begin
  for(x=0;x<24;x=x+1)begin @(negedge wc);de=1;pixel=base+(y<<8)+x;end
  @(negedge wc);de=0;repeat(3)@(negedge wc);
 end
end endtask
task advance_display;
begin repeat(5)@(negedge rc);fs=1;@(negedge rc);fs=0;repeat(3)@(negedge rc);end endtask
task check_pixels;input [23:0] base;
begin
 re=1;
 for(n=0;n<4;n=n+1)begin
  @(negedge rc);ra=n;repeat(2)@(negedge rc);
  if(q!==(base+((n/2)*12<<8)+(n%2)*12))begin test_failed=1;$display("FAIL_BRAM_PIXEL n=%d q=%h",n,q);$finish;end
 end
 re=0;
end endtask
initial begin
 #40;rst=1;repeat(15)@(negedge wc);
 send_frame(24'h100000);advance_display;
 if(!valid)begin test_failed=1;$display("FAIL_BRAM_VALID");$finish;end
 check_pixels(24'h100000);repeat(15)@(negedge wc);
 send_frame(24'h200000);
 // New frame remains separate until the display frame boundary.
 check_pixels(24'h100000);advance_display;check_pixels(24'h200000);
 rst=0;#20;if(valid!==0)begin test_failed=1;$display("FAIL_BRAM_RESET");$finish;end
 test_passed=1;$display("PASS_BRAM_TWO_CLOCKS_TWO_BANKS");$finish;
end
initial begin #100000;test_failed=1;$display("FAIL_BRAM_TIMEOUT");$finish;end
endmodule
