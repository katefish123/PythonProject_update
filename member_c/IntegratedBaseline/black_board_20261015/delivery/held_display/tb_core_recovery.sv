`timescale 1ns/1ps
// Small complete-core command-level DDR model. Native beat protocol is tested
// separately; this test exercises real RX frames, geometry and recovery.
module tb_core_recovery;
 localparam SW=64,SH=48,OW=32,OH=24,NP=SW*SH,OP=OW*OH;
 localparam[27:0]S1=28'h0800000,R0=28'h0200000,R1=28'h0400000,BIST=28'h0600000;
 reg rx=0,proc=0,ui=0,pix=0;always #3.367 rx=~rx;always #18.519 proc=~proc;always #4 ui=~ui;always #3.367 pix=~pix;
 reg rst=0,enabled=1,rxvs=0,rxde=0;reg[23:0]rxrgb=0;
 wire hs,vs,de,iv,working,fe,iw,un,sp,sf,cv,cw,cr,rsp,rw;wire[23:0]rgb;wire[31:0]good,rejected,mask;
 wire[27:0]ca;wire[255:0]cd;wire[2047:0]cb;wire[3:0]reason,phase;
 reg[255:0]rdata=0,src0[0:NP/8-1],src1[0:NP/8-1],res0[0:OP/8-1],res1[0:OP/8-1],bist[0:7];
 reg[23:0]s0[0:NP-1],s1[0:NP-1],s2[0:NP-1],s3[0:NP-1],s4[0:NP-1],e0[0:OP-1],e4[0:OP-1];
 reg pending=0,response=0,heldwrite=0;reg[27:0]heldaddr=0;reg[2047:0]helddata=0;
 integer beats=0,beat=0,delay_left=0,tick=0,seq=0,kind=0,cx=0,cy=0,current=0,produced=0,starts=0,pubs=0;
 reg[11:0]hx1=0,hx2=0,vy1=0,vy2=0;integer display0_pixels=0,display4_pixels=0;
 always @(posedge pix)begin hx1<=dut.display_reader.hc;hx2<=hx1;vy1<=dut.display_reader.vc;vy2<=vy1;end
 always @(negedge pix)if(rst&&iv)begin
  if(good<2&&(dut.display_reader.display_gen!=1||dut.display_reader.display_bank!=1))$fatal(1,"old complete display bank changed during rejection");
  if(de&&hx2>=20&&hx2<52&&vy2>=14&&vy2<38)begin
   if(rgb!==expected(dut.display_reader.display_gen==1?0:1,(vy2-14)*32+hx2-20))$fatal(1,"held/recovered displayed pixel mismatch x=%d y=%d",hx2,vy2);
   if(dut.display_reader.display_gen==1)display0_pixels=display0_pixels+1;else display4_pixels=display4_pixels+1;
  end
 end
 reg active_d=0,seen_pub=0;reg saw_rx=0,saw_marker=0,saw_solver=0,test_passed=0;
 reg[1:0]bankkind[0:1];
 assign cr=rst&&!pending&&!response&&(tick%5!=0);assign rsp=response;assign rw=heldwrite;
 video_correct_ddr_core #(.IN_W(SW),.IN_H(SH),.SRC_W(SW),.SRC_H(SH),.OUT_W(OW),.OUT_H(OH),.SCALE(1),
  .BIST_BEATS(8),.FIFO_ADDR_BITS(8),.CAPTURE_BURST_BEATS(8),.OVERLAP_CAPTURE(1),.LATE_CAPTURE_PERCENT(1),
  .ADAPTIVE_DISPLAY_GUARD(1),.INLINE_GEOMETRY(1),.SOURCE_BASE1(S1),.RESULT_BASE0(R0),.RESULT_BASE1(R1),.BIST_BASE(BIST),
  .MARKER_MIN_PIXELS(1),.MARKER_MAX_PIXELS(64),.MARKER_MAX_SPAN(16),.RETRY_CYCLES(8),.CAPTURE_TIMEOUT(10000),
  .H_SYNC(2),.H_BACK(2),.H_ACTIVE(64),.H_FRONT(4),.V_SYNC(1),.V_BACK(1),.V_ACTIVE(48),.V_FRONT(4)) dut(
  .proc_clk(proc),.proc_rst_n(rst),.rx_clk(rx),.rx_rst_n(rst),.ui_clk(ui),.ui_rst_n(rst),.pix_clk(pix),.pix_rst_n(rst),
  .hdmi_ready(enabled),.ddr_ready(rst),.memory_fault(1'b0),.rx_vs(rxvs),.rx_de(rxde),.rx_rgb(rxrgb),
  .nearest(1'b0),.force_pattern(1'b0),.hsync(hs),.vsync(vs),.de(de),.rgb(rgb),.image_valid(iv),.working(working),
  .frame_error(fe),.input_wait(iw),.display_underrun(un),.selftest_passed(sp),.selftest_failed(sf),.good_frames(good),.rejected_frames(rejected),
  .cmd_valid(cv),.cmd_ready(cr),.cmd_write(cw),.cmd_addr(ca),.cmd_wdata(cd),.cmd_wstrb(mask),.cmd_burst_data(cb),
  .rsp_valid(rsp),.rsp_write(rw),.rsp_rdata(rdata),.diagnostic_reason(reason),.diagnostic_phase(phase),
  .preview_valid(1'b0),.preview_rgb(24'd0),.overlay_on(1'b0),.overlay_rgb(24'd0),.scan_x(),.scan_y(),.scan_de(),.scan_start(),.scan_reset_n());
 function[23:0]source(input integer k,input integer i);
  case(k)0:source=s0[i];1:source=s1[i];2:source=s2[i];3:source=s3[i];default:source=s4[i];endcase
 endfunction
 function[23:0]expected(input integer k,input integer i);expected=k==0?e0[i]:e4[i];endfunction
 function[255:0]memread(input[27:0]a);
  if(a<NP)memread=src0[a/8];else if(a>=S1&&a<S1+NP)memread=src1[(a-S1)/8];
  else if(a>=R0&&a<R0+OP)memread=res0[(a-R0)/8];else if(a>=R1&&a<R1+OP)memread=res1[(a-R1)/8];
  else if(a>=BIST&&a<BIST+64)memread=bist[(a-BIST)/8];else begin memread=0;$fatal(1,"unmapped read");end
 endfunction
 task memwrite(input[27:0]a,input[255:0]d);
  if(a<NP)src0[a/8]=d;else if(a>=S1&&a<S1+NP)src1[(a-S1)/8]=d;
  else if(a>=R0&&a<R0+OP)begin if(dut.display_reader.display_bank==0&&iv)$fatal(1,"write displayed bank");res0[(a-R0)/8]=d;end
  else if(a>=R1&&a<R1+OP)begin if(dut.display_reader.display_bank==1&&iv)$fatal(1,"write displayed bank");res1[(a-R1)/8]=d;end
  else if(a>=BIST&&a<BIST+64)bist[(a-BIST)/8]=d;else $fatal(1,"unmapped write");
 endtask
 always @(posedge ui)if(rst)begin
  tick<=tick+1;response<=0;
  if(cv&&cr)begin
   pending<=1;heldwrite<=cw;heldaddr<=ca;beat<=0;delay_left<=3;
   if(cw&&(ca<NP||(ca>=S1&&ca<S1+NP)))begin beats<=8;helddata<=cb;end
   else begin beats<=1;helddata<={1792'd0,cd};end
  end
  if(pending)begin
   if(delay_left>0)delay_left<=delay_left-1;
   else if(heldwrite)begin
    memwrite(heldaddr+beat*8,helddata[beat*256+:256]);
    if(beat==beats-1)begin pending<=0;response<=1;end else beat<=beat+1;
   end else begin rdata<=memread(heldaddr);pending<=0;response<=1;end
  end
 end
 always @(negedge rx)if(rst)begin
  if(dut.source_capture.active&&!active_d)begin
   kind=seq<4?seq:4;seq=seq+1;
   $display("RECOVERY_CAPTURE kind=%0d bank=%0d time=%0t",kind,dut.capture_bank,$time);
   // Only result kinds 0/4 are consumed; encode 4 as 1 in bank ownership.
   bankkind[dut.capture_bank]=(kind==4)?1:0;
  end
  active_d=dut.source_capture.active;
  rxvs=(cy==0);rxde=(cx>=4&&cx<68&&cy>=2&&cy<50);
  if(kind==1&&cy==6&&cx==67)rxde=0; // Actual short RX line.
  rxrgb=rxde?source(kind,(cy-2)*SW+cx-4):24'h808080;
  if(cx==79)begin cx=0;if(cy==53)cy=0;else cy=cy+1;end else cx=cx+1;
 end
 always @(posedge proc)if(rst)begin
  if(sf)$fatal(1,"BIST failure");
  if(reason==12)saw_rx=1;if(reason==3)saw_marker=1;if(reason==4)saw_solver=1;
  if(dut.start)begin
   starts=starts+1;current=bankkind[dut.source_bank];produced=0;
   $display("RECOVERY_START ordinal=%0d bank=%0d time=%0t",starts,dut.source_bank,$time);
   // Solver rejection (start 2) must produce no result; good4 is start 3.
   if(starts==2)current=2;
  end
  if(dut.wr_v&&dut.wr_ready)begin
   if(current==2)$fatal(1,"degenerate solver emitted pixels");
   if(dut.wr_a!==produced||dut.wr_rgb!==expected(current,produced))$fatal(1,"recovery frame golden/order mismatch");
   produced=produced+1;
  end
  if(dut.pub_toggle!=seen_pub)begin
   seen_pub=dut.pub_toggle;pubs=pubs+1;
   if(produced!=OP)$fatal(1,"partial result published");
  end
  if(good==2)enabled<=0;
 end
 initial begin
  $readmemh("D:/FPGA/output/c_black_hold_display_20261015/recovery/source0.hex",s0);$readmemh("D:/FPGA/output/c_black_hold_display_20261015/recovery/source1.hex",s1);
  $readmemh("D:/FPGA/output/c_black_hold_display_20261015/recovery/source2.hex",s2);$readmemh("D:/FPGA/output/c_black_hold_display_20261015/recovery/source3.hex",s3);$readmemh("D:/FPGA/output/c_black_hold_display_20261015/recovery/source4.hex",s4);
  $readmemh("D:/FPGA/output/c_black_hold_display_20261015/recovery/expected0.hex",e0);$readmemh("D:/FPGA/output/c_black_hold_display_20261015/recovery/expected4.hex",e4);
  bankkind[0]=0;bankkind[1]=0;
  repeat(8)@(negedge ui);rst=1;
  wait(good==2&&pubs==2);wait(dut.display_ack==dut.pub_toggle);repeat(20)@(negedge proc);
  if(rejected!=3||starts!=3||!saw_rx||!saw_marker||!saw_solver||fe||!iv)$fatal(1,"recovery counters/reasons incomplete rejects=%d starts=%d RX=%d marker=%d solver=%d",rejected,starts,saw_rx,saw_marker,saw_solver);
  wait(display4_pixels>=OP);
  if(display0_pixels<OP)$fatal(1,"old displayed frame insufficiently checked");
  $display("RECOVERY_DISPLAY_CHECK_PASS old_pixels=%0d new_pixels=%0d",display0_pixels,display4_pixels);
  test_passed=1;$display("CORE_RECOVERY_PASS good short_RX missing_marker solver_reject good exact_pixels old_display_held counters");$finish;
 end
 initial begin #20000000;$fatal(1,"core recovery timeout starts=%0d good=%0d rejected=%0d reason=%0d captures=%0d",starts,good,rejected,reason,seq);end
endmodule
