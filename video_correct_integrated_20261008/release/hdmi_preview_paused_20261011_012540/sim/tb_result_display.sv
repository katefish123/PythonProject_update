`timescale 1ns/1ps
module tb_result_display;
 reg wr_clk=0,pix_clk=0,rst_n=0;
 always #3.5 wr_clk=~wr_clk;
 always #5.5 pix_clk=~pix_clk;
 reg wr_en=0,wr_bank=0;
 reg [23:0] wr_addr=0,wr_rgb=0;
 reg publish_toggle=0,publish_bank=0,force_pattern=0;
 wire ack_toggle,hsync,vsync,de,image_valid;
 wire [23:0] rgb;
 integer checks=0;
 reg passed=0;
 result_display #(.OUT_W(2),.OUT_H(2),.SCALE(1),
  .H_SYNC(1),.H_BACK(1),.H_ACTIVE(4),.H_FRONT(1),
  .V_SYNC(1),.V_BACK(1),.V_ACTIVE(4),.V_FRONT(1)) dut(
  .wr_clk(wr_clk),.wr_en(wr_en),.wr_bank(wr_bank),.wr_addr(wr_addr),.wr_rgb(wr_rgb),
  .pix_clk(pix_clk),.rst_n(rst_n),.publish_toggle(publish_toggle),.publish_bank(publish_bank),
  .force_pattern(force_pattern),.ack_toggle(ack_toggle),.hsync(hsync),.vsync(vsync),.de(de),
  .rgb(rgb),.image_valid(image_valid));
 function [23:0] val(input integer b,input integer a);
  val=(b==0)?(24'h110000+a):(24'h220000+a);
 endfunction
 task write_bank(input integer b);
  integer a;
  begin
   for(a=0;a<4;a=a+1)begin
    @(negedge wr_clk);wr_bank=b;wr_addr=a;wr_rgb=val(b,a);wr_en=1;
   end
   @(negedge wr_clk);wr_en=0;
  end
 endtask
 task scan_frame(input integer expected_bank,input integer request_new);
  integer hh,vv,pixels;
  begin
   // Each scan covers one complete frame, anchored to registered VSYNC.
   pixels=0;
   @(posedge vsync);#1;
   for(vv=0;vv<7;vv=vv+1)begin
    for(hh=0;hh<7;hh=hh+1)begin
     if(vv!=0||hh!=0)begin @(posedge pix_clk);#1;end
     if(de&&rgb!=24'd0)begin
      if(pixels>=4 || rgb!==val(expected_bank,pixels))
       $fatal(1,"frame tear/mismatch bank=%0d pixel=%0d got=%h expected=%h",expected_bank,pixels,rgb,val(expected_bank,pixels));
      pixels=pixels+1;checks=checks+1;
     end else if(!de&&rgb!==24'd0)$fatal(1,"RGB outside DE: %h",rgb);
     if(request_new&&vv==3&&hh==3)publish(1);
    end
   end
   if(pixels!=4)$fatal(1,"frame pixel count=%0d expected=4",pixels);
  end
 endtask
 task publish(input integer b);
  begin
   @(negedge wr_clk);publish_bank=b;publish_toggle=~publish_toggle;
  end
 endtask
 initial begin
  repeat(4)@(negedge pix_clk);rst_n=1;
  write_bank(0);publish(0);
  wait(ack_toggle==publish_toggle);#1;
  if(!image_valid)$fatal(1,"image_valid did not assert after publish");
  scan_frame(0,0);
  if(checks!=4)$fatal(1,"first frame did not contain all 4 pixels");
  // Update the inactive bank, then request it during scanning. The active frame stays intact.
  write_bank(1);
  scan_frame(0,1);
  wait(ack_toggle==publish_toggle);#1;
  checks=0;scan_frame(1,0);
  if(checks!=4)$fatal(1,"second frame did not contain all 4 pixels");
  $display("RESULT_DISPLAY_FRAME_ATOMIC_PASS pixels_per_frame=4 async_clocks=1");
  passed=1;$finish;
 end
 initial begin #200000;$fatal(1,"result display timeout");end
endmodule









