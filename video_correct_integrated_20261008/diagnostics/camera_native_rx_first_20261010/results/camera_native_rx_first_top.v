`timescale 1ns/1ps
`default_nettype none
// Full-resolution RGB888 preview: every real RX pixel reaches TX.
// Stream launch/VS recovery follows C's hdmi_camera_loop_top; shared I2C uses
// the integration project's startup retry fix. No image buffer or test pattern.
module camera_native_rx_first_top(
 input wire sys_clk_27m,rst_n,hd_rx_pclk,hd_rx_vs,hd_rx_hs,hd_rx_de,
 input wire [23:0] hd_rx_data,
 output wire hd_tx_pclk,hd_reset_n,hd_scl,inout wire hd_sda,
 output reg hd_tx_vs,hd_tx_hs,hd_tx_de,output reg [23:0] hd_tx_data,
 output wire [7:0] led
);
 wire cfg_clk,cfg_lock,cfg_rst_n,rx_rst_n;
 config_pll_27m_10m cp(.clkin1(sys_clk_27m),.clkout0(cfg_clk),.lock(cfg_lock));
 reset_sync cfg_reset(.clk(cfg_clk),.arst_n(rst_n&&cfg_lock),.rst_n(cfg_rst_n));
 reg [13:0] reset_count;
 always @(posedge cfg_clk or negedge cfg_rst_n) begin
  if(!cfg_rst_n)reset_count<=0;
  else if(reset_count<10000)reset_count<=reset_count+1'b1;
 end
 assign hd_reset_n=cfg_rst_n&&(reset_count==10000);
 wire rx_done,tx_done,ack_error,config_error,startup_retry_seen;
 hdmi_config #(.TX_FIRST(1'b0)) config_bus(.cfg_clk(cfg_clk),.reset_n(hd_reset_n),
  .rx_done(rx_done),.tx_done(tx_done),.scl(hd_scl),.sda(hd_sda),
  .ack_error(ack_error),.config_error(config_error),.startup_retry_seen(startup_retry_seen));
 reset_sync rx_reset(.clk(hd_rx_pclk),.arst_n(hd_reset_n),.rst_n(rx_rst_n));
 reg rx_vs_q,rx_hs_q,rx_de_q;
 reg [23:0] rx_rgb_q;
 reg clock_seen,de_seen;
 always @(posedge hd_rx_pclk or negedge rx_rst_n) begin
  if(!rx_rst_n)begin rx_vs_q<=0;rx_hs_q<=0;rx_de_q<=0;rx_rgb_q<=0;clock_seen<=0;de_seen<=0;end
  else begin
   rx_vs_q<=hd_rx_vs;rx_hs_q<=hd_rx_hs;rx_de_q<=hd_rx_de;rx_rgb_q<=hd_rx_data;
   clock_seen<=1;if(hd_rx_de)de_seen<=1;
  end
 end
 wire recovered_vs;
 hdmi_vs_recover recover(.clk(hd_rx_pclk),.reset_n(rx_rst_n),.de(rx_de_q),
  .hs(rx_hs_q),.vs_in(rx_vs_q),.vs_out(recovered_vs));
 always @(posedge hd_rx_pclk or negedge rx_rst_n) begin
  if(!rx_rst_n)begin hd_tx_vs<=0;hd_tx_hs<=0;hd_tx_de<=0;hd_tx_data<=0;end
  else begin hd_tx_vs<=recovered_vs;hd_tx_hs<=rx_hs_q;hd_tx_de<=rx_de_q;hd_tx_data<=rx_rgb_q;end
 end
 assign hd_tx_pclk=hd_rx_pclk;
 reg [25:0] heartbeat;
 always @(posedge sys_clk_27m or negedge rst_n)begin
  if(!rst_n)heartbeat<=0;else heartbeat<=heartbeat+1'b1;
 end
 assign led={cfg_lock,startup_retry_seen,config_error,de_seen,clock_seen,tx_done,rx_done,heartbeat[24]};
endmodule
`default_nettype wire
