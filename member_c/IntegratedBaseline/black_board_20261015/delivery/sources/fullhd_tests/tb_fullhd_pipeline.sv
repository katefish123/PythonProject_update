`timescale 1ns/1ps
module tb_fullhd_pipeline #(parameter OVERLAP=1,FRAMES=3,PREFETCH=0,LATE_CAPTURE=0,INLINE=0);
 localparam SW=1920,SH=1080,OW=640,OH=904,SRC_PIXELS=SW*SH,PIXELS=OW*OH;
 localparam [27:0] SRC1=28'h0800000,RES0=28'h0200000,RES1=28'h0400000,BIST=28'h0600000;
 reg proc_clk=0,rx_clk=0,ui_clk=0,pix_clk=0;
 always #18.5185185 proc_clk=~proc_clk;
 always #3.3670035 rx_clk=~rx_clk;
 always #4 ui_clk=~ui_clk;
 always #3.3670035 pix_clk=~pix_clk;
 reg rst_n=0,enabled=1,rx_vs=0,rx_de=0;reg [23:0] rx_rgb=0;
 wire hs,vs,de,image_valid,working,frame_error,input_wait,underrun,bist_pass,bist_fail,engine_fault;
 wire [23:0] rgb;wire [31:0] good,rejected;
 wire cmd_v,cmd_r,cmd_w,rsp_v,rsp_w;wire [27:0] cmd_a;wire [255:0] cmd_data,rsp_data;wire [31:0] cmd_mask;
 reg [23:0] source0[0:SRC_PIXELS-1],source1[0:SRC_PIXELS-1],source2[0:SRC_PIXELS-1],expected0[0:PIXELS-1],expected1[0:PIXELS-1],expected2[0:PIXELS-1];
 reg [255:0] source_ram0[0:SRC_PIXELS/8-1],source_ram1[0:SRC_PIXELS/8-1];
 reg [255:0] result_ram0[0:PIXELS/8-1],result_ram1[0:PIXELS/8-1],bist_ram[0:7];
 reg [95:0] expected_geometry[0:2];
 reg [1:0] source_kind[0:1],result_kind[0:1];time source_time[0:1];
 integer camera_x=0,camera_y=0,capture_seq=0,camera_kind=0;
 reg capture_active_d=0;
 integer ui_tick=0,commands=0,capture_beats=0,result_beats=0,overlap_beats=0,physical_reads=0;
 integer processing_frame=0,current_kind=0,produced=0,published=0,display_frames=0,display_pixels=0;
 reg seen_pub=0,previous_vs=0,check_display=0;integer display_kind=0,row_pixels=0,checked_generation=0,last_checked_generation=0;
 reg [11:0] hd1=0,hd2=0,vd1=0,vd2=0;
 integer proc_tick=0,last_start=0,interval_sum=0,interval_count=0,avg_interval=0;
 integer scan_cycles=0,solve_cycles=0,read_cycles=0,interp_cycles=0,write_cycles=0,other_cycles=0;
 integer bridge_wait=0,max_bridge_wait=0;time active_source_time=0,process_started=0;
 reg test_passed=0;
 wire[2047:0]burst_payload;wire[3:0]engine_reason;
 video_correct_ddr_core #(.CAPTURE_BURST_BEATS(8),.IN_W(SW),.IN_H(SH),.SRC_W(SW),.SRC_H(SH),.OUT_W(OW),.OUT_H(OH),.SCALE(1),
  .FIFO_ADDR_BITS(10),.BIST_BEATS(8),.OVERLAP_CAPTURE(OVERLAP),.LATE_CAPTURE_PERCENT(LATE_CAPTURE),.ADAPTIVE_DISPLAY_GUARD(PREFETCH),.INLINE_GEOMETRY(INLINE),.BLACK_RMIN(0),.BLACK_RMAX(64),.BLACK_GMIN(0),.BLACK_GMAX(64),.BLACK_BMIN(0),.BLACK_BMAX(64),.P0_XMIN(580),.P0_XMAX(681),.P0_YMIN(86),.P0_YMAX(187),.P1_XMIN(1410),.P1_XMAX(1511),.P1_YMIN(174),.P1_YMAX(275),.P2_XMIN(1480),.P2_XMAX(1581),.P2_YMIN(920),.P2_YMAX(1021),.P3_XMIN(226),.P3_XMAX(327),.P3_YMIN(886),.P3_YMAX(987),.SOURCE_BASE1(SRC1),
  .RESULT_BASE0(RES0),.RESULT_BASE1(RES1),.BIST_BASE(BIST),
  .MARKER_MIN_PIXELS(64),.MARKER_MAX_PIXELS(16384),.MARKER_MAX_SPAN(256)) dut(.scan_x(),.scan_y(),.scan_de(),.scan_start(),.scan_reset_n(),.diagnostic_reason(),.diagnostic_phase(),.preview_valid(1'b0),.preview_rgb(24'd0),.overlay_on(1'b0),.overlay_rgb(24'd0),
  .proc_clk(proc_clk),.proc_rst_n(rst_n),.rx_clk(rx_clk),.rx_rst_n(rst_n),
  .pix_clk(pix_clk),.pix_rst_n(rst_n),.ui_clk(ui_clk),.ui_rst_n(rst_n),
  .hdmi_ready(enabled),.ddr_ready(rst_n),.memory_fault(engine_fault),.rx_vs(rx_vs),.rx_de(rx_de),.rx_rgb(rx_rgb),
  .nearest(1'b0),.force_pattern(1'b0),.hsync(hs),.vsync(vs),.de(de),.rgb(rgb),
  .image_valid(image_valid),.working(working),.frame_error(frame_error),.input_wait(input_wait),.display_underrun(underrun),
  .selftest_passed(bist_pass),.selftest_failed(bist_fail),.good_frames(good),.rejected_frames(rejected),
  .cmd_burst_data(burst_payload),.cmd_valid(cmd_v),.cmd_ready(cmd_r),.cmd_write(cmd_w),.cmd_addr(cmd_a),.cmd_wdata(cmd_data),.cmd_wstrb(cmd_mask),
  .rsp_valid(rsp_v),.rsp_write(rsp_w),.rsp_rdata(rsp_data));
 wire [27:0] awaddr,araddr;wire [3:0] awid,arid,awlen,arlen;
 wire awap,arap,awvalid,arvalid;wire [255:0] wdata;wire [31:0] wmask;
 reg rvalid=0,rlast=0;reg [255:0] rdata=0;
 reg read_pending=0;reg [27:0] read_base=0;integer read_beat=0,read_total=0,read_delay=0;
 reg write_pending=0;reg[27:0]write_base=0;integer write_index=0,write_total=0;
 wire wready=rst_n&&(ui_tick%11!=0);
 wire wlast=write_pending?(write_index==write_total-1):(awlen==0);
 wire[27:0]physical_addr=write_pending?write_base+write_index*8:awaddr;
 wire awready=rst_n&&(ui_tick%17>=2);
 wire arready=rst_n&&!read_pending&&(ui_tick%7!=0);
 ddr_word_engine #(.CAPTURE_BURST_BEATS(8),.READ_AHEAD_ENABLE(1),.SOURCE_PREFETCH_ENABLE(PREFETCH),.SOURCE_WORDS(SRC_PIXELS),.SOURCE_BASE1(SRC1),.RESULT_WORDS(PIXELS),.RESULT_BASE0(RES0),.RESULT_BASE1(RES1)) engine(.capture_burst_data(burst_payload),.fault_reason(engine_reason),
  .clk(ui_clk),.rst_n(rst_n),.init_done(rst_n),.cmd_valid(cmd_v),.cmd_ready(cmd_r),.cmd_write(cmd_w),.cmd_addr(cmd_a),
  .cmd_wdata(cmd_data),.cmd_wstrb(cmd_mask),.rsp_valid(rsp_v),.rsp_write(rsp_w),.rsp_rdata(rsp_data),.fault(engine_fault),
  .axi_awaddr(awaddr),.axi_awuser_ap(awap),.axi_awuser_id(awid),.axi_awlen(awlen),.axi_awvalid(awvalid),.axi_awready(awready),
  .axi_wdata(wdata),.axi_wstrb(wmask),.axi_wready(wready),.axi_wusero_id(4'd0),.axi_wusero_last(wlast),
  .axi_araddr(araddr),.axi_aruser_ap(arap),.axi_aruser_id(arid),.axi_arlen(arlen),.axi_arvalid(arvalid),.axi_arready(arready),
  .axi_rdata(rdata),.axi_rid(4'd0),.axi_rlast(rlast),.axi_rvalid(rvalid));
 function [23:0] source_pixel(input integer kind,input integer index);
  source_pixel=(kind==2)?source2[index]:(kind==1)?source1[index]:source0[index];
 endfunction
 function [23:0] expected_pixel(input integer kind,input integer index);
  expected_pixel=(kind==2)?expected2[index]:(kind==1)?expected1[index]:expected0[index];
 endfunction
 function [255:0] memory_read(input [27:0] a);
  begin
   if(a<SRC_PIXELS)memory_read=source_ram0[a>>3];
   else if(a>=SRC1&&a<SRC1+SRC_PIXELS)memory_read=source_ram1[(a-SRC1)>>3];
   else if(a>=RES0&&a<RES0+PIXELS)memory_read=result_ram0[(a-RES0)>>3];
   else if(a>=RES1&&a<RES1+PIXELS)memory_read=result_ram1[(a-RES1)>>3];
   else if(a>=BIST&&a<BIST+64)memory_read=bist_ram[(a-BIST)>>3];
   else begin memory_read=0;$fatal(1,"unmapped physical read %h",a);end
  end
 endfunction
 // Free-running 1080p60 raster. RGB is only evaluated when the actual capture
 // block is active; uncaptured frames still have the same VS/DE timing.
 always @(negedge rx_clk)begin
  if(!rst_n)begin camera_x=0;camera_y=0;rx_vs=0;rx_de=0;rx_rgb=0;capture_active_d=0;end
  else begin
   if(dut.source_capture.active&&!capture_active_d)begin
    camera_kind=capture_seq%3;capture_seq=capture_seq+1;
    source_kind[dut.capture_bank]=camera_kind;source_time[dut.capture_bank]=$time;
   end
   capture_active_d=dut.source_capture.active;
   rx_vs=(camera_y<5);
   rx_de=(camera_x>=192&&camera_x<2112&&camera_y>=41&&camera_y<1121);
   if(rx_de&&dut.source_capture.active)begin
    rx_rgb=source_pixel(camera_kind,(camera_y-41)*SW+camera_x-192);
   end else rx_rgb=0;
   if(camera_x==2199)begin camera_x=0;if(camera_y==1124)camera_y=0;else camera_y=camera_y+1;end
   else camera_x=camera_x+1;
   if(dut.source_capture.active&&dut.fifo_full)$fatal(1,"FULLHD_PIPELINE_CAPTURE_OVERFLOW");
  end
 end
 always @(posedge ui_clk)if(rst_n)begin
  ui_tick<=ui_tick+1;
  if(cmd_v&&cmd_r)commands=commands+1;
  if(dut.br_v&&!dut.br_r)begin bridge_wait=bridge_wait+1;if(bridge_wait>max_bridge_wait)max_bridge_wait=bridge_wait;end
  else bridge_wait=0;
  if(engine_fault||bist_fail)$fatal(1,"native engine or BIST failed");
  if(arvalid&&arready)begin
   read_pending<=1;read_base<=araddr;read_total<=arlen+1;read_beat<=0;
   read_delay<=28+((physical_reads%128==127)?100:0);physical_reads=physical_reads+1;
  end
  if(awvalid&&awready)begin
   if(write_pending)$fatal(1,"overlapping physical AW");
   if(awlen!=0&&awlen!=7)$fatal(1,"invalid AWLEN");
   write_pending<=1;write_base<=awaddr;write_index<=0;write_total<=awlen+1;
  end
  if(wready&&(write_pending||(awvalid&&awready)))begin: physical_write
   integer rel,bank,kind;
   if(physical_addr[2:0]!=0||wmask!==32'hffffffff)$fatal(1,"unaligned/masked physical write");
   if(physical_addr<SRC_PIXELS||(physical_addr>=SRC1&&physical_addr<SRC1+SRC_PIXELS))begin
    bank=(physical_addr>=SRC1);rel=physical_addr-(bank?SRC1:0);kind=source_kind[bank];
    if(working)begin
     if(bank==dut.source_bank)$fatal(1,"capture overwrote locked source bank");
     overlap_beats=overlap_beats+1;
    end
    for(integer lane=0;lane<8;lane=lane+1)
     if(wdata[lane*32+:24]!==source_pixel(kind,rel+lane))$fatal(1,"native capture RGB mismatch bank=%0d addr=%0d",bank,rel+lane);
    if(bank)source_ram1[rel>>3]<=wdata;else source_ram0[rel>>3]<=wdata;
    capture_beats=capture_beats+1;
   end else if((physical_addr>=RES0&&physical_addr<RES0+PIXELS)||(physical_addr>=RES1&&physical_addr<RES1+PIXELS))begin
    bank=(physical_addr>=RES1);rel=physical_addr-(bank?RES1:RES0);
    if(bank==dut.display_reader.display_bank)$fatal(1,"native write to active display bank");
    for(integer lane=0;lane<8;lane=lane+1)
     if(wdata[lane*32+:24]!==expected_pixel(current_kind,rel+lane))$fatal(1,"native result mismatch addr=%0d",rel+lane);
    if(bank)result_ram1[rel>>3]<=wdata;else result_ram0[rel>>3]<=wdata;
    result_beats=result_beats+1;
   end else if(physical_addr>=BIST&&physical_addr<BIST+64)bist_ram[(physical_addr-BIST)>>3]<=wdata;
   else $fatal(1,"unmapped physical write %h",physical_addr);
   if(wlast)begin write_pending<=0;write_index<=0;end
   else begin write_pending<=1;write_index<=write_pending?write_index+1:1;end
  end
 end
 always @(negedge ui_clk)begin
  rvalid<=0;rlast<=0;
  if(!rst_n)read_pending<=0;
  else if(read_pending)begin
   if(read_delay>0)read_delay<=read_delay-1;
   else begin
    rvalid<=1;rdata<=memory_read(read_base+read_beat*8);rlast<=(read_beat==read_total-1);
    read_beat<=read_beat+1;
    if(read_beat==read_total-1)read_pending<=0;
   end
  end
 end
 always @(posedge proc_clk)if(rst_n)begin
  proc_tick=proc_tick+1;
  if(rejected!=0)$fatal(1,"full-HD frame rejected count=%0d",rejected);
  if(underrun&&image_valid)$fatal(1,"full-HD display underrun");
  if(dut.start)begin
   if(processing_frame>0)begin interval_sum=interval_sum+proc_tick-last_start;interval_count=interval_count+1;end
   last_start=proc_tick;processing_frame=processing_frame+1;current_kind=source_kind[dut.source_bank];
   if(current_kind!==(processing_frame-1)%3)$fatal(1,"input sequence changed between modes");
   if(INLINE && (!dut.processor.input_geometry_valid || dut.processor.input_corners!==expected_geometry[current_kind]))$fatal(1,"source geometry generation mismatch");
   result_kind[dut.write_bank]=current_kind;active_source_time=source_time[dut.source_bank];process_started=$time;
   scan_cycles=0;solve_cycles=0;read_cycles=0;interp_cycles=0;write_cycles=0;other_cycles=0;produced=0;
   if(LATE_CAPTURE>0 && $time-active_source_time>64'd50000000)
    $fatal(1,"late capture source age exceeds 50 ms");
   $display("FULLHD_FRAME_BEGIN mode=%0d frame=%0d source_bank=%0d kind=%0d time_ns=%0d source_age_ns=%0d",OVERLAP,processing_frame,dut.source_bank,current_kind,$time,$time-active_source_time);
  end
  if(INLINE && (dut.processor.state==1||dut.processor.state==2))$fatal(1,"unexpected DDR source rescan");
  if(dut.p_busy)begin
   case(dut.processor.state)
    1,2:scan_cycles=scan_cycles+1;
    3,4:solve_cycles=solve_cycles+1;
    7,8:read_cycles=read_cycles+1;
    9,10:interp_cycles=interp_cycles+1;
    11:write_cycles=write_cycles+1;
    default:other_cycles=other_cycles+1;
   endcase
  end
  if(dut.wr_v&&dut.wr_ready)begin
   if(dut.wr_a!==produced||dut.wr_rgb!==expected_pixel(current_kind,produced))$fatal(1,"full-HD output order/RGB mismatch addr=%0d frame=%0d",dut.wr_a,processing_frame);
   produced=produced+1;
  end
  if(dut.p_done)begin
   if(produced!=PIXELS)$fatal(1,"incomplete corrected frame");
   $display("FULLHD_PHASE_PROFILE mode=%0d frame=%0d scan=%0d solve=%0d read=%0d interp=%0d write=%0d other=%0d processing_ns=%0d",OVERLAP,processing_frame,scan_cycles,solve_cycles,read_cycles,interp_cycles,write_cycles,other_cycles,$time-process_started);
  end
  if(dut.pub_toggle!=seen_pub)begin
   seen_pub=dut.pub_toggle;published=published+1;
   if(result_beats!=published*(PIXELS/8))$fatal(1,"published incomplete native result");
   $display("FULLHD_FRAME_PUBLISH mode=%0d frame=%0d time_ns=%0d image_age_ns=%0d",OVERLAP,published,$time,$time-active_source_time);
  end
 end
 always @(posedge pix_clk)begin hd1<=dut.display_reader.hc;hd2<=hd1;vd1<=dut.display_reader.vc;vd2<=vd1;end
 always @(negedge pix_clk)if(rst_n)begin
  if(vs&&!previous_vs)begin
   checked_generation=dut.display_reader.display_gen;
   check_display=image_valid&&(checked_generation>last_checked_generation);row_pixels=0;
   if(check_display&&checked_generation!=last_checked_generation+1)$fatal(1,"display skipped a published generation");
   display_kind=result_kind[dut.display_reader.display_bank];
  end
  if(check_display&&de&&hd2>=832&&hd2<1472&&vd2>=129&&vd2<1033)begin
   if(dut.display_reader.display_gen!=checked_generation)$fatal(1,"display generation changed inside frame");
   if(rgb!==expected_pixel(display_kind,(vd2-129)*OW+hd2-832))$fatal(1,"full-HD displayed RGB mismatch x=%0d y=%0d",hd2-832,vd2-129);
   row_pixels=row_pixels+1;display_pixels=display_pixels+1;
   if(hd2==1471&&vd2==1032)begin
    if(row_pixels!=PIXELS)$fatal(1,"incomplete display check");
    display_frames=display_frames+1;last_checked_generation=checked_generation;check_display=0;
   end
  end
  previous_vs=vs;
 end
 initial begin
  $display("FULLHD_PIPELINE_CONFIG overlap=%0d prefetch=%0d late_percent=%0d inline=%0d",OVERLAP,PREFETCH,LATE_CAPTURE,INLINE);
  $readmemh("D:/FPGA/output/c_black_burst_merge_v3_20261015/fullhd_tests/source_1920x1080.hex",source0);
  $readmemh("D:/FPGA/output/c_black_burst_merge_v3_20261015/fullhd_tests/source_variant_1920x1080.hex",source1);
  $readmemh("D:/FPGA/output/c_black_burst_merge_v3_20261015/fullhd_tests/expected_640x904.hex",expected0);
  $readmemh("D:/FPGA/output/c_black_burst_merge_v3_20261015/fullhd_tests/expected_variant_640x904.hex",expected1);
  $readmemh("D:/FPGA/output/c_black_burst_merge_v3_20261015/fullhd_tests/source_variant2_1920x1080.hex",source2);
  $readmemh("D:/FPGA/output/c_black_burst_merge_v3_20261015/fullhd_tests/expected_variant2_640x904.hex",expected2);
  $readmemh("D:/FPGA/output/c_black_burst_merge_v3_20261015/fullhd_tests/source_corners96.hex",expected_geometry);
  source_kind[0]=0;source_kind[1]=0;result_kind[0]=0;result_kind[1]=0;source_time[0]=0;source_time[1]=0;
  repeat(8)@(negedge ui_clk);rst_n=1;
  wait(good>=FRAMES);enabled=0;wait(published==FRAMES);wait(display_frames==FRAMES);
  avg_interval=interval_sum/interval_count;
  if(interval_count!=FRAMES-1||processing_frame!=FRAMES||result_beats!=FRAMES*PIXELS/8)$fatal(1,"benchmark frame count mismatch");
  if(OVERLAP&&overlap_beats==0)$fatal(1,"full-HD pipeline did not overlap capture");
  if(max_bridge_wait>=4629000)$fatal(1,"bridge wait exceeded stage watchdog budget");
  test_passed=1;
  $display("FULLHD_PIPELINE_PASS mode=%0d frames=%0d corrected_pixels=%0d display_pixels=%0d average_start_interval_cycles=%0d max_ui_wait=%0d overlap_beats=%0d native_reads=%0d",OVERLAP,published,FRAMES*PIXELS,display_pixels,avg_interval,max_bridge_wait,overlap_beats,physical_reads);
  $finish;
 end
 initial begin #(64'd10000000000);$fatal(1,"full-HD multi-frame test timeout");end
endmodule
