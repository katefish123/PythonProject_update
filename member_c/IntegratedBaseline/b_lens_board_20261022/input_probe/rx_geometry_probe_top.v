`timescale 1ns/1ps
module rx_geometry_probe_top(
 input wire sys_clk_27m,rst_n,hd_rx_pclk,hd_rx_vs,hd_rx_hs,hd_rx_de,
 input wire[23:0]hd_rx_data,
 output wire hd_tx_pclk,hd_tx_vs,hd_tx_hs,hd_tx_de,
 output reg[23:0]hd_tx_data,output wire hd_reset_n,hd_scl,inout wire hd_sda
);
 wire pix,proc_unused,cfg,pl,cl;wire ready=rst_n&&pl&&cl;
 video_pll_27m_148m5 vp(.clkin1(sys_clk_27m),.clkout0(pix),.clkout57(proc_unused),.lock(pl));
 config_pll_27m_10m cp(.clkin1(sys_clk_27m),.clkout0(cfg),.lock(cl));
 reg[15:0]reset_count;
 always @(posedge cfg or negedge ready)if(!ready)reset_count<=0;else if(reset_count<10000)reset_count<=reset_count+1'b1;
 assign hd_reset_n=ready&&reset_count==10000;
 wire rx_done,tx_done,ack_error,config_error,retry_seen;wire[49:0]rx_probe;
 hdmi_config #(.TX_FIRST(1'b1)) config_bus(.cfg_clk(cfg),.reset_n(hd_reset_n),
 .rx_done(rx_done),.tx_done(tx_done),.scl(hd_scl),.sda(hd_sda),.ack_error(ack_error),.config_error(config_error),.startup_retry_seen(retry_seen),.rx_probe(rx_probe));
 wire rx_reset;reset_sync rr(.clk(hd_rx_pclk),.arst_n(hd_reset_n),.rst_n(rx_reset));
 wire[159:0]pos_q,neg_q,pos_cfg,neg_cfg;wire inv_rx=~hd_rx_pclk;
 input_geometry_monitor pm(hd_rx_pclk,rx_reset,hd_rx_vs,hd_rx_de,pos_q);
 input_geometry_monitor nm(inv_rx,rx_reset,hd_rx_vs,hd_rx_de,neg_q);
 snapshot_cdc #(.WIDTH(160)) pc(.s_clk(hd_rx_pclk),.d_clk(cfg),.rst_n(hd_reset_n),.s_data(pos_q),.d_data(pos_cfg),.d_valid());
 snapshot_cdc #(.WIDTH(160)) nc(.s_clk(inv_rx),.d_clk(cfg),.rst_n(hd_reset_n),.s_data(neg_q),.d_data(neg_cfg),.d_valid());
 reg[5:0]div_rx;
 always @(posedge hd_rx_pclk or negedge hd_reset_n)if(!hd_reset_n)div_rx<=0;else div_rx<=div_rx+1'b1;
 reg[2:0]ds;reg[18:0]win;reg[31:0]edges,frequency;
 always @(posedge sys_clk_27m or negedge ready)begin
  if(!ready)begin ds<=0;win<=0;edges<=0;frequency<=0;end
  else begin ds<={ds[1:0],div_rx[5]};
   if(win==269999)begin frequency<=edges+(ds[1]&&!ds[2]);edges<=0;win<=0;end
   else begin win<=win+1'b1;if(ds[1]&&!ds[2])edges<=edges+1'b1;end
  end
 end
 wire[31:0]freq_cfg;snapshot_cdc #(.WIDTH(32)) fc(.s_clk(sys_clk_27m),.d_clk(cfg),.rst_n(ready),.s_data(frequency),.d_data(freq_cfg),.d_valid());
 wire[11:0]hc,vc;wire hs,vs,de;
 video_timing_vtc timing(.clk(pix),.rst_n(ready),.h_cnt(hc),.v_cnt(vc),.hsync(hs),.vsync(vs),.de(de));
 wire[11:0]x=hc-192,y=vc-41;
 wire[1919:0]trace={1360'd0,16'd0,freq_cfg,27'd0,retry_seen,config_error,ack_error,rx_done,tx_done,30'd0,rx_probe,neg_cfg,pos_cfg,80'd0};
 wire on;wire[23:0]overlay;
 debug_hex_overlay view(.proc_clk(cfg),.pix_clk(pix),.rst_n(ready),.scan_de(de),.x(x),.y(y),.data(trace),
 .pix_metadata(80'h525850524f4245000001),.on(on),.rgb(overlay));
 always @(posedge pix)hd_tx_data<=on?overlay:24'h202040;
 assign hd_tx_pclk=pix;assign hd_tx_hs=hs;assign hd_tx_vs=vs;assign hd_tx_de=de;
endmodule
