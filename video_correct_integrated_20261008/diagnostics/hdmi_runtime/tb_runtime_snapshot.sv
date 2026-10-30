`timescale 1ns/1ps
module tb_runtime_snapshot;
 reg sys_clk_27m=0,rst_n=0,rx_enable=0,hd_rx_pclk=0;
 reg hd_rx_vs=0,hd_rx_hs=0,hd_rx_de=0;
 reg [23:0] hd_rx_data=24'h123456;
 wire hd_tx_pclk,hd_reset_n,hd_scl,hd_tx_vs,hd_tx_hs,hd_tx_de;
 wire [23:0] hd_tx_data;
 wire [7:0] led;
 tri1 hd_sda;
 integer h=0,v=0,frames=0;
 integer test_failed=0;
 always #5 sys_clk_27m=~sys_clk_27m;
 always #3 if(rx_enable)hd_rx_pclk=~hd_rx_pclk;else hd_rx_pclk=0;
 always @(negedge hd_rx_pclk) if(rx_enable)begin
  if(h==23)begin h=0;if(v==7)v=0;else v=v+1;end else h=h+1;
  hd_rx_hs=(h<2);hd_rx_vs=(v==0);
  hd_rx_de=(v>=2&&v<6&&h>=4&&h<20);
 end
 hdmi_runtime_probe_top dut(.*);
 task tick_frames(input integer n);
  repeat(n)begin @(posedge dut.raw_vs);@(negedge sys_clk_27m);end
 endtask
 task require(input logic condition,input string message);
  if(!condition)begin test_failed=1;$display("TEST_FAIL %s word=%064h",message,dut.status_frame);$finish;end
 endtask
 initial begin
  #100 rst_n=1;
  wait(hd_reset_n===1'b1);
  tick_frames(4);
  repeat(20)begin
   tick_frames(1);
   require(dut.status_frame[255:240]===16'hD103,"signature");
   require(dut.status_frame[223:192]===32'h02020304,"config bundle field mapping");
   require(dut.status_frame[183:176]===8'h56,"device byte mapping");
   require(dut.status_frame[175:160]===16'h209F,"register address mapping");
   require(dut.status_frame[225]===1'b1,"config snapshot returns without RX clock");
   require(dut.status_frame[224]===1'b0,"absent RX clock never falsely acknowledges");
   require(dut.status_frame[231]===1'b0,"absent RX clock detection");
   require(dut.status_frame[95:8]===88'd0,"absent RX bundle remains zero");
  end
  $display("TEST_PASS_NO_RX_CLOCK");
  rx_enable=1;
  tick_frames(12);
  require(dut.status_frame[224]===1'b1,"RX snapshot returns after clock starts");
  require(dut.status_frame[231]===1'b1,"clock detected after start");
  require(dut.status_frame[230:228]===3'b111,"DE VS HS all observed");
  require(dut.status_frame[95:80]===16'd16,"completed DE width");
  require(dut.status_frame[79:64]===16'd4,"completed active frame height");
  require(dut.status_frame[63:48]===16'd24,"HS period");
  require(dut.status_frame[31:8]===24'h123456,"RGB sample");
  $display("TEST_PASS_RX_GEOMETRY_AND_CDC");
  @(negedge hd_rx_pclk);rx_enable=0;
  tick_frames(5);
  repeat(20)begin tick_frames(1);require(dut.status_frame[224]===1'b0,"stopped RX clock pending request cannot alias");end
  $display("TEST_PASS_STOPPED_RX_CLOCK");
  rx_enable=1;tick_frames(12);
  require(dut.status_frame[224]===1'b1,"RX snapshot recovers after resumed clock");
  require(dut.status_frame[95:80]===16'd16,"width remains correct after resume");
  $display("TEST_PASS_RESUMED_RX_CLOCK");
  $finish;
 end
 initial begin #2000000;test_failed=1;$display("TEST_FAIL_TIMEOUT");$finish;end
endmodule
module video_pll_27m_148m5(input clkin1,output clkout0,output reg lock=0);
 assign clkout0=clkin1;initial #20 lock=1;
endmodule
module config_pll_27m_10m(input clkin1,output clkout0,output reg lock=0);
 assign clkout0=clkin1;initial #20 lock=1;
endmodule
module hdmi_config_runtime_diag #(parameter TX_FIRST=0)(
 input cfg_clk,reset_n,output rx_done,tx_done,scl,ack_error,config_error,startup_retry_seen,
 inout sda,output [143:0] debug_word);
 assign rx_done=0;assign tx_done=reset_n;assign scl=1;assign sda=1'bz;
 assign ack_error=0;assign config_error=0;assign startup_retry_seen=0;
 assign debug_word=reset_n?{8'h24,32'h02020304,8'h81,8'h56,16'h209F,8'hA5,
  8'hB2,16'h0003,16'h0004,16'h1234,8'h02}:144'd0;
endmodule
module video_timing_vtc #(parameter H_SYNC=44,H_BACK=148,H_ACTIVE=1920,H_FRONT=88,
 V_SYNC=5,V_BACK=36,V_ACTIVE=1080,V_FRONT=4)(
 input clk,rst_n,output [11:0] h_cnt,v_cnt,output hsync,vsync,de);
 reg [7:0] counter;
 always @(posedge clk or negedge rst_n)if(!rst_n)counter<=0;else counter<=counter+1'b1;
 assign h_cnt=12'd192+{4'd0,counter};assign v_cnt=12'd41;
 assign hsync=counter<2;assign vsync=counter<3;assign de=counter>=4;
endmodule
