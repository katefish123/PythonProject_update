`timescale 1ns/1ps
module config_pll_27m_10m(input clkin1,output reg clkout0=0,output lock);
always #50 clkout0=~clkout0;
assign lock=1'b1;
endmodule
module hdmi_config #(parameter TX_FIRST=0)(input cfg_clk,reset_n,output rx_done,tx_done,scl,ack_error,config_error,startup_retry_seen,inout sda); assign rx_done=reset_n;assign tx_done=reset_n;assign scl=1;assign sda=1'bz;assign ack_error=0;assign config_error=0;assign startup_retry_seen=0; endmodule
module tb_hdmi_camera_native;
parameter MISSING_VS=0;
parameter [11:0] H_FRONT=88;
reg pc=0,sc=0,rst=0;
always #3.367 pc=~pc;
always #18.518 sc=~sc;
wire [11:0] h,v;
wire de,hs,vs,oc,ode,ohs,ovs,ready,txdone,rxdone,scl;
wire [23:0] pixel={h[7:0],v[7:0],(h[7:0]^v[7:0])};
wire [23:0] output_pixel;
tri sda;
video_timing_vtc #(.H_FRONT(H_FRONT)) timing(.clk(pc),.rst_n(ready),.h_cnt(h),.v_cnt(v),.de(de),.hsync(hs),.vsync(vs));
hdmi_camera_passthrough_top dut(.sys_clk_27m(sc),.rst_n(rst),.hd_rx_pclk(pc),
 .hd_rx_vs(MISSING_VS ? 1'b0 : vs),.hd_rx_hs(hs),.hd_rx_de(de),.hd_rx_data(pixel),
 .hd_tx_pclk(oc),.hd_tx_vs(ovs),.hd_tx_hs(ohs),.hd_tx_de(ode),.hd_tx_data(output_pixel),
 .hd_reset_n(ready),.hd_scl(scl),.led(),.hd_sda(sda));
reg [23:0] expect0,expect1;
reg [2:0] sync0,sync1;
integer warmup=0,pixels=0,frames=0;
reg previous_vs=0,test_failed=0;
integer test_passed=0;
always @(posedge pc)if(ready)begin
 expect0<=pixel;expect1<=expect0;
 sync0<={vs,hs,de};sync1<=sync0;warmup=warmup+1;
end
always @(negedge pc)if(ready && warmup>8)begin
 if({ohs,ode}!==sync1[1:0] || (!MISSING_VS && ovs!==sync1[2]) || (ode && output_pixel!==expect1))begin
  test_failed=1;$display("FAIL_NATIVE_ALIGNMENT expected_sync=%b actual=%b pixel=%h expected=%h",sync1,{ovs,ohs,ode},output_pixel,expect1);$finish;
 end
 if(ovs && !previous_vs)begin
  if(frames>0 && pixels!=2073600)begin
   test_failed=1;$display("FAIL_NATIVE_PIXEL_COUNT %d",pixels);$finish;
  end
  pixels=0;frames=frames+1;
  if(frames==3)begin test_passed=1;$display("PASS_NATIVE_ALL_PIXELS frames=2 pixels_per_frame=2073600");$finish;end
 end
 if(ode)pixels=pixels+1;
 previous_vs=ovs;
end
initial begin #200;rst=1;end
initial begin #70000000;test_failed=1;$display("FAIL_NATIVE_TIMEOUT");$finish;end
endmodule
