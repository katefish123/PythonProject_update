`timescale 1ns/1ps
module tb_raw_corrected #(
 parameter NATIVE=0,LATE=0
);
 localparam SW=NATIVE?1920:128,OW=NATIVE?768:64,SH=NATIVE?1080:8;
 localparam HS=NATIVE?44:4,HB=NATIVE?148:124,HA=SW,HF=NATIVE?88:16;
 localparam VS=2,VB=NATIVE?39:8,VA=SH,VF=3;
 localparam[27:0]S0=0,S1=28'h0800000,C0=28'h0200000,C1=28'h0400000;
 reg ui_clk=0,pix_clk=0,rst_n=0;
 always #4 ui_clk=~ui_clk;
 always #(NATIVE?3.3670035:5)pix_clk=~pix_clk;
 reg pub_toggle=0,pub_bank=0,pub_raw=0;
 wire ack,cmd_valid,cmd_raw,hs,vs,de,image_valid,underrun,busy,display_raw,swap_pulse,scan_pulse;
 wire[27:0]cmd_addr;wire[23:0]rgb;wire[11:0]sx,sy;wire sd,ss,srn;
 reg cmd_ready=0,rsp_valid=0;reg[2047:0]rsp_block=0;
`ifdef RED_BASELINE
 assign cmd_raw=0;assign display_raw=0;assign swap_pulse=0;assign scan_pulse=ss;
 ddr_result_display_block64 #(.OUT_W(OW),.OUT_H(SH),.SCALE(1),.BASE0(C0),.BASE1(C1),
