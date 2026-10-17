`timescale 1ns/1ps
module tb_camera_live_bram;
reg sys_clk=0,rx_clk=0,rst_n=0,rx_vs=0,rx_hs=0,rx_de=0;
reg [23:0] rx_pixel=0;
wire tx_clk,tx_vs,tx_hs,tx_de,chip_reset,scl;
tri1 sda;
wire [23:0] tx_pixel;
wire [7:0] led;
integer test_passed=0,test_failed=0;
integer sx,sy,frame_number;
integer ox=0,oy=0,checked=0,tag=0;
reg de_prev=0,vs_prev=0,checking=0;
reg [23:0] expected;
always #18.518519 sys_clk=~sys_clk;
// 59.94-Hz input is asynchronous to the fixed 60-Hz output.
always #3.37037 rx_clk=~rx_clk;
camera_live_bram_top dut(.sys_clk_27m(sys_clk),.rst_n(rst_n),
 .hd_rx_pclk(rx_clk),.hd_rx_vs(rx_vs),.hd_rx_hs(rx_hs),.hd_rx_de(rx_de),
 .hd_rx_data(rx_pixel),.hd_tx_pclk(tx_clk),.hd_tx_vs(tx_vs),.hd_tx_hs(tx_hs),
 .hd_tx_de(tx_de),.hd_tx_data(tx_pixel),.hd_reset_n(chip_reset),.hd_scl(scl),
 .hd_sda(sda),.led(led));
function [23:0] source_pixel;
 input integer frame_id,y,x;
 begin source_pixel=(frame_id<<20)|((y/6)<<12)|((x/6)<<3);end
endfunction
initial begin
 #200;rst_n=1;
 for(frame_number=1;frame_number<7;frame_number=frame_number+1)begin
  for(sy=0;sy<1125;sy=sy+1)begin
   for(sx=0;sx<2200;sx=sx+1)begin
    @(negedge rx_clk);
    rx_vs=(sy<5);rx_hs=(sx<44);
    rx_de=(sy>=41 && sy<1121 && sx>=192 && sx<2112);
    rx_pixel=rx_de?source_pixel(frame_number,sy-41,sx-192):0;
   end
  end
 end
end
always @(negedge tx_clk)begin
 if(!rst_n)begin ox=0;oy=0;de_prev=0;vs_prev=0;checking=0;end
 else begin
  if(tx_vs&&!vs_prev)begin
   ox=0;oy=0;checked=0;tag=0;checking=dut.frame_valid;
  end
  if(tx_de&&checking)begin
   if(ox==0&&oy==0)tag=tx_pixel[23:20];
   expected=source_pixel(tag,oy,ox);
   if(tag<1 || tx_pixel!==expected)begin
    $display("FAIL_RAW_PREVIEW x=%0d y=%0d actual=%06h expected=%06h",ox,oy,tx_pixel,expected);
    test_failed=1;$finish;
   end
   ox=ox+1;checked=checked+1;
  end
  if(!tx_de&&de_prev&&checking)begin
   if(ox!=1920)begin test_failed=1;$display("FAIL_RAW_LINE width=%0d",ox);$finish;end
   ox=0;oy=oy+1;
   if(oy==1080)begin
    if(checked!=2073600)begin test_failed=1;$display("FAIL_RAW_FRAME_SIZE");$finish;end
    test_passed=1;
    $display("PASS_RAW_CAMERA_FULL_1080P_FRAME pixels=%0d input=59.94 output=60 tag=%0d",checked,tag);
    $finish;
   end
  end
  de_prev=tx_de;vs_prev=tx_vs;
 end
end
initial begin #150000000;test_failed=1;$display("FAIL_RAW_PREVIEW_TIMEOUT");$finish;end
endmodule

// Simulation-only PLL and configuration models; hardware build uses real IP.
module video_pll_27m_148m5(input clkin1,output reg clkout0=0,output reg lock=0);
always #3.3670035 clkout0=~clkout0;
initial #120 lock=1;
endmodule
module config_pll_27m_10m(input clkin1,output reg clkout0=0,output reg lock=0);
always #50 clkout0=~clkout0;
initial #120 lock=1;
endmodule
module hdmi_config_runtime_diag #(parameter TX_FIRST=1)(
input cfg_clk,reset_n,output rx_done,tx_done,scl,inout sda,
output ack_error,config_error,startup_retry_seen,output [143:0] debug_word);
assign rx_done=reset_n;assign tx_done=reset_n;assign scl=1;
assign ack_error=0;assign config_error=0;assign startup_retry_seen=0;
assign debug_word=0;
endmodule
