`timescale 1ns/1ps
// Full-resolution RGB888 stream diagnostic; no frame buffer or DDR.
module hdmi_camera_loop_top(input sys_clk_27m,rst_n,hd_rx_pclk,hd_rx_vs,hd_rx_hs,hd_rx_de,input [23:0] hd_rx_data,output hd_tx_pclk,hd_tx_vs,hd_tx_hs,hd_tx_de,output [23:0] hd_tx_data,output hd_reset_n,hd_scl,hdmi_init_done,rx_init_done,inout hd_sda);
wire cfg_clk,locked;
reg [15:0] reset_count;
config_pll_27m_10m pll(.clkin1(sys_clk_27m),.clkout0(cfg_clk),.lock(locked));
always @(posedge cfg_clk or negedge rst_n) begin
 if(!rst_n) reset_count<=0;
 else if(!locked) reset_count<=0;
 else if(reset_count<10000) reset_count<=reset_count+1'b1;
end
assign hd_reset_n=rst_n && locked && reset_count==10000;
ms72xx_shared_config #(.TX_FIRST(0)) config_bus(.cfg_clk(cfg_clk),.reset_n(hd_reset_n),.rx_done(rx_init_done),.tx_done(hdmi_init_done),.scl(hd_scl),.sda(hd_sda));
assign hd_tx_pclk=hd_rx_pclk;
reg [1:0] rx_reset_pipe;
always @(posedge hd_rx_pclk or negedge hd_reset_n)begin
 if(!hd_reset_n)rx_reset_pipe<=0;else rx_reset_pipe<={rx_reset_pipe[0],1'b1};
end
reg rx_de_q,rx_hs_q,rx_vs_q;
reg [23:0] rx_pixel_q;
always @(posedge hd_rx_pclk or negedge rx_reset_pipe[1])begin
 if(!rx_reset_pipe[1])begin rx_de_q<=0;rx_hs_q<=0;rx_vs_q<=0;rx_pixel_q<=0;end
 else begin rx_de_q<=hd_rx_de;rx_hs_q<=hd_rx_hs;rx_vs_q<=hd_rx_vs;rx_pixel_q<=hd_rx_data;end
end
wire recovered_vs;
hdmi_vs_recover recover(.clk(hd_rx_pclk),.reset_n(rx_reset_pipe[1]),.de(rx_de_q),.hs(rx_hs_q),.vs_in(rx_vs_q),.vs_out(recovered_vs));
reg tx_de_q,tx_hs_q,tx_vs_q;
reg [23:0] tx_pixel_q;
always @(posedge hd_rx_pclk or negedge rx_reset_pipe[1])begin
 if(!rx_reset_pipe[1])begin tx_de_q<=0;tx_hs_q<=0;tx_vs_q<=0;tx_pixel_q<=0;end
 else begin tx_de_q<=rx_de_q;tx_hs_q<=rx_hs_q;tx_vs_q<=recovered_vs;tx_pixel_q<=rx_pixel_q;end
end
assign hd_tx_vs=tx_vs_q;
assign hd_tx_hs=tx_hs_q;
assign hd_tx_de=tx_de_q;
assign hd_tx_data=tx_pixel_q;
endmodule