`else
 ddr_result_display_raw_corrected #(.OUT_W(OW),.OUT_H(SH),.SRC_W(SW),.SRC_H(SH),.SCALE(1),
 .BASE0(C0),.BASE1(C1),.SOURCE_BASE0(S0),.SOURCE_BASE1(S1),
`endif
 .H_SYNC(HS),.H_BACK(HB),.H_ACTIVE(HA),.H_FRONT(HF),.V_SYNC(VS),.V_BACK(VB),.V_ACTIVE(VA),.V_FRONT(VF)) dut(
 .ui_clk(ui_clk),.ui_rst_n(rst_n),.pix_clk(pix_clk),.pix_rst_n(rst_n),
 .publish_toggle(pub_toggle),.publish_bank(pub_bank),.ack_toggle(ack),
`ifndef RED_BASELINE
 .publish_raw(pub_raw),.display_raw(display_raw),.cmd_source_block(cmd_raw),
 .scan_frame_pulse(scan_pulse),.image_swap_pulse(swap_pulse),
`endif
 .preview_valid(1'b0),.preview_rgb(24'd0),.overlay_on(1'b0),.overlay_rgb(24'd0),
 .scan_x(sx),.scan_y(sy),.scan_de(sd),.scan_start(ss),.scan_reset_n(srn),
 .force_pattern(1'b0),.capture_guard(1'b0),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_addr(cmd_addr),
 .rsp_valid(rsp_valid),.rsp_rdata(rsp_block[255:0]),.rsp_block(rsp_block),
 .hsync(hs),.vsync(vs),.de(de),.rgb(rgb),.image_valid(image_valid),.underrun(underrun),.prefetch_busy(busy));

 integer seq_raw[0:1],seq_corr[0:1];
 function automatic[23:0]pattern(input bit raw_mode,input integer seq,x,y);
 reg[7:0]r,g,b;
 begin
  if(!raw_mode&&(x==0||x>=OW-2))pattern=0;
  else begin
   r=(x+seq*17)&255;g=(y+seq*29)&255;b=(x/256+y/256*7+seq*43)&255;
   pattern={r,g,b};
  end
 end endfunction
 integer ui_tick=0,commands=0,responses=0,delay_left=0;
 integer rel,width,seq_hold,lane,row,col;reg pending=0,hold_responses=0;
 reg[27:0]pending_addr,stall_addr;reg pending_raw,pending_bank,stall_raw,stalled=0;
 reg[2047:0]pending_data;
 integer stalled_cycles=0,first_pixels=0,last_pixels=0,checked=0,black_border=0,swaps=0,scans=0;
 always @(negedge ui_clk)begin
  if(!rst_n)cmd_ready=0;else cmd_ready=(ui_tick%11)<8&&!pending;
 end
 always @(posedge ui_clk)begin
  if(!rst_n)begin pending<=0;rsp_valid<=0;stalled<=0;delay_left<=0;ui_tick<=0;end
  else begin
   ui_tick<=ui_tick+1;rsp_valid<=0;
   if(stalled&&(!cmd_valid||cmd_addr!==stall_addr||cmd_raw!==stall_raw))$fatal(1,"command payload/valid changed under backpressure");
   stalled<=cmd_valid&&!cmd_ready;
   if(cmd_valid&&!cmd_ready)begin stall_addr<=cmd_addr;stall_raw<=cmd_raw;stalled_cycles=stalled_cycles+1;end
   if(cmd_valid&&cmd_ready)begin
    if(pending)$fatal(1,"multiple display reads outstanding");
    pending_raw=cmd_raw;pending_bank=0;
    if(cmd_raw)begin
     if(cmd_addr>=S1&&cmd_addr<S1+SW*SH)begin rel=cmd_addr-S1;pending_bank=1;end
     else if(cmd_addr>=S0&&cmd_addr<S0+SW*SH)rel=cmd_addr-S0;
     else $fatal(1,"RAW address is not in a source bank addr=%h",cmd_addr);
     width=SW;seq_hold=seq_raw[pending_bank];
    end else begin
     if(cmd_addr>=C1&&cmd_addr<C1+OW*SH)begin rel=cmd_addr-C1;pending_bank=1;end
     else if(cmd_addr>=C0&&cmd_addr<C0+OW*SH)rel=cmd_addr-C0;
     else $fatal(1,"CORRECTED address is not in a result bank addr=%h",cmd_addr);
     width=OW;seq_hold=seq_corr[pending_bank];
    end
    if(cmd_addr[5:0]!=0||rel%width>width-64)$fatal(1,"unaligned/cross-row block");
    row=rel/width;col=rel%width;
    for(lane=0;lane<64;lane=lane+1)pending_data[lane*32+:32]={8'd0,pattern(cmd_raw,seq_hold,col+lane,row)};
    pending_addr<=cmd_addr;pending<=1;delay_left<=2+(commands%7);commands=commands+1;
   end
   if(pending&&!hold_responses)begin
    if(delay_left==0)begin rsp_block<=pending_data;rsp_valid<=1;pending<=0;responses=responses+1;end
    else delay_left<=delay_left-1;
   end
  end
 end

 bit strict_pixels=0,checking=0;integer active_seq=0;bit active_bank=0,active_raw=0;
 reg[11:0]px=0,py=0;reg pde=0;bit pstart=0;reg prev_mode=0;
 integer cx,expected_width;reg[23:0]expected;
 always @(posedge pix_clk)begin: pixel_score
  reg[11:0]now_x,now_y;reg now_de,now_start;
  now_x=sx;now_y=sy;now_de=sd;now_start=ss;
  #0.1;
  if(!rst_n||!srn)begin pde=0;prev_mode=display_raw;end
  else begin
   if(display_raw!=prev_mode&&!now_start)$fatal(1,"mode changed outside scan_start");
   prev_mode=display_raw;
   if(scan_pulse)scans=scans+1;
   if(swap_pulse)begin
    swaps=swaps+1;
    if(!now_start)$fatal(1,"swap pulse outside scan_start");
    if(display_raw!==pub_raw)$fatal(1,"RAW_MODE_PUBLICATION_REQUIRED actual=%b expected=%b",display_raw,pub_raw);
   end
   if(de&&checking)begin
    expected_width=active_raw?SW:OW;
    cx=px-(HA-expected_width)/2;
    expected=(cx<0||cx>=expected_width)?24'd0:pattern(active_raw,active_seq,cx,py);
    if(strict_pixels&&rgb!==expected)$fatal(1,"pixel mismatch raw=%0d seq=%0d x=%0d y=%0d got=%h expected=%h",active_raw,active_seq,px,py,rgb,expected);
    if(!strict_pixels&&rgb!==0&&rgb!==expected)$fatal(1,"late old-mode pixel leaked raw=%0d x=%0d y=%0d got=%h expected=%h",active_raw,px,py,rgb,expected);
    if(strict_pixels)begin
     checked=checked+1;
     if(cx==0)first_pixels=first_pixels+1;
     if(cx==expected_width-1)last_pixels=last_pixels+1;
     if(cx<0||cx>=expected_width)begin black_border=black_border+1;if(rgb!==0)$fatal(1,"stretched corrected window/black border");end
    end
   end
   px=now_x;py=now_y;pde=now_de;pstart=now_start;
  end
 end
 task automatic publish(input bit raw_mode,bank_mode,input integer sequence_number);
 begin
  wait(ack==pub_toggle);@(negedge pix_clk);
  if(raw_mode)seq_raw[bank_mode]=sequence_number;else seq_corr[bank_mode]=sequence_number;
  pub_raw=raw_mode;pub_bank=bank_mode;pub_toggle=~pub_toggle;
  wait(ack==pub_toggle);#1;
  if(display_raw!==raw_mode)$fatal(1,"RAW_MODE_PUBLICATION_REQUIRED actual=%b expected=%b",display_raw,raw_mode);
  active_raw=raw_mode;active_bank=bank_mode;active_seq=sequence_number;
 end endtask
 task automatic whole_scan(input bit strict_mode);
 begin
  @(posedge ss);@(negedge pix_clk);strict_pixels=strict_mode;checking=1;
  @(posedge ss);@(negedge pix_clk);checking=0;strict_pixels=0;
 end endtask
 initial begin
  seq_raw[0]=0;seq_raw[1]=0;seq_corr[0]=0;seq_corr[1]=0;
  repeat(6)@(negedge pix_clk);rst_n=1;
  publish(1,0,1);whole_scan(1);
  if(LATE)begin
   // Keep one old RAW transaction outstanding across a CORRECTED publication.
   hold_responses=1;wait(pending);publish(0,1,2);checking=1;strict_pixels=0;
   repeat(31)@(negedge pix_clk);hold_responses=0;
   whole_scan(0);whole_scan(1);
   // A common hard reset flushes an accepted read and every mailbox endpoint.
   checking=0;hold_responses=1;wait(pending);@(negedge pix_clk);
   rst_n=0;pub_toggle=0;pub_bank=0;pub_raw=0;hold_responses=0;
   repeat(5)@(negedge pix_clk);
   if(cmd_valid||image_valid||display_raw||ack)$fatal(1,"in-flight common reset failed");
   rst_n=1;publish(1,1,9);whole_scan(1);
  end else begin
   publish(1,1,2);whole_scan(1);
   publish(0,0,3);whole_scan(1);
   publish(0,1,4);whole_scan(1);
   publish(1,0,5);whole_scan(1);
  end
  if(first_pixels==0||last_pixels==0||checked==0||stalled_cycles==0)$fatal(1,"insufficient pixel/stall coverage");
  if(!LATE&&black_border==0)$fatal(1,"corrected black border not scored");
  checking=0;@(negedge pix_clk);rst_n=0;repeat(4)@(negedge pix_clk);
  if(cmd_valid||image_valid||display_raw||ack)$fatal(1,"shared reset did not flush mode/requests");
  $display("PASS RAW_CORRECTED native=%0d late=%0d checked=%0d commands=%0d responses=%0d stalls=%0d first=%0d last=%0d borders=%0d swaps=%0d scans=%0d",NATIVE,LATE,checked,commands,responses,stalled_cycles,first_pixels,last_pixels,black_border,swaps,scans);$finish;
 end
 initial begin #(NATIVE?350000000:10000000);$fatal(1,"test timeout native=%0d late=%0d",NATIVE,LATE);end
endmodule
