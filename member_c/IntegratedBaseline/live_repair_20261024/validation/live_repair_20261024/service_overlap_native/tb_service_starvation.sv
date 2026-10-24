`timescale 1ns/1ps
module tb_service_starvation #(parameter ADVERSE=1);
 localparam NATIVE=1,FRAMES=3,CORRECTED=0,REQUIRE_RAW30=0,BAD_FRAME=0,CAMERA_START_LINE=0,RGB_PATTERN=1;
 integer pixel_errors=0,fifo_full_cycles=0,close12=0,close13=0,first_pub_frame=0;
 localparam SW=1920,SH=1080,OW=1920;
 localparam HS=44,HB=148,HF=88;
 localparam VS=5,VB=36,VF=4;
 localparam HT=HS+HB+SW+HF,VT=VS+VB+SH+VF,WORDS=SW*SH;
 localparam[27:0]SRC1=28'h0800000,BIST=28'h0600000;
 reg proc_clk=0,ui_clk=0,rx_clk=0,pix_clk=0,rst_n=0;
 always #8.754037 proc_clk=~proc_clk;
 always #4 ui_clk=~ui_clk;
 always #3.3670035 rx_clk=~rx_clk;
 always #3.3670035 pix_clk=~pix_clk;
 reg rx_hs=0;reg rx_vs=0,rx_de=0;reg[23:0]rx_rgb=0;
 reg rx_hs_f;reg rx_vs_f,rx_de_f;reg[23:0]rx_rgb_f;
 always @(negedge rx_clk or negedge rst_n)begin
  if(!rst_n)begin rx_hs_f<=0;rx_vs_f<=0;rx_de_f<=0;rx_rgb_f<=0;end
  else begin rx_hs_f<=rx_hs;rx_vs_f<=rx_vs;rx_de_f<=rx_de;rx_rgb_f<=rx_rgb;end
 end
 reg rx_hs_q;reg rx_vs_q,rx_de_q;reg[23:0]rx_rgb_q;
 always @(posedge rx_clk or negedge rst_n)begin
  if(!rst_n)begin rx_hs_q<=0;rx_vs_q<=0;rx_de_q<=0;rx_rgb_q<=0;end
  else begin rx_hs_q<=rx_hs_f;rx_vs_q<=rx_vs_f;rx_de_q<=rx_de_f;rx_rgb_q<=rx_rgb_f;end
 end
 wire recovered_vs;hdmi_vs_recover recover(.clk(rx_clk),.reset_n(rst_n),.de(rx_de_q),.hs(rx_hs_q),.vs_in(rx_vs_q),.vs_out(recovered_vs));
 wire[23:0]rgb;wire de,image_valid,underrun,bist_pass,bist_fail,engine_fault,display_raw;
 wire[31:0]good,rejected,published,displayed,admitted,dropped,raw_pubs,corr_pubs;
 wire[3:0]source_fault;
 wire[511:0]rejected_reason_counts;
 wire cmd_v,cmd_r,cmd_w,rsp_v,rsp_w,source_block_cmd,result_block_cmd;
 wire[27:0]cmd_a;wire[255:0]cmd_data,rsp_data;wire[31:0]cmd_mask;
 wire[2047:0]burst_payload,source_block_payload,result_block_payload;
 video_correct_ddr_continuous_core #(.BIST_ONLY_NATIVE_WDATA(1),.IN_W(SW),.IN_H(SH),.SRC_W(SW),.SRC_H(SH),.OUT_W(OW),.OUT_H(SH),
 .H_SYNC(HS),.H_BACK(HB),.H_ACTIVE(SW),.H_FRONT(HF),.V_SYNC(VS),.V_BACK(VB),.V_ACTIVE(SH),.V_FRONT(VF),
 .PROC_CYCLES_PER_MS(57115),.FIFO_ADDR_BITS(10),.BIST_BEATS(8)) dut(
 .proc_clk(proc_clk),.proc_rst_n(rst_n),.ui_clk(ui_clk),.ui_rst_n(rst_n),.rx_clk(rx_clk),.rx_rst_n(rst_n),.pix_clk(pix_clk),.pix_rst_n(rst_n),
 .hdmi_ready(1'b1),.ddr_ready(rst_n),.memory_fault(engine_fault),.rx_vs(recovered_vs),.rx_de(rx_de_q),.rx_rgb(rx_rgb_q),
 .nearest(1'b0),.force_pattern(1'b0),.raw_requested(!CORRECTED),.display_raw(display_raw),.source_fault_components(source_fault),.raw_publications(raw_pubs),.corrected_publications(corr_pubs),
 .debug_h(),.debug_corners(),.debug_frame_id(),.debug_source_base(),.debug_result_base(),.debug_display_bank(),.debug_display_id(),.data_fifo_peak(),
 .hsync(),.vsync(),.de(de),.rgb(rgb),.image_valid(image_valid),.working(),.frame_error(),.input_wait(),.display_underrun(underrun),
 .selftest_passed(bist_pass),.selftest_failed(bist_fail),.good_frames(good),.rejected_frames(rejected),.diagnostic_reason(),.diagnostic_phase(),
 .preview_valid(1'b0),.preview_rgb(24'd0),.overlay_on(1'b0),.overlay_rgb(24'd0),
 .scan_x(),.scan_y(),.scan_de(),.scan_start(),.scan_reset_n(),.capture_frame_id(),.processing_frame_id(),
 .published_frame_id(published),.displayed_frame_id(displayed),.display_age_ms(),.admitted_frames(admitted),.dropped_frames(dropped),.rejected_reason_counts(rejected_reason_counts),
 .cmd_source_block(source_block_cmd),.cmd_result_block(result_block_cmd),.result_block_data(result_block_payload),.rsp_source_block(source_block_payload),.cmd_burst_data(burst_payload),
 .cmd_valid(cmd_v),.cmd_ready(cmd_r),.cmd_write(cmd_w),.cmd_addr(cmd_a),.cmd_wdata(cmd_data),.cmd_wstrb(cmd_mask),.rsp_valid(rsp_v),.rsp_write(rsp_w),.rsp_rdata(rsp_data));
 wire[27:0]awaddr,araddr;wire[3:0]awid,arid,awlen,arlen;
 wire awap,arap,awvalid,arvalid;wire[255:0]wdata;wire[31:0]wmask;wire[3:0]engine_reason;
 reg rvalid=0,rlast=0;reg[255:0]rdata=0;
 integer ui_tick=0,read_beat=0,read_total=0,read_delay=0,write_index=0,write_total=0,reads=0,writes=0,write_delay=0;
 wire slow_window;
 integer slow_read_commands=0,slow_write_commands=0;
 reg read_pending=0,write_pending=0;reg[27:0]read_base=0,write_base=0;
 wire wready=rst_n&&write_pending&&write_delay==0&&(ui_tick%11!=0),awready=rst_n&&(ui_tick%17>=2),arready=rst_n&&!read_pending&&(ui_tick%7!=0);
 wire wlast=write_pending?(write_index==write_total-1):(awlen==0);
 wire[27:0]physical_addr=write_pending?write_base+write_index*8:awaddr;
 ddr_word_engine_result_burst #(.CAPTURE_BURST_BEATS(8),.READ_AHEAD_ENABLE(1),.SOURCE_PREFETCH_ENABLE(1),.SOURCE_WORDS(WORDS),.SOURCE_BASE1(SRC1),.RESULT_WORDS(OW*SH),.RESULT_BASE0(28'h0200000),.RESULT_BASE1(28'h0400000)) engine(
 .clk(ui_clk),.rst_n(rst_n),.init_done(rst_n),.cmd_valid(cmd_v),.cmd_ready(cmd_r),.cmd_write(cmd_w),.cmd_addr(cmd_a),.cmd_wdata(cmd_data),.cmd_wstrb(cmd_mask),
 .cmd_source_block(source_block_cmd),.cmd_result_block(result_block_cmd),.result_block_data(result_block_payload),.rsp_source_block(source_block_payload),.capture_burst_data(burst_payload),.fault_reason(engine_reason),
 .rsp_valid(rsp_v),.rsp_write(rsp_w),.rsp_rdata(rsp_data),.fault(engine_fault),
 .axi_awaddr(awaddr),.axi_awuser_ap(awap),.axi_awuser_id(awid),.axi_awlen(awlen),.axi_awvalid(awvalid),.axi_awready(awready),
 .axi_wdata(wdata),.axi_wstrb(wmask),.axi_wready(wready),.axi_wusero_id(4'd0),.axi_wusero_last(wlast),
 .axi_araddr(araddr),.axi_aruser_ap(arap),.axi_aruser_id(arid),.axi_arlen(arlen),.axi_arvalid(arvalid),.axi_arready(arready),.axi_rdata(rdata),.axi_rid(4'd0),.axi_rlast(rlast),.axi_rvalid(rvalid));
 reg[255:0]source_ram0[0:WORDS/8-1],source_ram1[0:WORDS/8-1],bist_ram[0:7];
 reg[255:0]result_ram0[0:OW*SH/8-1],result_ram1[0:OW*SH/8-1];
 reg[23:0]source_fixture[0:WORDS-1],expected_fixture[0:OW*SH-1];
 reg[39:0]expected_h[0:8];
 reg[23:0]source_alt[0:WORDS-1],expected_alt[0:OW*SH-1];reg[39:0]expected_h_alt[0:8];
 localparam[95:0]EXPECTED_CORNERS=NATIVE?96'h28a0464e206e5283f224e3c0:96'h01200506c009068029016025;
 localparam[95:0]ALT_CORNERS=NATIVE?{12'd1100,12'd100,12'd1700,12'd160,12'd1650,12'd950,12'd1150,12'd900}:{12'd24,12'd7,12'd112,12'd5,12'd107,12'd38,12'd18,12'd42};
 integer camera_x=0,camera_y=CAMERA_START_LINE,physical_frames=0;integer bank_id[0:1];reg[31:0]seen_generation=0;
 assign slow_window=ADVERSE&&good>=1&&camera_y>=VS+VB&&camera_y<VS+VB+SH/2;
 function[23:0]pattern(input integer g,x,y);
 reg[7:0]v,r,gc,b;begin
 v=70+(g*19+x+3*y)%160;
 r=(g*31+x*3+y)%256;gc=(g*17+x+y*5)%256;b=(g*7+x*7+y*11)%256;
 pattern=CORRECTED?(BAD_FRAME>0&&g==BAD_FRAME?24'hb0b0b0:g%2==0?source_alt[y*SW+x]:source_fixture[y*SW+x]):RGB_PATTERN?{r,gc,b}:{v,v,v};end endfunction
 function[23:0]expected_pixel(input integer g,index);expected_pixel=g%2==0?expected_alt[index]:expected_fixture[index];endfunction
 function[255:0]memory_read(input[27:0]a);
 if(a<WORDS)memory_read=source_ram0[a>>3];
 else if(a>=SRC1&&a<SRC1+WORDS)memory_read=source_ram1[(a-SRC1)>>3];
 else if(a>=BIST&&a<BIST+64)memory_read=bist_ram[(a-BIST)>>3];
 else if(CORRECTED&&a>=28'h0200000&&a<28'h0200000+OW*SH)memory_read=result_ram0[(a-28'h0200000)>>3];
 else if(CORRECTED&&a>=28'h0400000&&a<28'h0400000+OW*SH)memory_read=result_ram1[(a-28'h0400000)>>3];
 else begin memory_read=0;$fatal(1,"RAW unexpected read address %h",a);end
 endfunction
 always @(posedge rx_clk)if(rst_n)begin
 #1; // External source changes away from the falling capture edge.
 if(camera_x==0&&camera_y==0)physical_frames++;
 if(dut.continuous_sources.capture.active&&dut.continuous_sources.capture.generation!=seen_generation)begin
 seen_generation=dut.continuous_sources.capture.generation;
 bank_id[dut.continuous_sources.capture.bank]=seen_generation;
 end
 rx_hs=camera_x<HS;rx_vs=camera_y<VS;
 rx_de=camera_x>=HS+HB&&camera_x<HS+HB+SW&&camera_y>=VS+VB&&camera_y<VS+VB+SH;
 rx_rgb=rx_de?pattern(seen_generation,camera_x-HS-HB,camera_y-VS-VB):0;
 if(camera_x==HT-1)begin camera_x=0;camera_y=camera_y==VT-1?0:camera_y+1;end else camera_x++;
 end
 always @(posedge ui_clk)if(rst_n)begin: memory_model
 integer bank,rel;
 ui_tick++;
 if(write_pending&&write_delay>0)write_delay<=write_delay-1;
 if(cmd_v&&cmd_r&&((cmd_a[2:0]!=0)||(source_block_cmd&&(cmd_w||cmd_a[5:0]!=0||!engine.source_block_safe))||(result_block_cmd&&(!cmd_w||source_block_cmd||cmd_a[5:0]!=0||!engine.result_block_safe))))
 $fatal(1,"bad accepted command addr=%h write=%b source64=%b result64=%b grant=%0d source_safe=%b result_safe=%b",cmd_a,cmd_w,source_block_cmd,result_block_cmd,dut.ui_mux.grant,engine.source_block_safe,engine.result_block_safe);
 if(engine_fault||bist_fail)$fatal(1,"pipeline fault engine=%0d source=%b",engine_reason,source_fault);
 if(arvalid&&arready)begin
 read_pending<=1;read_base<=araddr;read_total<=arlen+1;read_beat<=0;
 read_delay<=slow_window?320:4;if(slow_window)slow_read_commands++;reads++;
 end
 if(awvalid&&awready)begin
 if(write_pending)$fatal(1,"overlap AW");
 write_pending<=1;write_base<=awaddr;write_index<=0;write_total<=awlen+1;write_delay<=slow_window?320:0;if(slow_window)slow_write_commands++;
 end
 if(wready&&(write_pending||(awvalid&&awready)))begin
 if(physical_addr<WORDS||(physical_addr>=SRC1&&physical_addr<SRC1+WORDS))begin
 bank=physical_addr>=SRC1;rel=physical_addr-(bank?SRC1:0);
 if(image_valid&&display_raw&&bank==dut.display_reader.display_bank)$fatal(1,"camera overwrote displayed RAW bank");
 for(integer k=0;k<8;k++)if(wdata[k*32+:32]!=={8'd0,pattern(bank_id[bank],(rel+k)%SW,(rel+k)/SW)})$fatal(1,"source writer pixel mismatch");
 if(bank)source_ram1[rel>>3]<=wdata;else source_ram0[rel>>3]<=wdata;
 writes++;
 end else if(physical_addr>=BIST&&physical_addr<BIST+64)bist_ram[(physical_addr-BIST)>>3]<=wdata;
 else if(CORRECTED&&((physical_addr>=28'h0200000&&physical_addr<28'h0200000+OW*SH)||(physical_addr>=28'h0400000&&physical_addr<28'h0400000+OW*SH)))begin
 bank=physical_addr>=28'h0400000;rel=physical_addr-(bank?28'h0400000:28'h0200000);
 if(image_valid&&!display_raw&&bank==dut.display_reader.display_bank)$fatal(1,"overwrote active corrected bank");
 for(integer k=0;k<8;k++)if(wdata[k*32+:32]!=={8'd0,expected_pixel(dut.processing_frame_id,rel+k)})$fatal(1,"corrected DDR pixel mismatch index=%0d actual=%h expected=%h",rel+k,wdata[k*32+:24],expected_pixel(dut.processing_frame_id,rel+k));
 if(bank)result_ram1[rel>>3]<=wdata;else result_ram0[rel>>3]<=wdata;
 end else $fatal(1,"RAW wrote correction result bank");
 if(wlast)begin write_pending<=0;write_index<=0;end
 else begin write_pending<=1;write_index<=write_pending?write_index+1:1;end
 end
 end
 always @(negedge ui_clk)begin
 rvalid<=0;rlast<=0;
 if(rst_n&&read_pending)begin
 if(read_delay>0)read_delay<=read_delay-1;
 else begin rvalid<=1;rdata<=memory_read(read_base+read_beat*8);rlast<=read_beat==read_total-1;
 read_beat<=read_beat+1;if(read_beat==read_total-1)read_pending<=0;end
 end end
 integer checked=0,scans=0,seen_pub=0,scan_id=0,last_scan_id=0,unique_scans=0;
 time previous_publication=0,maximum_steady_interval=0;
 reg[11:0]px=0,py=0;reg check_scan=0;
 always @(posedge pix_clk)begin: scoreboard
 reg[11:0]nx,ny;reg ns;
 nx=dut.scan_x;ny=dut.scan_y;ns=dut.scan_start;#0.1;
 if(rst_n)begin
 if(ns||dut.display_reader.image_swap_pulse)begin
 check_scan=image_valid;if(ns)scans++;
 if(image_valid)begin
 if(display_raw!==!CORRECTED)$fatal(1,"mode publication mismatch");
 scan_id=dut.debug_display_id;
 if(!CORRECTED&&scan_id!=bank_id[dut.display_reader.display_bank])$fatal(1,"PIX display identity does not match actual source bank");
 if(scan_id<last_scan_id)$fatal(1,"RAW frame ID reversed");
 if(scan_id!=last_scan_id)begin unique_scans++;last_scan_id=scan_id;end
 end end
 if(de&&check_scan)begin
 if(CORRECTED)begin
 if(px<(SW-OW)/2||px>=(SW+OW)/2)begin if(rgb!==0)$fatal(1,"corrected margin stretched");end
 else if(rgb!==expected_pixel(scan_id,py*OW+px-(SW-OW)/2))$fatal(1,"corrected HDMI pixel mismatch x=%0d y=%0d actual=%h",px,py,rgb);
 end else if(rgb!==pattern(scan_id,px,py))begin
 pixel_errors++;if(pixel_errors==1)$display("DISPLAY_FAILURE id=%0d x=%0d y=%0d actual=%h expected=%h time=%0t",scan_id,px,py,rgb,pattern(scan_id,px,py),$time);
 end
 checked++;
 end
 px=nx;py=ny;
 end end
 always @(posedge proc_clk)if(rst_n)begin
 // Path BUSY also covers the writer bridge's reset handshake, before any
 // image exists. A launch or processor activity indicates actual correction.
 if(!CORRECTED&&(dut.start||dut.stream_path.p_busy||corr_pubs!=0))$fatal(1,"RAW invoked B correction");
 if(BAD_FRAME>0&&CORRECTED)begin
 if(rejected>1||rejected_reason_counts[3*32+:32]!=rejected||published==BAD_FRAME||(dut.start&&dut.descriptor_generation==BAD_FRAME))$fatal(1,"bad-marker frame published/processed or wrong reject reason");
 end else if(!ADVERSE&&rejected!=0)$fatal(1,"control unexpectedly rejected frame");
 if(good!=seen_pub)begin
 if(CORRECTED)begin
 for(integer hi=0;hi<9;hi++)if(dut.debug_h[hi*40+:40]!==(published%2==0?expected_h_alt[hi]:expected_h[hi]))$fatal(1,"trace H coefficient mismatch index=%0d",hi);
 $display("CORRECTED_SNAPSHOT id=%0d corners=%h H=%h source_base=%h result_base=%h",dut.debug_frame_id,dut.debug_corners,dut.debug_h,dut.debug_source_base,dut.debug_result_base);
 end
 if(good>2&&$time-previous_publication>maximum_steady_interval)maximum_steady_interval=$time-previous_publication;
 previous_publication=$time;seen_pub=good;$display("PIPELINE_PUBLICATION corrected=%0d id=%0d count=%0d time=%0t",CORRECTED,published,good,$time);
 end
 end
 initial begin
 if(dut.stream_path.processor.FIXED_IDENTITY!=1)$fatal(1,"B_LENS_TRIAL_NOT_CONNECTED");
 bank_id[0]=0;bank_id[1]=0;repeat(8)@(negedge ui_clk);rst_n=1;
 if(!ADVERSE)begin
  wait(unique_scans>=3);@(posedge dut.scan_start);#100;
  if(good<3||pixel_errors!=0||rejected!=0||engine_fault||bist_fail)$fatal(1,"control failed");
  $display("PASS SERVICE_CONTROL physical=%0d good=%0d pix_id=%0d pixels=%0d peak=%0d",physical_frames,good,dut.debug_display_id,checked,dut.data_fifo_peak);$finish;
 end else begin
  wait(good>=1);first_pub_frame=physical_frames;
  wait(physical_frames>=first_pub_frame+6);repeat(10000)@(negedge ui_clk);
  summary();
  if(good==1&&dut.data_fifo_peak==1024&&fifo_full_cycles>0&&(rejected_reason_counts[13*32+:32]>0||close13>0))
   $fatal(1,"SERVICE_STARVATION_REPRO first publication followed by overflow and no new RAW image");
  $fatal(1,"SERVICE_DIAGNOSTIC_NO_TARGET inspect recorded distribution and counters");
 end
 end
 initial begin #250000000;summary();$fatal(1,"service experiment timeout");end

 integer cap_accepts=0,display_accepts=0,cap_wait=0,max_cap_wait=0,last_rejected=0,last_frame=0;
 always @(posedge rx_clk)if(rst_n)begin
  if(good>=1&&!dut.continuous_sources.queue_ready)fifo_full_cycles++;
  if(dut.continuous_sources.close_valid)begin
   if(dut.continuous_sources.close_reason==12)close12++;
   if(dut.continuous_sources.close_reason==13)close13++;
   $display("CAPTURE_CLOSE gen=%0d ok=%b reason=%0d peak=%0d full_cycles=%0d time=%0t",dut.continuous_sources.close_generation,dut.continuous_sources.close_ok,dut.continuous_sources.close_reason,dut.data_fifo_peak,fifo_full_cycles,$time);
  end
 end
 always @(posedge ui_clk)if(rst_n&&bist_pass)begin
  if(dut.cap_v&&!dut.cap_r)begin cap_wait++;if(cap_wait>max_cap_wait)max_cap_wait=cap_wait;end else cap_wait=0;
  if(cmd_v&&cmd_r)begin if(dut.ui_mux.grant==1)cap_accepts++;if(dut.ui_mux.grant==2)display_accepts++;end
 end
 always @(posedge proc_clk)if(rst_n&&rejected!=last_rejected)begin
  last_rejected=rejected;$display("REJECT total=%0d r12=%0d r13=%0d r14=%0d r15=%0d source_fault=%b time=%0t",rejected,rejected_reason_counts[12*32+:32],rejected_reason_counts[13*32+:32],rejected_reason_counts[14*32+:32],rejected_reason_counts[15*32+:32],source_fault,$time);
 end
 task summary;
 begin
  $display("SERVICE_SUMMARY adverse=%0d physical=%0d admitted=%0d dropped=%0d rejected=%0d good=%0d raw=%0d pix_id=%0d actual_raw=%b",ADVERSE,physical_frames,admitted,dropped,rejected,good,raw_pubs,dut.debug_display_id,display_raw);
  $display("SERVICE_CAUSES r12=%0d r13=%0d r14=%0d r15=%0d rx_close12=%0d rx_close13=%0d fifo_peak=%0d fifo_full_cycles=%0d pixel_errors=%0d underrun=%b engine_fault=%b source_fault=%b",rejected_reason_counts[12*32+:32],rejected_reason_counts[13*32+:32],rejected_reason_counts[14*32+:32],rejected_reason_counts[15*32+:32],close12,close13,dut.data_fifo_peak,fifo_full_cycles,pixel_errors,underrun,engine_fault,source_fault);
  $display("SERVICE_TIMING slow_reads=%0d slow_writes=%0d read_cmds=%0d write_beats=%0d cap_accepts=%0d display_accepts=%0d max_cap_wait_ui=%0d",slow_read_commands,slow_write_commands,reads,writes,cap_accepts,display_accepts,max_cap_wait);
 end endtask
endmodule
