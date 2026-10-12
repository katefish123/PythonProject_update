`timescale 1ns/1ps
`default_nettype none
// PG2L100H / MES2L676-100HP board integration with external x32 DDR3.
module video_correct_ddr_status_top(
 input wire sys_clk_27m,rst_n,key1_pattern_n,key2_nearest_n,
 input wire ddr_ref_clk_p,ddr_ref_clk_n,
 input wire hd_rx_pclk,hd_rx_vs,hd_rx_hs,hd_rx_de,
 input wire [23:0] hd_rx_data,
 output wire hd_tx_pclk,output reg hd_tx_vs,hd_tx_hs,hd_tx_de,
 output reg [23:0] hd_tx_data,
 output wire hd_reset_n,hd_scl,inout wire hd_sda,
 output wire [7:0] led,
 output wire mem_cs_n,mem_rst_n,mem_ck,mem_ck_n,mem_cke,mem_ras_n,mem_cas_n,mem_we_n,mem_odt,
 output wire [14:0] mem_a,output wire [2:0] mem_ba,
 inout wire [3:0] mem_dqs,mem_dqs_n,inout wire [31:0] mem_dq,output wire [3:0] mem_dm
);
 wire pix_clk,cfg_clk,pix_lock,cfg_lock,ref_clk,ui_clk;
 video_pll_27m_148m5 vp(.clkin1(sys_clk_27m),.clkout0(pix_clk),.lock(pix_lock));
 config_pll_27m_10m cp(.clkin1(sys_clk_27m),.clkout0(cfg_clk),.lock(cfg_lock));
 GTP_INBUFDS ref_input(.I(ddr_ref_clk_p),.IB(ddr_ref_clk_n),.O(ref_clk));
 wire clocks_ready=rst_n&&pix_lock&&cfg_lock;
 wire cfg_rst,mem_reset,proc_rst,rx_rst,pix_rst,ui_rst;
 reset_sync cfg_reset(.clk(cfg_clk),.arst_n(clocks_ready),.rst_n(cfg_rst));
 reset_sync ddr_reset(.clk(ref_clk),.arst_n(clocks_ready),.rst_n(mem_reset));
 reg [15:0] hd_count;
 always @(posedge cfg_clk or negedge cfg_rst)begin
  if(!cfg_rst)hd_count<=0;else if(hd_count<10000)hd_count<=hd_count+1'b1;
 end
 assign hd_reset_n=cfg_rst&&hd_count==10000;
 wire ddr_lock,ddr_ready,phy_fail,align_error;
 wire app_reset_async=hd_reset_n&&mem_reset&&ddr_lock;
 reset_sync process_reset(.clk(sys_clk_27m),.arst_n(app_reset_async),.rst_n(proc_rst));
 reset_sync receive_reset(.clk(hd_rx_pclk),.arst_n(app_reset_async),.rst_n(rx_rst));
 reset_sync display_reset(.clk(pix_clk),.arst_n(app_reset_async),.rst_n(pix_rst));
 reset_sync ui_reset(.clk(ui_clk),.arst_n(app_reset_async),.rst_n(ui_rst));
 wire rx_done,tx_done,ack_error;
 hdmi_config #(.TX_FIRST(1'b1)) config_bus(.cfg_clk(cfg_clk),.reset_n(hd_reset_n),.rx_done(rx_done),.tx_done(tx_done),
  .scl(hd_scl),.sda(hd_sda),.ack_error(ack_error));
 (* ASYNC_REG="TRUE" *) reg [2:0] ready_sync,nearest_sync,pattern_sync;
 always @(posedge sys_clk_27m or negedge proc_rst)begin
  if(!proc_rst)begin ready_sync<=0;nearest_sync<=0;end
  else begin ready_sync<={ready_sync[1:0],rx_done&&tx_done&&!ack_error};nearest_sync<={nearest_sync[1:0],!key2_nearest_n};end
 end
 always @(posedge pix_clk or negedge pix_rst)begin
  if(!pix_rst)pattern_sync<=0;else pattern_sync<={pattern_sync[1:0],!key1_pattern_n};
 end
 reg rx_vs_q,rx_hs_q,rx_de_q;reg [23:0] rx_rgb_q;
 always @(posedge hd_rx_pclk or negedge rx_rst)begin
  if(!rx_rst)begin rx_vs_q<=0;rx_hs_q<=0;rx_de_q<=0;rx_rgb_q<=0;end
  else begin rx_vs_q<=hd_rx_vs;rx_hs_q<=hd_rx_hs;rx_de_q<=hd_rx_de;rx_rgb_q<=hd_rx_data;end
 end
 wire recovered_vs;
 hdmi_vs_recover vs_recover(.clk(hd_rx_pclk),.reset_n(rx_rst),.de(rx_de_q),.hs(rx_hs_q),.vs_in(rx_vs_q),.vs_out(recovered_vs));
 wire cmd_v,cmd_r,cmd_w,rsp_v,rsp_w,engine_fault;
 wire [27:0] cmd_a;wire [255:0] cmd_data,rsp_data;wire [31:0] cmd_mask;
 wire hs,vs,den,image_valid,working,frame_error,input_wait,underrun,self_pass,self_fail;
 wire [23:0] rgb;
 video_correct_ddr_core core(.proc_clk(sys_clk_27m),.proc_rst_n(proc_rst),.rx_clk(hd_rx_pclk),.rx_rst_n(rx_rst),
  .pix_clk(pix_clk),.pix_rst_n(pix_rst),.ui_clk(ui_clk),.ui_rst_n(ui_rst),
  .hdmi_ready(ready_sync[2]),.ddr_ready(ddr_ready),.memory_fault(engine_fault||phy_fail||align_error),
  .rx_vs(recovered_vs),.rx_de(rx_de_q),.rx_rgb(rx_rgb_q),.nearest(nearest_sync[2]),.force_pattern(pattern_sync[2]),
  .hsync(hs),.vsync(vs),.de(den),.rgb(rgb),.image_valid(image_valid),.working(working),.frame_error(frame_error),.input_wait(input_wait),
  .display_underrun(underrun),.selftest_passed(self_pass),.selftest_failed(self_fail),.good_frames(),.rejected_frames(),
  .cmd_valid(cmd_v),.cmd_ready(cmd_r),.cmd_write(cmd_w),.cmd_addr(cmd_a),.cmd_wdata(cmd_data),.cmd_wstrb(cmd_mask),
  .rsp_valid(rsp_v),.rsp_write(rsp_w),.rsp_rdata(rsp_data));
 wire [27:0] awaddr,araddr;wire awvalid,arvalid,awready,arready,wready,rvalid,rlast,wlast;
 wire [3:0] awid,arid,awlen,arlen,rid,wid;wire awap,arap;
 wire [255:0] wdata,rdata;wire [31:0] wstrb;
 ddr_word_engine engine(.clk(ui_clk),.rst_n(ui_rst),.init_done(ddr_ready),
  .cmd_valid(cmd_v),.cmd_ready(cmd_r),.cmd_write(cmd_w),.cmd_addr(cmd_a),.cmd_wdata(cmd_data),.cmd_wstrb(cmd_mask),
  .rsp_valid(rsp_v),.rsp_write(rsp_w),.rsp_rdata(rsp_data),.fault(engine_fault),
  .axi_awaddr(awaddr),.axi_awuser_ap(awap),.axi_awuser_id(awid),.axi_awlen(awlen),.axi_awvalid(awvalid),.axi_awready(awready),
  .axi_wdata(wdata),.axi_wstrb(wstrb),.axi_wready(wready),.axi_wusero_id(wid),.axi_wusero_last(wlast),
  .axi_araddr(araddr),.axi_aruser_ap(arap),.axi_aruser_id(arid),.axi_arlen(arlen),.axi_arvalid(arvalid),.axi_arready(arready),
  .axi_rdata(rdata),.axi_rid(rid),.axi_rlast(rlast),.axi_rvalid(rvalid));
 ddr3_ip memory_ip(.ref_clk(ref_clk),.resetn(mem_reset),.core_clk(ui_clk),.pll_lock(ddr_lock),
  .phy_pll_lock(),.gpll_lock(),.rst_gpll_lock(),.ddrphy_cpd_lock(),.ddr_init_done(ddr_ready),
  .axi_awaddr(awaddr),.axi_awuser_ap(awap),.axi_awuser_id(awid),.axi_awlen(awlen),.axi_awready(awready),.axi_awvalid(awvalid),
  .axi_wdata(wdata),.axi_wstrb(wstrb),.axi_wready(wready),.axi_wusero_id(wid),.axi_wusero_last(wlast),
  .axi_araddr(araddr),.axi_aruser_ap(arap),.axi_aruser_id(arid),.axi_arlen(arlen),.axi_arready(arready),.axi_arvalid(arvalid),
  .axi_rdata(rdata),.axi_rid(rid),.axi_rlast(rlast),.axi_rvalid(rvalid),
  .apb_clk(1'b0),.apb_rst_n(1'b0),.apb_sel(1'b0),.apb_enable(1'b0),.apb_addr(8'd0),.apb_write(1'b0),.apb_wdata(16'd0),.apb_ready(),.apb_rdata(),
  .mem_cs_n(mem_cs_n),.mem_rst_n(mem_rst_n),.mem_ck(mem_ck),.mem_ck_n(mem_ck_n),.mem_cke(mem_cke),
  .mem_ras_n(mem_ras_n),.mem_cas_n(mem_cas_n),.mem_we_n(mem_we_n),.mem_odt(mem_odt),.mem_a(mem_a),.mem_ba(mem_ba),
  .mem_dqs(mem_dqs),.mem_dqs_n(mem_dqs_n),.mem_dq(mem_dq),.mem_dm(mem_dm),
  .dbg_gate_start(1'b0),.dbg_cpd_start(1'b0),.dbg_ddrphy_rst_n(1'b1),.dbg_gpll_scan_rst(1'b0),
  .samp_position_dyn_adj(1'b0),.init_samp_position_even(32'd0),.init_samp_position_odd(32'd0),
  .wrcal_position_dyn_adj(1'b0),.init_wrcal_position(32'd0),.force_read_clk_ctrl(1'b0),.init_slip_step(16'd0),.init_read_clk_ctrl(12'd0),
  .debug_calib_ctrl(),.dbg_slice_status(),.dbg_slice_state(),.debug_data(),.dbg_dll_upd_state(),.debug_gpll_dps_phase(),
  .dbg_rst_dps_state(),.dbg_tran_err_rst_cnt(),.dbg_ddrphy_init_fail(phy_fail),
  .debug_cpd_offset_adj(1'b0),.debug_cpd_offset_dir(1'b0),.debug_cpd_offset(10'd0),.debug_dps_cnt_dir0(),.debug_dps_cnt_dir1(),
  .ck_dly_en(1'b1),.init_ck_dly_step(8'd0),.ck_dly_set_bin(),.align_error(align_error),.debug_rst_state(),.debug_cpd_state());
 wire tx_rst_n;wire status_hs,status_vs,status_de;wire [23:0] status_rgb;
 reset_sync tx_reset(.clk(pix_clk),.arst_n(rst_n&&pix_lock&&cfg_lock&&hd_reset_n),.rst_n(tx_rst_n));
 wire [14:0] status_async={ddr_lock,ddr_ready,phy_fail,align_error,self_pass,self_fail,
  engine_fault,rx_done,tx_done,ack_error,image_valid,working,frame_error,input_wait,underrun};
 ddr_status_video status_screen(.pix_clk(pix_clk),.reset_n(tx_rst_n),.status_async(status_async),
  .hsync(status_hs),.vsync(status_vs),.de(status_de),.rgb(status_rgb),.pix_clk_out());
 // The probe picture is generated independently while DDR/RX initialize and while the
 // normal algorithm path runs in parallel behind the status cells.
 always @(posedge pix_clk or negedge tx_rst_n)begin
  if(!tx_rst_n)begin hd_tx_hs<=0;hd_tx_vs<=0;hd_tx_de<=0;hd_tx_data<=0;end
  else begin hd_tx_hs<=status_hs;hd_tx_vs<=status_vs;hd_tx_de<=status_de;hd_tx_data<=status_rgb;end
 end
 assign hd_tx_pclk=pix_clk;
 reg [25:0] heartbeat;
 always @(posedge sys_clk_27m or negedge proc_rst)begin
  if(!proc_rst)heartbeat<=0;else heartbeat<=heartbeat+1'b1;
 end
 assign led={rx_done&&tx_done,ack_error||engine_fault||phy_fail||align_error||self_fail,
  underrun,frame_error||input_wait,image_valid,self_pass,ddr_ready,heartbeat[24]};
endmodule
`default_nettype wire
