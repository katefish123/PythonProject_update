`timescale 1ns/1ps
module tb_hires_read_ahead_display #(parameter READ_AHEAD=1,EXPECT_UNDERRUN=0);
 localparam OW=640,OH=904,HS=44,HB=148,HA=1920,HF=88,VS=5,VB=36,VA=1080,VF=4;
 localparam X0=HS+HB+(HA-OW)/2,Y0=VS+VB+(VA-OH)/2;
 reg ui_clk=0,pix_clk=0,reset_n=0,pub_toggle=0,pub_bank=0;
 always #4 ui_clk=~ui_clk;
 always #3.3670035 pix_clk=~pix_clk;
 wire [63:0] diagnostics;
 wire ack,cmd_valid;wire [27:0] cmd_addr;
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
 ddr_result_display #(.OUT_W(OW),.OUT_H(OH),.SCALE(1)) dut(
  .ui_clk(ui_clk),.ui_rst_n(reset_n),.pix_clk(pix_clk),.pix_rst_n(reset_n),.publish_toggle(pub_toggle),.publish_bank(pub_bank),
  .ack_toggle(ack),.force_pattern(1'b0),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_addr(cmd_addr),
  .rsp_valid(rsp_valid),.rsp_rdata(rsp_data),.hsync(hs),.vsync(vs),.de(de),.rgb(rgb),.image_valid(image_valid),.underrun(underrun),.diagnostic_snapshot(diagnostics));

 wire app_valid,app_ready,app_write,app_response,app_response_write;
 wire [27:0] app_addr;wire [255:0] app_wdata,app_rdata;wire [31:0] app_mask;
 ddr_arbiter3 owner(.clk(ui_clk),.rst_n(reset_n),.enabled(1'b1),
  .c0_valid(1'b0),.c0_ready(),.c0_write(1'b0),.c0_addr(28'd0),.c0_wdata(256'd0),.c0_wstrb(32'd0),.c0_rsp_valid(),.c0_rsp_write(),.c0_rdata(),
  .c1_valid(1'b0),.c1_ready(),.c1_write(1'b0),.c1_addr(28'd0),.c1_wdata(256'd0),.c1_wstrb(32'd0),.c1_rsp_valid(),.c1_rsp_write(),.c1_rdata(),
  .c2_valid(cmd_valid),.c2_ready(cmd_ready),.c2_write(1'b0),.c2_addr(cmd_addr),.c2_wdata(256'd0),.c2_wstrb(32'd0),.c2_rsp_valid(rsp_valid),.c2_rsp_write(),.c2_rdata(rsp_data),
  .cmd_valid(app_valid),.cmd_ready(app_ready),.cmd_write(app_write),.cmd_addr(app_addr),.cmd_wdata(app_wdata),.cmd_wstrb(app_mask),
  .rsp_valid(app_response),.rsp_write(app_response_write),.rsp_rdata(app_rdata));
 wire [27:0] axi_awaddr,axi_araddr;wire [3:0] axi_awid,axi_arid,axi_awlen,axi_arlen;
 wire axi_awap,axi_arap,axi_awvalid,axi_arvalid,engine_fault;
 wire [255:0] axi_wdata;wire [31:0] axi_mask;
 reg arready=0,rvalid=0,rlast=0;reg [255:0] rdata=0;
 reg memory_pending=0;reg [27:0] memory_base;integer beat=0,total=0;
 ddr_word_engine #(.READ_AHEAD_ENABLE(READ_AHEAD),.RESULT_WORDS(OW*OH)) engine(
  .clk(ui_clk),.rst_n(reset_n),.init_done(reset_n),.cmd_valid(app_valid),.cmd_ready(app_ready),.cmd_write(app_write),.cmd_addr(app_addr),.cmd_wdata(app_wdata),.cmd_wstrb(app_mask),
  .rsp_valid(app_response),.rsp_write(app_response_write),.rsp_rdata(app_rdata),.fault(engine_fault),
  .axi_awaddr(axi_awaddr),.axi_awuser_ap(axi_awap),.axi_awuser_id(axi_awid),.axi_awlen(axi_awlen),.axi_awvalid(axi_awvalid),.axi_awready(1'b1),
  .axi_wdata(axi_wdata),.axi_wstrb(axi_mask),.axi_wready(1'b1),.axi_wusero_id(4'd0),.axi_wusero_last(1'b1),
  .axi_araddr(axi_araddr),.axi_aruser_ap(axi_arap),.axi_aruser_id(axi_arid),.axi_arlen(axi_arlen),.axi_arvalid(axi_arvalid),.axi_arready(arready),
  .axi_rdata(rdata),.axi_rid(4'd0),.axi_rlast(rlast),.axi_rvalid(rvalid));
 always @(posedge ui_clk)if(reset_n)begin
  if(cmd_valid&&cmd_ready)requests=requests+1;
  if(axi_arvalid&&arready)physical_reads=physical_reads+1;
  if(engine_fault||axi_awvalid)$fatal(1,"display protocol/ownership fault");
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
    mem_bank=(memory_base>=28'h0200000);
    mem_y=(memory_base+beat*8-(mem_bank?28'h0200000:28'h0100000))/OW;
    mem_x=(memory_base+beat*8-(mem_bank?28'h0200000:28'h0100000))%OW;
    if(mem_y>=OH||mem_x>=OW)$fatal(1,"read-ahead exceeded result bounds");
    for(integer lane=0;lane<8;lane=lane+1)rdata[lane*32+:32]={8'd0,encode_pixel(mem_bank,mem_y,mem_x+lane)};
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
  if(diagnostics[31:22]==0 || diagnostics[63:48]==0 || diagnostics[47:32]<diagnostics[63:48])$fatal(1,"invalid actual row timing snapshot");
  if(!EXPECT_UNDERRUN&&physical_reads!=2*OW*OH/64)$fatal(1,"unexpected prefetch transaction count %0d",physical_reads);
  test_passed=1;$display("HIRES_ENGINE_DISPLAY_PASS read_ahead=%0d expected_underflow=%0d frames=%0d correct_pixels=%0d black_pixels=%0d physical_reads=%0d logical_reads=%0d max_row_cycles=%0d model_latency_only=1",READ_AHEAD,EXPECT_UNDERRUN,completed_frames,correct_pixels,black_pixels,physical_reads,requests,diagnostics[47:32]);$finish;
 end
 initial begin #150000000;$fatal(1,"native high resolution display timeout");end
endmodule
