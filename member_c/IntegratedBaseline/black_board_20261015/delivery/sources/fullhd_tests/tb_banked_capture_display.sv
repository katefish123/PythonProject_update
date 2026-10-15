`timescale 1ns/1ps
module tb_banked_capture_display #(parameter READ_AHEAD=1,EXPECT_UNDERRUN=0,LOAD_TRAFFIC=1);
 localparam OW=640,OH=904,HS=44,HB=148,HA=1920,HF=88,VS=5,VB=36,VA=1080,VF=4;
 localparam X0=HS+HB+(HA-OW)/2,Y0=VS+VB+(VA-OH)/2;
 reg ui_clk=0,pix_clk=0,reset_n=0,pub_toggle=0,pub_bank=0;
 always #4 ui_clk=~ui_clk;
 always #3.3670035 pix_clk=~pix_clk;
 wire ack,cmd_valid,prefetch_busy;wire [27:0] cmd_addr;
 wire cmd_ready;
 wire rsp_valid;wire [255:0] rsp_data;
 wire hs,vs,de,image_valid,underrun;wire [23:0] rgb;
 integer ui_cycle=0,delay_count=0,requests=0,physical_reads=0,mem_y,mem_x,mem_bank;
 integer correct_pixels=0,black_pixels=0;
 reg pending=0;reg [255:0] held_word;
 reg [11:0] hd1=0,hd2=0,vd1=0,vd2=0;
 integer frame_bank=0,checked_pixels=0,completed_frames=0;
 reg previous_vs=0,test_passed=0;
 function [23:0] encode_pixel(input integer bank,input integer y,input integer x);
  encode_pixel=((bank+1)<<22)|(y<<10)|x;
 endfunction
 reg camera_vs=0,camera_de=0,capture_request=0;reg [23:0] camera_rgb=0;
 wire rx_done,rx_ok,full,empty,fwe,fre,frvalid,cap_done,cap_good,capture_write;
 ddr_result_display #(.OUT_W(OW),.OUT_H(OH),.SCALE(1),.BASE0(28'h0200000),.BASE1(28'h0400000)) dut(.scan_x(),.scan_y(),.scan_de(),.scan_start(),.scan_reset_n(),.preview_valid(1'b0),.preview_rgb(24'd0),.overlay_on(1'b0),.overlay_rgb(24'd0),.capture_guard(capture_request!=cap_done),
  .ui_clk(ui_clk),.ui_rst_n(reset_n),.pix_clk(pix_clk),.pix_rst_n(reset_n),.publish_toggle(pub_toggle),.publish_bank(pub_bank),
  .ack_toggle(ack),.force_pattern(1'b0),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_addr(cmd_addr),
  .rsp_valid(rsp_valid),.rsp_rdata(rsp_data),.hsync(hs),.vsync(vs),.de(de),.rgb(rgb),.image_valid(image_valid),.underrun(underrun),.prefetch_busy(prefetch_busy));


 integer row_ui_cycles=0,row_max_ui_cycles=0;
 always @(posedge ui_clk)begin
  if(!reset_n)begin row_ui_cycles=0;row_max_ui_cycles=0;end
  else if(dut.ui_state==dut.UI_IDLE)row_ui_cycles=0;
  else begin
   row_ui_cycles=row_ui_cycles+1;
   if(dut.ui_state==dut.UI_WRITE && dut.burst_index==OW/8-1 &&
      (!dut.scan_active_ui[2] || dut.ui_line_row[0]!=dut.scan_row_ui2[0]) &&
      row_ui_cycles>row_max_ui_cycles)row_max_ui_cycles=row_ui_cycles;
  end
 end
 function [255:0] source_word(input [27:0] address);
  for(integer q=0;q<8;q=q+1)source_word[q*32+:32]={8'd0,24'h200000|(address+q)};
 endfunction

 integer processor_served=0,processor_wait=0,max_processor_wait=0;wire load_proc_valid=reset_n;wire [27:0] load_proc_addr=28'h0100000;
 wire load_cap_valid;wire [27:0] load_cap_addr;wire [255:0] capture_data;wire [31:0] capture_mask;
 wire load_proc_ready,load_cap_ready,load_proc_rsp,load_cap_rsp,load_proc_write,load_cap_write;
 wire [255:0] load_proc_data,load_cap_data;
 wire [284:0] fwd,frd;
 integer capture_served=0,capture_max_backlog=0;
 ddr_snapshot_capture #(.IN_W(1920),.IN_H(1080),.SRC_W(1920),.SRC_H(1080)) capture(.failure_reason(),.sample_valid(),.sample_first(),.sample_last(),.sample_token(),
  .rx_clk(pix_clk),.rx_rst_n(reset_n),.rx_vs(camera_vs),.rx_de(camera_de),.rx_rgb(camera_rgb),
  .request_toggle(capture_request),.rx_complete_toggle(rx_done),.capture_ok(rx_ok),
  .fifo_wr_en(fwe),.fifo_wr_data(fwd),.fifo_full(full));
 async_packet_fifo #(.DATA_WIDTH(285),.ADDR_BITS(10)) fifo(.wr_clk(pix_clk),.rd_clk(ui_clk),.rst_n(reset_n),
  .wr_en(fwe),.wr_data(fwd),.full(full),.rd_en(fre),.rd_data(frd),.rd_valid(frvalid),.empty(empty));
 ddr_capture_writer_banked #(.SRC_W(1920),.SRC_H(1080)) writer(.failure_reason(),.cmd_burst_data(),.rx_failure_reason(4'd0),.ui_clk(ui_clk),.ui_rst_n(reset_n),
  .base_word_addr(28'h0800000),.request_toggle(capture_request),.rx_complete_toggle(rx_done),.rx_capture_ok(rx_ok),
  .fifo_empty(empty),.fifo_rd_data(frd),.fifo_rd_valid(frvalid),.fifo_rd_en(fre),
  .cmd_valid(load_cap_valid),.cmd_ready(load_cap_ready),.cmd_write(capture_write),.cmd_addr(load_cap_addr),
  .cmd_wdata(capture_data),.cmd_wstrb(capture_mask),.rsp_valid(load_cap_rsp),.rsp_write(load_cap_write),
  .complete_toggle(cap_done),.capture_ok(cap_good));
 always @(posedge pix_clk)if(reset_n&&capture.active)begin
  if(full)$fatal(1,"FULLHD_FIFO_OVERFLOW full-resolution capture cannot sustain rate");
 end
 always @(posedge ui_clk)if(reset_n&&load_cap_valid&&load_cap_ready)begin
  if(!capture_write||load_cap_addr!==28'h0800000+capture_served*8||capture_mask!==32'hffffffff||
     capture_data!==source_word(load_cap_addr-28'h0800000))$fatal(1,"FULLHD_CAPTURE_PIXEL_OR_ADDRESS beat=%0d",capture_served);
  capture_served=capture_served+1;
 end
 initial begin
  wait(ack==1);repeat(30)@(negedge pix_clk);capture_request=1;
  repeat(30)@(negedge pix_clk);camera_vs=1;repeat(5)@(negedge pix_clk);camera_vs=0;
  for(integer y=0;y<1080;y=y+1)begin
   for(integer x=0;x<1920;x=x+1)begin
    camera_de=1;camera_rgb=24'h200000|(y*1920+x);@(negedge pix_clk);
   end
   camera_de=0;repeat(280)@(negedge pix_clk);
  end
  camera_vs=1;repeat(5)@(negedge pix_clk);camera_vs=0;
 end
 wire app_valid,app_ready,app_write,app_response,app_response_write;
 wire [27:0] app_addr;wire [255:0] app_wdata,app_rdata;wire [31:0] app_mask;
 ddr_arbiter3 owner(.clk(ui_clk),.rst_n(reset_n),.enabled(1'b1),
  .c0_valid(load_proc_valid&&empty&&!prefetch_busy),.c0_ready(load_proc_ready),.c0_write(1'b0),.c0_addr(load_proc_addr),.c0_wdata(256'd0),.c0_wstrb(32'd0),.c0_rsp_valid(load_proc_rsp),.c0_rsp_write(load_proc_write),.c0_rdata(load_proc_data),
  .c1_valid(load_cap_valid),.c1_ready(load_cap_ready),.c1_write(1'b1),.c1_addr(load_cap_addr),.c1_wdata(capture_data),.c1_wstrb(capture_mask),.c1_rsp_valid(load_cap_rsp),.c1_rsp_write(load_cap_write),.c1_rdata(load_cap_data),
  .c2_valid(cmd_valid),.c2_ready(cmd_ready),.c2_write(1'b0),.c2_addr(cmd_addr),.c2_wdata(256'd0),.c2_wstrb(32'd0),.c2_rsp_valid(rsp_valid),.c2_rsp_write(),.c2_rdata(rsp_data),
  .cmd_valid(app_valid),.cmd_ready(app_ready),.cmd_write(app_write),.cmd_addr(app_addr),.cmd_wdata(app_wdata),.cmd_wstrb(app_mask),
  .rsp_valid(app_response),.rsp_write(app_response_write),.rsp_rdata(app_rdata));
 wire [27:0] axi_awaddr,axi_araddr;wire [3:0] axi_awid,axi_arid,axi_awlen,axi_arlen;
 wire axi_awap,axi_arap,axi_awvalid,axi_arvalid,engine_fault;
 wire [255:0] axi_wdata;wire [31:0] axi_mask;
 reg arready=0,rvalid=0,rlast=0;reg [255:0] rdata=0;
 reg memory_pending=0;reg [27:0] memory_base;integer beat=0,total=0;
 ddr_word_engine #(.READ_AHEAD_ENABLE(READ_AHEAD),.RESULT_WORDS(OW*OH),.RESULT_BASE0(28'h0200000),.RESULT_BASE1(28'h0400000)) engine(.fault_reason(),.capture_burst_data(2048'd0),
  .clk(ui_clk),.rst_n(reset_n),.init_done(reset_n),.cmd_valid(app_valid),.cmd_ready(app_ready),.cmd_write(app_write),.cmd_addr(app_addr),.cmd_wdata(app_wdata),.cmd_wstrb(app_mask),
  .rsp_valid(app_response),.rsp_write(app_response_write),.rsp_rdata(app_rdata),.fault(engine_fault),
  .axi_awaddr(axi_awaddr),.axi_awuser_ap(axi_awap),.axi_awuser_id(axi_awid),.axi_awlen(axi_awlen),.axi_awvalid(axi_awvalid),.axi_awready(ui_cycle%17>=2),
  .axi_wdata(axi_wdata),.axi_wstrb(axi_mask),.axi_wready(ui_cycle%17>=2),.axi_wusero_id(4'd0),.axi_wusero_last(1'b1),
  .axi_araddr(axi_araddr),.axi_aruser_ap(axi_arap),.axi_aruser_id(axi_arid),.axi_arlen(axi_arlen),.axi_arvalid(axi_arvalid),.axi_arready(arready),
  .axi_rdata(rdata),.axi_rid(4'd0),.axi_rlast(rlast),.axi_rvalid(rvalid));
 always @(posedge ui_clk)if(reset_n)begin
  if(cmd_valid&&cmd_ready)requests=requests+1;
  if(load_proc_valid&&load_proc_ready)begin processor_served=processor_served+1;processor_wait=0;end
  else if(load_proc_valid)begin processor_wait=processor_wait+1;if(processor_wait>max_processor_wait)max_processor_wait=processor_wait;end
  if(axi_arvalid&&arready)physical_reads=physical_reads+1;
  if(engine_fault)$fatal(1,"display protocol/ownership fault");
 end
 // Hypothetical physical memory: 28-cycle first-beat response; occasionally
 // another 100 clocks model a refresh wait. Stream all burst beats without RREADY.
 always @(negedge ui_clk)begin
  ui_cycle=ui_cycle+1;arready=reset_n&&!memory_pending&&(ui_cycle%7!=0);rvalid=0;rlast=0;
  if(!reset_n)begin memory_pending=0;beat=0;end
  else if(!memory_pending&&axi_arvalid&&arready)begin
   memory_base=axi_araddr;total=axi_arlen+1;beat=0;
   delay_count=28+((physical_reads%128==127)?100:0);memory_pending=1;
  end else if(memory_pending)begin
   if(delay_count>0)delay_count=delay_count-1;
   else begin
    mem_bank=(memory_base>=28'h0400000);
    mem_y=(memory_base+beat*8-(mem_bank?28'h0400000:28'h0200000))/OW;
    mem_x=(memory_base+beat*8-(mem_bank?28'h0400000:28'h0200000))%OW;
    if(memory_base<28'h0200000)rdata=source_word(memory_base+beat*8);
    else begin
     if(mem_y>=OH||mem_x>=OW)$fatal(1,"read-ahead exceeded result bounds");
     for(integer lane=0;lane<8;lane=lane+1)rdata[lane*32+:32]={8'd0,encode_pixel(mem_bank,mem_y,mem_x+lane)};
    end
    rvalid=1;rlast=(beat==total-1);beat=beat+1;
    if(beat==total)memory_pending=0;
   end
  end
 end
 always @(posedge pix_clk)begin hd1<=dut.hc;hd2<=hd1;vd1<=dut.vc;vd2<=vd1;end
 always @(negedge pix_clk)if(reset_n)begin
  if(vs&&!previous_vs)begin frame_bank=dut.display_bank;checked_pixels=0;end
  if(image_valid&&de&&hd2>=X0&&hd2<X0+OW&&vd2>=Y0&&vd2<Y0+OH)begin
   if(rgb===encode_pixel(frame_bank,vd2-Y0,hd2-X0))correct_pixels=correct_pixels+1;
   else if(EXPECT_UNDERRUN&&rgb===24'd0)black_pixels=black_pixels+1;
   else $fatal(1,"display/arbiter/engine lost or mixed a row bank=%0d x=%0d y=%0d",frame_bank,hd2-X0,vd2-Y0);
   checked_pixels=checked_pixels+1;
   if(hd2==X0+OW-1&&vd2==Y0+OH-1)begin
    if(checked_pixels!=OW*OH)$fatal(1,"incomplete native frame %0d",checked_pixels);
    if(!EXPECT_UNDERRUN&&underrun)$fatal(1,"cached full display underflow");
    if(EXPECT_UNDERRUN&&(!underrun||black_pixels==0))$fatal(1,"control case failed to reproduce late rows");
    completed_frames=completed_frames+1;
   end
  end
  previous_vs=vs;
 end
 initial begin
  repeat(8)@(negedge pix_clk);reset_n=1;
  repeat(8)@(negedge pix_clk);pub_toggle=1;
  wait(ack==pub_toggle);
  if(EXPECT_UNDERRUN)wait(completed_frames>=1);
  else begin
   // Pending publication during active scan cannot mix physical memory banks.
   wait(dut.vc==Y0+300&&dut.hc==X0+300);@(negedge pix_clk);pub_bank=1;pub_toggle=0;
   wait(completed_frames>=2);
   if(frame_bank!=1)$fatal(1,"cached scanout did not swap atomically");
  end
  if(!EXPECT_UNDERRUN&&!LOAD_TRAFFIC&&physical_reads!=2*OW*OH/64)$fatal(1,"unexpected prefetch transaction count %0d",physical_reads);
  wait(cap_done==capture_request); if(!cap_good||!rx_ok||capture_served!=259200)$fatal(1,"FULLHD_CAPTURE_INCOMPLETE beats=%0d",capture_served);
  if(processor_served<100)$fatal(1,"processor reads did not progress during banked full-HD capture");
  $display("PROCESSOR_MAX_UI_WAIT=%0d UI_PERIOD_NS=8",max_processor_wait);
  if(max_processor_wait>=4629000)$fatal(1,"parallel memory wait exceeds processor watchdog");
  $display("BANKED_FULLHD_CAPTURE_DISPLAY_PASS source_pixels=2073600 capture_beats=%0d display_frames=%0d model_latency_only=1",capture_served,completed_frames);
  test_passed=1;$display("HIRES_ENGINE_DISPLAY_PASS read_ahead=%0d expected_underflow=%0d frames=%0d correct_pixels=%0d black_pixels=%0d physical_reads=%0d logical_reads=%0d max_row_cycles=%0d model_latency_only=1",READ_AHEAD,EXPECT_UNDERRUN,completed_frames,correct_pixels,black_pixels,physical_reads,requests,row_max_ui_cycles);$finish;
 end
 initial begin #150000000;$fatal(1,"native high resolution display timeout");end
endmodule
