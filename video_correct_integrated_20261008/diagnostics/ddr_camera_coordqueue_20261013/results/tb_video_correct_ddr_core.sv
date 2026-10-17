`timescale 1ns/1ps
module tb_video_correct_ddr_core;
 localparam IW=128,IH=96,SW=64,SH=48,OW=32,OH=24,PIXELS=OW*OH,SRC_PIXELS=SW*SH,WORDS=PIXELS/8;
 reg proc_clk=0,rx_clk=0,ui_clk=0,pix_clk=0;
 always #5 proc_clk=~proc_clk;
 always #3.5 rx_clk=~rx_clk;
 always #4 ui_clk=~ui_clk;
 always #6.5 pix_clk=~pix_clk;
 reg proc_rst_n=0,rx_rst_n=0,ui_rst_n=0,pix_rst_n=0;
 reg rx_vs=0,rx_de=0; reg [23:0] rx_rgb=0;
 reg hdmi_ready=1,ddr_ready=1,memory_fault=0,nearest=1,force_pattern=0;
 wire hsync,vsync,de; wire [23:0] rgb;
 wire image_valid,working,frame_error,input_wait,display_underrun,selftest_passed,selftest_failed;
 wire [31:0] good_frames,rejected_frames;
 wire cmd_valid,cmd_write; wire [27:0] cmd_addr; wire [255:0] cmd_wdata; wire [31:0] cmd_wstrb;
 reg cmd_ready=0,rsp_valid=0,rsp_write=0; reg [255:0] rsp_rdata=0;
 reg [23:0] src0[0:PIXELS*4-1],src1[0:PIXELS*4-1],src2[0:PIXELS*4-1],exp0[0:PIXELS-1],exp1[0:PIXELS-1];
 reg [255:0] src_mem[0:WORDS*4-1],bank0[0:WORDS-1],bank1[0:WORDS-1],bist_mem[0:15];
 integer cmd_count=0,cap_writes=0,dest_writes=0,dest_responses=0,display_reads=0,bist_writes=0,bist_reads=0,pub_seen=0,pub_count=0;
 integer rng=1,delay_count=0,resp_wait=0,burst_delay=0; reg pending=0,pending_write=0; reg [27:0] pending_addr; reg [255:0] pending_data;
 integer i,j,k,idx,frame_no=0,checks=0; reg test_passed=0;
 integer chkbeat,chklane;
 video_correct_ddr_core #(.IN_W(IW),.IN_H(IH),.SRC_W(SW),.SRC_H(SH),.OUT_W(OW),.OUT_H(OH),.SCALE(2),
  .H_SYNC(1),.H_BACK(1),.H_ACTIVE(80),.H_FRONT(1),.V_SYNC(1),.V_BACK(8),.V_ACTIVE(64),.V_FRONT(1),
  .CAPTURE_TIMEOUT(500000),.RETRY_CYCLES(40),.FIFO_ADDR_BITS(8),.BIST_BEATS(8)) dut(
  .proc_clk(proc_clk),.proc_rst_n(proc_rst_n),.rx_clk(rx_clk),.rx_rst_n(rx_rst_n),.pix_clk(pix_clk),.pix_rst_n(pix_rst_n),.ui_clk(ui_clk),.ui_rst_n(ui_rst_n),
  .hdmi_ready(hdmi_ready),.ddr_ready(ddr_ready),.memory_fault(memory_fault),.rx_vs(rx_vs),.rx_de(rx_de),.rx_rgb(rx_rgb),.nearest(nearest),.force_pattern(force_pattern),
  .hsync(hsync),.vsync(vsync),.de(de),.rgb(rgb),.image_valid(image_valid),.working(working),.frame_error(frame_error),.input_wait(input_wait),.display_underrun(display_underrun),
  .selftest_passed(selftest_passed),.selftest_failed(selftest_failed),.good_frames(good_frames),.rejected_frames(rejected_frames),
  .cmd_valid(cmd_valid),.cmd_write(cmd_write),.cmd_addr(cmd_addr),.cmd_wdata(cmd_wdata),.cmd_wstrb(cmd_wstrb),.cmd_ready(cmd_ready),.rsp_valid(rsp_valid),.rsp_write(rsp_write),.rsp_rdata(rsp_rdata));
 function [255:0] memory_read(input [27:0] a);
  integer n; begin
   if(a>=28'h03f0000 && a<28'h03f0040) memory_read=bist_mem[(a-28'h03f0000)>>3];
   else if(a<SRC_PIXELS) memory_read=src_mem[a>>3];
   else if(a>=28'h0100000 && a<28'h0100000+WORDS*8) memory_read=bank0[(a-28'h0100000)>>3];
   else if(a>=28'h0200000 && a<28'h0200000+WORDS*8) memory_read=bank1[(a-28'h0200000)>>3];
   else memory_read=256'hbad0bad0;
  end
 endfunction
 always @(negedge ui_clk) begin
  if(!ui_rst_n) begin cmd_ready<=0;rsp_valid<=0;pending<=0;end
  else begin
   rng=(rng*1103515245+12345)&32'h7fffffff;
   cmd_ready<=!pending && ((rng%5)!=0);
   rsp_valid<=0;
   if(pending) begin
    if(delay_count>0) delay_count<=delay_count-1;
    else begin
     rsp_valid<=1;rsp_write<=pending_write;
     if(pending_write) rsp_rdata<=0; else rsp_rdata<=memory_read(pending_addr);
     if(pending_write && ((pending_addr>=28'h0100000 && pending_addr<28'h0100000+WORDS*8) || (pending_addr>=28'h0200000 && pending_addr<28'h0200000+WORDS*8))) dest_responses<=dest_responses+1;
     pending<=0;
    end
   end
  end
 end
 always @(posedge ui_clk) if(ui_rst_n&&cmd_valid&&cmd_ready) begin
  if(pending) $fatal(1,"overlapping UI memory commands");
  pending<=1;pending_write<=cmd_write;pending_addr<=cmd_addr;pending_data<=cmd_wdata;delay_count<=(cmd_count%4);
  cmd_count<=cmd_count+1;
  if(cmd_addr>=28'h03f0000 && cmd_addr<28'h03f0040) begin
   if(cmd_write) begin bist_mem[(cmd_addr-28'h03f0000)>>3]<=cmd_wdata;bist_writes<=bist_writes+1;end
   else bist_reads<=bist_reads+1;
  end else if(cmd_write) begin
   if(cmd_addr<SRC_PIXELS) begin if(cmd_addr[2:0]!=0)$fatal(1,"unaligned source beat address");src_mem[cmd_addr>>3]<=cmd_wdata;cap_writes<=cap_writes+1;end
   else if(cmd_addr>=28'h0100000 && cmd_addr<28'h0100000+WORDS*8) begin if(cmd_addr[2:0]!=0)$fatal(1,"unaligned bank0 beat address");if(dut.display_reader.display_bank==0)$fatal(1,"write to active display bank0");bank0[(cmd_addr-28'h0100000)>>3]<=cmd_wdata;dest_writes<=dest_writes+1;end
   else if(cmd_addr>=28'h0200000 && cmd_addr<28'h0200000+WORDS*8) begin if(cmd_addr[2:0]!=0)$fatal(1,"unaligned bank1 beat address");if(dut.display_reader.display_bank==1)$fatal(1,"write to active display bank1");bank1[(cmd_addr-28'h0200000)>>3]<=cmd_wdata;dest_writes<=dest_writes+1;end
   else $fatal(1,"unexpected write address %h",cmd_addr);
  end else begin
   if(cmd_addr<SRC_PIXELS && cap_writes<(good_frames+1)*(SRC_PIXELS/8)) $fatal(1,"read source before capture writes drained: %0d",cap_writes);
   if(cmd_addr>=28'h0100000 && cmd_addr<28'h0100000+WORDS*8 || cmd_addr>=28'h0200000 && cmd_addr<28'h0200000+WORDS*8) display_reads<=display_reads+1;
  end
 end
 task send_frame(input integer which,input integer corrupt);
  integer x,y,si; reg [23:0] pix; begin
   @(negedge rx_clk);rx_vs<=1;rx_de<=0; repeat(2) @(negedge rx_clk);rx_vs<=0;
   for(y=0;y<IH;y=y+1) begin
    for(x=0;x<(corrupt&&y==IH/2?IW-1:IW);x=x+1) begin
     si=(y/2)*SW+(x/2);
     if(which==0)pix=src0[si];else if(which==1)pix=src1[si];else pix=src2[si];
     rx_de<=1;rx_rgb<=pix;@(negedge rx_clk);
    end
    rx_de<=0;repeat(2) @(negedge rx_clk);
   end
   rx_de<=0;rx_vs<=1;repeat(2) @(negedge rx_clk);rx_vs<=0;
  end endtask
 task check_capture; integer z,q; begin
  if(cap_writes!=SRC_PIXELS/8) $fatal(1,"capture count %0d expected %0d",cap_writes,SRC_PIXELS/8);
  for(z=0;z<SRC_PIXELS/8;z=z+1) for(q=0;q<8;q=q+1)
   if(src_mem[z][q*32+:24]!==src0[z*8+q]) $fatal(1,"source snapshot mismatch beat=%0d lane=%0d",z,q);
 end endtask
 always @(posedge proc_clk) if(proc_rst_n&&dut.start) begin
  if(cap_writes<(good_frames+1)*(SRC_PIXELS/8)) $fatal(1,"processing started before complete source: %0d",cap_writes);
  for(chkbeat=0;chkbeat<SRC_PIXELS/8;chkbeat=chkbeat+1) for(chklane=0;chklane<8;chklane=chklane+1) begin
   if(good_frames==1) begin
    if(src_mem[chkbeat][chklane*32+:24]!==src1[chkbeat*8+chklane])$fatal(1,"source1 DDR snapshot mismatch beat=%0d lane=%0d",chkbeat,chklane);
   end else if(src_mem[chkbeat][chklane*32+:24]!==src0[chkbeat*8+chklane])$fatal(1,"source0 DDR snapshot mismatch beat=%0d lane=%0d",chkbeat,chklane);
  end
 end
 always @(posedge proc_clk) if(proc_rst_n&&dut.pub_toggle!=pub_seen) begin
  if(dest_responses<(pub_count+1)*WORDS)$fatal(1,"published before target write responses completed: %0d",dest_responses);
  pub_count=pub_count+1;
  pub_seen=dut.pub_toggle;
 end
 task compare_frame(input integer bank,input integer which); integer x,y,beat,lane; reg [23:0] got; begin
  for(y=0;y<OH;y=y+1) for(x=0;x<OW;x=x+1) begin
   beat=(y*OW+x)/8;lane=(y*OW+x)%8;
   if(bank)got=bank1[beat][lane*32+:24];else got=bank0[beat][lane*32+:24];
   if(which==0 && got!==exp0[y*OW+x])$fatal(1,"frame0 mismatch %0d,%0d got=%h exp=%h",x,y,got,exp0[y*OW+x]);
   if(which==1 && got!==exp1[y*OW+x])$fatal(1,"frame1 mismatch %0d,%0d got=%h exp=%h",x,y,got,exp1[y*OW+x]);
  end
 end endtask
 task display_check(input integer which); integer x,y; reg [23:0] e; begin
  // Scan a complete active raster; the centered 64x48 window expands each result pixel 2x2.
  @(posedge vsync);wait(de===1'b0);
  for(y=0;y<64;y=y+1) begin
   wait(de===1'b1);
   for(x=0;x<80;x=x+1) begin
    @(negedge pix_clk);
    if(x>=8 && x<72 && y>=8 && y<56) begin
     if(which==0)e=exp0[((y-8)/2)*OW+((x-8)/2)];else e=exp1[((y-8)/2)*OW+((x-8)/2)];
     if(rgb!==e)$fatal(1,"display mismatch frame=%0d x=%0d y=%0d got=%h expected=%h",which,x,y,rgb,e);
    end
   end
   wait(de===1'b0);
  end
 end endtask
 initial begin
  $readmemh("C:/D/FPGA/video_correct_integrated_20261008/vendor/b/vectors/source0.hex",src0);$readmemh("C:/D/FPGA/video_correct_integrated_20261008/vendor/b/vectors/source1.hex",src1);$readmemh("C:/D/FPGA/video_correct_integrated_20261008/vendor/b/vectors/source2.hex",src2);
  $readmemh("C:/D/FPGA/video_correct_integrated_20261008/vendor/b/vectors/expected0.hex",exp0);$readmemh("C:/D/FPGA/video_correct_integrated_20261008/vendor/b/vectors/expected1.hex",exp1);
  for(i=0;i<WORDS*4;i=i+1)src_mem[i]=0;
  for(i=0;i<WORDS;i=i+1)begin bank0[i]=0;bank1[i]=0;end
  repeat(6)@(negedge ui_clk);proc_rst_n=1;rx_rst_n=1;ui_rst_n=1;pix_rst_n=1;
  wait(selftest_passed); $display("BIST_PASS writes=%0d reads=%0d",bist_writes,bist_reads); nearest=0;
  fork begin wait(dut.capture_req!=dut.capture_ack);repeat(5)@(negedge rx_clk);while(good_frames<1) send_frame(0,0); end begin wait(good_frames==1); end join_any disable fork;
  wait(!working); #1;check_capture();
  if(dest_writes!=WORDS)$fatal(1,"target write completion count before publish=%0d",dest_writes);
  compare_frame(1,0); wait(image_valid);display_check(0);
  if(display_underrun)$fatal(1,"display underrun on first frame");
  nearest=1;fork begin while(good_frames<2) send_frame(1,0); end begin wait(good_frames==2); end join_any disable fork;
  wait(!working); #1;compare_frame(0,1);wait(dut.display_ack==dut.pub_toggle);display_check(1);
  if(display_underrun)$fatal(1,"display underrun on second frame");
  fork begin while(rejected_frames==0) send_frame(2,1); end begin wait(rejected_frames>0); end join_any disable fork;
  if(good_frames!=2)$fatal(1,"bad frame unexpectedly published");
  compare_frame(0,1);wait(dut.display_ack==dut.pub_toggle);display_check(1);
  proc_rst_n=0;rx_rst_n=0;ui_rst_n=0;pix_rst_n=0;rx_vs=0;rx_de=0;rx_rgb=0;
  repeat(6)@(negedge proc_clk);proc_rst_n=1;rx_rst_n=1;ui_rst_n=1;pix_rst_n=1;nearest=0;
  wait(selftest_passed);
  fork begin wait(dut.capture_req!=dut.capture_ack);repeat(5)@(negedge rx_clk);while(good_frames<1)send_frame(0,0);end begin wait(good_frames==1);end join_any disable fork;
  wait(!working);compare_frame(1,0);wait(image_valid);wait(dut.display_ack==dut.pub_toggle);display_check(0);
  if(display_underrun)$fatal(1,"display underrun after common-reset recovery");
  $display("DDR_CORE_PASS good=%0d rejected=%0d cmd=%0d capture=%0d dest=%0d display_reads=%0d publications=%0d",good_frames,rejected_frames,cmd_count,cap_writes,dest_writes,display_reads,pub_count);
  test_passed=1;$finish;
 end
 initial begin #30000000;$display("DEBUG good=%0d reject=%0d cap=%0d dest=%0d work=%b wait=%b session=%0d",good_frames,rejected_frames,cap_writes,dest_writes,working,input_wait,dut.session.state);$fatal(1,"timeout");end
endmodule
