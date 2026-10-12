from pathlib import Path
root=Path(r'C:\D\FPGA\video_correct_integrated_20261008')
out=root/'diagnostics/internal_fixture'
src=root/'reference/baselines/ddr_before_hdmi_startup_fix/rtl/top/video_correct_ddr_top.v'
s=src.read_text()
s=s.replace('module video_correct_ddr_top(', 'module video_correct_ddr_internal_fixture_top(')
s=s.replace('wire cfg_rst,mem_reset,proc_rst,rx_rst,pix_rst,ui_rst;', 'wire cfg_rst,mem_reset,proc_rst,pix_rst,ui_rst;')
s=s.replace('reset_sync receive_reset(.clk(hd_rx_pclk),.arst_n(app_reset_async),.rst_n(rx_rst));\n','')
s=s.replace('hdmi_config config_bus(', "hdmi_config #(.TX_FIRST(1'b1)) config_bus(")
s=s.replace('(* ASYNC_REG="TRUE" *) reg [2:0] ready_sync,nearest_sync,pattern_sync;', '(* ASYNC_REG="TRUE" *) reg [2:0] ready_sync,nearest_sync,pattern_sync;')
s=s.replace('rx_done&&tx_done&&!ack_error', 'tx_done')
start=s.index(' reg rx_vs_q,rx_hs_q,rx_de_q;')
end=s.index(' wire cmd_v,cmd_r,cmd_w,rsp_v,rsp_w,engine_fault;',start)
s=s[:start]+''' wire fixture_vs,fixture_hs,fixture_de; wire [23:0] fixture_rgb;
 wire [11:0] fixture_x,fixture_y;
 internal_fixture_video fixture_source(.clk(sys_clk_27m),.reset_n(proc_rst),
  .vsync(fixture_vs),.hsync(fixture_hs),.de(fixture_de),.rgb(fixture_rgb),.raster_x(fixture_x),.raster_y(fixture_y));
 // Diagnostic fixture mode: TX completion alone releases capture; RX camera is intentionally unused.
 // DDR BIST/readiness and memory fault gates remain unchanged in video_correct_ddr_core.
'''+s[end:]
s=s.replace('.proc_clk(sys_clk_27m),.proc_rst_n(proc_rst),.rx_clk(hd_rx_pclk),.rx_rst_n(rx_rst),', '.proc_clk(sys_clk_27m),.proc_rst_n(proc_rst),.rx_clk(sys_clk_27m),.rx_rst_n(proc_rst),')
s=s.replace('.rx_vs(recovered_vs),.rx_de(rx_de_q),.rx_rgb(rx_rgb_q),', '.rx_vs(fixture_vs),.rx_de(fixture_de),.rx_rgb(fixture_rgb),')
s=s.replace('assign led={rx_done&&tx_done,ack_error||engine_fault||phy_fail||align_error||self_fail,', 'assign led={tx_done,ack_error||engine_fault||phy_fail||align_error||self_fail,')
s=s.replace('// PG2L100H / MES2L676-100HP board integration with external x32 DDR3.', '// Isolated internal-fixture diagnostic top; memory/IP and core algorithm match DDR baseline.')
(out/'video_correct_ddr_internal_fixture_top.v').write_text(s)
