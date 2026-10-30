 // Fill source DDR exclusively through the actual full-resolution capture path.
 // Processor/golden comparison starts only after the final capture write retires.
 reg cap_rx_clk=0,cap_ui_clk=0,cap_clock_enable=1,cap_reset=0;
 reg cap_vs=0,cap_de=0,cap_request=0;reg [23:0] cap_rgb=0;
 always begin wait(cap_clock_enable);#3.3670035;cap_rx_clk=~cap_rx_clk;end
 always begin wait(cap_clock_enable);#4;cap_ui_clk=~cap_ui_clk;end
 wire cap_rx_done,cap_rx_good,cap_full,cap_empty,cap_we,cap_re,cap_rvalid;
 wire [284:0] cap_wpacket,cap_rpacket;
 wire cap_cv,cap_cw,cap_done,cap_good;wire [27:0] cap_ca;wire [255:0] cap_cd;wire [31:0] cap_mask;
 reg cap_rsp=0;integer captured_beats=0;
 ddr_snapshot_capture #(.IN_W(SRC_W),.IN_H(SRC_H),.SRC_W(SRC_W),.SRC_H(SRC_H)) source_capture(
  .rx_clk(cap_rx_clk),.rx_rst_n(cap_reset),.rx_vs(cap_vs),.rx_de(cap_de),.rx_rgb(cap_rgb),
  .request_toggle(cap_request),.rx_complete_toggle(cap_rx_done),.capture_ok(cap_rx_good),
  .fifo_wr_en(cap_we),.fifo_wr_data(cap_wpacket),.fifo_full(cap_full));
 async_packet_fifo #(.DATA_WIDTH(285),.ADDR_BITS(10)) source_fifo(
  .wr_clk(cap_rx_clk),.rd_clk(cap_ui_clk),.rst_n(cap_reset),.wr_en(cap_we),.wr_data(cap_wpacket),.full(cap_full),
  .rd_en(cap_re),.rd_data(cap_rpacket),.rd_valid(cap_rvalid),.empty(cap_empty));
 ddr_capture_writer #(.SRC_W(SRC_W),.SRC_H(SRC_H)) source_writer(
  .ui_clk(cap_ui_clk),.ui_rst_n(cap_reset),.request_toggle(cap_request),.rx_complete_toggle(cap_rx_done),.rx_capture_ok(cap_rx_good),
  .fifo_empty(cap_empty),.fifo_rd_data(cap_rpacket),.fifo_rd_valid(cap_rvalid),.fifo_rd_en(cap_re),
  .cmd_valid(cap_cv),.cmd_ready(1'b1),.cmd_write(cap_cw),.cmd_addr(cap_ca),.cmd_wdata(cap_cd),.cmd_wstrb(cap_mask),
  .rsp_valid(cap_rsp),.rsp_write(1'b1),.complete_toggle(cap_done),.capture_ok(cap_good));
 always @(posedge cap_ui_clk)begin
  cap_rsp<=0;
  if(cap_reset&&cap_cv)begin
   if(!cap_cw||cap_ca!==captured_beats*8||cap_mask!==32'hffffffff)$fatal(1,"full-HD capture address/strobes");
   for(integer n=0;n<8;n=n+1)begin
    if(cap_cd[n*32+:32]!=={8'd0,source[cap_ca+n]})$fatal(1,"full-HD capture changed source pixel");
    ram[cap_ca+n]<=cap_cd[n*32+:32];
   end
   captured_beats=captured_beats+1;cap_rsp<=1;
  end
 end
 task run_capture;
  begin
   repeat(12)@(negedge cap_rx_clk);cap_reset=1;cap_request=1;
   repeat(20)@(negedge cap_rx_clk);cap_vs=1;repeat(5)@(negedge cap_rx_clk);cap_vs=0;
   for(integer y=0;y<SRC_H;y=y+1)begin
    for(integer x=0;x<SRC_W;x=x+1)begin cap_de=1;cap_rgb=source[y*SRC_W+x];@(negedge cap_rx_clk);end
    cap_de=0;repeat(280)@(negedge cap_rx_clk);
   end
   cap_vs=1;repeat(5)@(negedge cap_rx_clk);cap_vs=0;
   wait(cap_done==cap_request);#1;
   if(!cap_good||!cap_rx_good||captured_beats!=SRC_W*SRC_H/8)$fatal(1,"full-HD source was not completely committed");
   cap_clock_enable=0;
   $display("FULLHD_CAPTURE_TO_PROCESSOR_PASS pixels=%0d beats=%0d",SRC_W*SRC_H,captured_beats);
  end
 endtask
