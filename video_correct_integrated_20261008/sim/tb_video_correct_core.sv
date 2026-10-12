`timescale 1ns/1ps
module tb_video_correct_core;
 reg proc_clk=0,rx_clk=0,pix_clk=0;
 always #5 proc_clk=~proc_clk;
 always #3.5 rx_clk=~rx_clk;
 always #6.5 pix_clk=~pix_clk;
 reg proc_rst_n=0,rx_rst_n=0,pix_rst_n=0;
 reg enabled=0,rx_vs=0,rx_de=0,nearest=0,force_pattern=0;
 reg [23:0] rx_rgb=0;
 wire hsync,vsync,de,image_valid,working,frame_error,input_wait;
 wire [23:0] rgb;
 wire [31:0] good_frames,rejected_frames;
 localparam IN_W=64,IN_H=48,OUT_W=32,OUT_H=24;
 reg [23:0] source0[0:IN_W*IN_H-1],source1[0:IN_W*IN_H-1],source_bad[0:IN_W*IN_H-1];
 reg [23:0] expected0[0:OUT_W*OUT_H-1],expected1[0:OUT_W*OUT_H-1];
 integer writes=0,source_writes=0,prev_req=0,good_before,reject_before,old_bank,old_publish;
 integer x,y,i,pixels,scene;
 reg test_passed=0;
 video_correct_core #(.IN_W(IN_W),.IN_H(IN_H),.DECIMATE(1),.SRC_W(IN_W),.SRC_H(IN_H),
  .OUT_W(OUT_W),.OUT_H(OUT_H),.SCALE(1),
  .H_SYNC(1),.H_BACK(1),.H_ACTIVE(OUT_W),.H_FRONT(1),
  .V_SYNC(1),.V_BACK(1),.V_ACTIVE(OUT_H),.V_FRONT(1),
  .CAPTURE_TIMEOUT(10000),.RETRY_CYCLES(20),.MIN_PIXELS(16),.MAX_PIXELS(4096),.MAX_SPAN(128)) dut(
  .proc_clk(proc_clk),.proc_rst_n(proc_rst_n),.rx_clk(rx_clk),.rx_rst_n(rx_rst_n),
  .pix_clk(pix_clk),.pix_rst_n(pix_rst_n),.enabled(enabled),.rx_vs(rx_vs),.rx_de(rx_de),.rx_rgb(rx_rgb),
  .nearest(nearest),.force_pattern(force_pattern),.hsync(hsync),.vsync(vsync),.de(de),.rgb(rgb),
  .image_valid(image_valid),.working(working),.frame_error(frame_error),.input_wait(input_wait),
  .good_frames(good_frames),.rejected_frames(rejected_frames));
 always @(posedge proc_clk) if(proc_rst_n)begin
  if(dut.write_valid)begin
   writes=writes+1;
   if(dut.write_bank===dut.display_store.display_bank)
    $fatal(1,"write attempted on active display bank %0d",dut.write_bank);
  end
 end
 always @(posedge rx_clk) if(rx_rst_n&&working&&dut.source_store.write_pixel)
  $fatal(1,"snapshot source overwritten while frame_processor is working");
 task pulse_vs;
  begin
   @(negedge rx_clk);rx_de=0;rx_vs=1;
   @(negedge rx_clk);rx_vs=0;repeat(2)@(negedge rx_clk);
  end
 endtask
 task send_frame(input integer which,input integer short_frame);
  integer limit_y;
  begin
   pulse_vs();
   limit_y=short_frame?10:IN_H;
   for(y=0;y<limit_y;y=y+1)begin
    @(negedge rx_clk);rx_de=1;
    for(x=0;x<IN_W;x=x+1)begin
     if(which==0)rx_rgb=source0[y*IN_W+x];
     else if(which==1)rx_rgb=source1[y*IN_W+x];
     else if(which==2)rx_rgb=source_bad[y*IN_W+x];
     else rx_rgb=24'd0;
     @(negedge rx_clk);
    end
    rx_de=0;rx_rgb=0;repeat(2)@(negedge rx_clk);
   end
   if(short_frame)begin
    // The next frame boundary tells capture that the pending frame ended early.
    pulse_vs();
   end
   rx_de=0;rx_rgb=0;
  end
 endtask
 task wait_request;
  begin
   wait(dut.capture_request!=prev_req);
   prev_req=dut.capture_request;
   repeat(6)@(negedge rx_clk);
  end
 endtask
 task compare_source(input integer which);
  integer k;
  begin
   for(k=0;k<IN_W*IN_H;k=k+1)begin
    if(dut.source_store.memory[k] !== ((which==0)?source0[k]:source1[k]))
     $fatal(1,"captured source changed/mismatch at %0d got=%h expected=%h",k,dut.source_store.memory[k],(which==0)?source0[k]:source1[k]);
   end
  end
 endtask
 task scan_output(input integer which);
  integer xx,yy,k;
  begin
   k=0;
   // Output sync is registered. Anchor to its frame edge and compare every active pixel.
   @(posedge vsync);#1;
   for(yy=0;yy<27;yy=yy+1)begin
    for(xx=0;xx<35;xx=xx+1)begin
     if(xx!=0||yy!=0)begin @(posedge pix_clk);#1;end
     if(de)begin
      if(k>=OUT_W*OUT_H)$fatal(1,"too many output pixels");
      if(which==0 && rgb!==expected0[k])$fatal(1,"scene0 display mismatch pixel=%0d got=%h expected=%h",k,rgb,expected0[k]);
      if(which==1 && rgb!==expected1[k])$fatal(1,"scene1 display mismatch pixel=%0d got=%h expected=%h",k,rgb,expected1[k]);
      k=k+1;
     end else if(rgb!==24'd0)$fatal(1,"RGB asserted outside DE: %h",rgb);
    end
   end
   if(k!=OUT_W*OUT_H)$fatal(1,"output DE pixels=%0d expected=%0d",k,OUT_W*OUT_H);
  end
 endtask
 task process_scene(input integer which,input integer nn);
  begin
   good_before=good_frames;old_publish=dut.publish_toggle;nearest=nn;wait_request();
   send_frame(which,0);
   wait(working);
   compare_source(which);
   // A different frame arriving during processing must not overwrite the locked snapshot.
   send_frame(3,0);
   compare_source(which);
   wait(good_frames==good_before+1);
   wait(dut.publish_toggle!=old_publish);
   wait(dut.display_ack==dut.publish_toggle);#1;
   if(!image_valid||frame_error)$fatal(1,"successful processing did not publish cleanly");
   scan_output(which);
   $display("CORE_SCENE_PASS scene=%0d pixels=%0d good_frames=%0d",which,OUT_W*OUT_H,good_frames);
  end
 endtask
 task check_rejected(input integer which,input integer short_frame);
  begin
   reject_before=rejected_frames;old_bank=dut.display_store.display_bank;old_publish=dut.publish_toggle;source_writes=writes;
   wait_request();send_frame(which,short_frame);
   wait(rejected_frames==reject_before+1);repeat(4)@(negedge proc_clk);
   if(dut.publish_toggle!=old_publish || dut.display_store.display_bank!=old_bank)
    $fatal(1,"rejected frame changed display publication");
   if(writes!=source_writes)$fatal(1,"rejected frame wrote %0d destination pixels",writes-source_writes);
   if(!frame_error)$fatal(1,"rejected frame did not set frame_error");
   scan_output(1);
   $display("CORE_REJECT_PASS input=%0d short=%0d rejected=%0d held_bank=%0d",which,short_frame,rejected_frames,old_bank);
  end
 endtask
 initial begin
  $readmemh("vendor/b/vectors/source0.hex",source0);
  $readmemh("vendor/b/vectors/source1.hex",source1);
  $readmemh("vendor/b/vectors/source2.hex",source_bad);
  $readmemh("vendor/b/vectors/expected0.hex",expected0);
  $readmemh("vendor/b/vectors/expected1.hex",expected1);
  repeat(5)@(negedge proc_clk);proc_rst_n=1;rx_rst_n=1;pix_rst_n=1;enabled=1;
  process_scene(0,0);
  process_scene(1,1);
  // Invalid geometry (source2) and then a short capture both retain scene1.
  check_rejected(2,0);
  check_rejected(3,1);
  // Reset every domain together and prove a clean capture/publication recovers.
  enabled=0;proc_rst_n=0;rx_rst_n=0;pix_rst_n=0;
  repeat(5)@(negedge proc_clk);proc_rst_n=1;rx_rst_n=1;pix_rst_n=1;enabled=1;prev_req=0;
  process_scene(0,0);
  test_passed=1;
  $display("VIDEO_CORRECT_CORE_PASS async_clocks=3 recovery=1 active_bank_protection=1");
  $finish;
 end
 initial begin #50000000;$fatal(1,"video_correct_core timeout");end
endmodule


