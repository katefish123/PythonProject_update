`timescale 1ns/1ps
module tb_preview_write_pipeline #(parameter D=1);
 localparam W=32,H=16;
 reg rx_clk=0,pix_clk=0;always #3.367 rx_clk=~rx_clk;always #5 pix_clk=~pix_clk;
 reg rx_rst_n=0,pix_rst_n=0,rx_vs=0,rx_de=0;reg[23:0]rx_rgb=0;
 reg scan_de=0,scan_start=0;reg[11:0]scan_x=0,scan_y=0;
 wire[23:0]rgb;wire valid;wire[12:0]observed_width,observed_height;wire bad_frame;
 rx_preview_stream #(.IN_W(W),.IN_H(H),.DECIMATE(D)) dut(.*);
 integer checks=0,publications=0;reg last_toggle=0;
 function[23:0]pixel(input integer g,x,y);
  pixel={8'(g*37+x*13+y*7),8'(g*19+x*3+y*23),8'(g*11+x*29+y*5)};
 endfunction
 task rtick;begin @(posedge rx_clk);#0.2;end endtask
 task ptick;begin @(posedge pix_clk);#0.2;end endtask
 always @(posedge rx_clk)if(rx_rst_n&&pix_rst_n)begin
  if(dut.pub_toggle!=last_toggle)publications=publications+1;
  last_toggle=dut.pub_toggle;
 end else last_toggle=0;
 task settle;begin repeat(10)rtick();repeat(6)ptick();end endtask
 task frame(input integer g,input reg admit,input reg good);
  reg previous;integer line_width;begin
   @(negedge rx_clk);rx_vs=1;rx_de=0;rtick();
   @(negedge rx_clk);rx_vs=0;rtick();
   if(dut.active!==admit)$fatal(1,"preview admission/ACK hold mismatch gen=%0d",g);
   for(integer y=0;y<H;y=y+1)begin
    line_width=(!good&&y==H-1)?W-1:W;
    for(integer x=0;x<line_width;x=x+1)begin @(negedge rx_clk);rx_de=1;rx_rgb=pixel(g,x,y);rtick();end
    @(negedge rx_clk);rx_de=0;rtick();
   end
   previous=dut.pub_toggle;
   @(negedge rx_clk);rx_vs=1;rtick();
   if(admit&&good&&dut.pub_toggle!==previous)$fatal(1,"PUBLISH_AFTER_WRITE_DRAIN_REQUIRED publication must follow close and write retirement");
   @(negedge rx_clk);rx_vs=0;rtick();
   if(admit&&good)begin
    if(dut.pub_toggle===previous||bad_frame||observed_width!=W||observed_height!=H)$fatal(1,"complete frame not published after drain");
   end else if(dut.pub_toggle!==previous)$fatal(1,"bad/blocked frame changed publication");
   if(admit&&!good&&!bad_frame)$fatal(1,"bad frame was not flagged");
  end
 endtask
 task swap;
  begin
   repeat(7)ptick();@(negedge pix_clk);scan_de=0;scan_start=1;ptick();
   if(!valid||dut.display_bank!==dut.pub_toggle)$fatal(1,"scan_start failed to swap complete published bank");
   @(negedge pix_clk);scan_start=0;settle();
  end
 endtask
 task scan(input integer g);
  reg[23:0]want;begin
   for(integer y=0;y<H;y=y+1)begin
    @(negedge pix_clk);scan_de=0;scan_y=y;scan_x=0;ptick();
    for(integer x=0;x<W;x=x+1)begin
     @(negedge pix_clk);scan_de=1;scan_x=x;
     want=pixel(g,(x/D)*D,(y/D)*D);ptick();
     if(!valid||rgb!==want)$fatal(1,"preview pixel mismatch D=%0d gen=%0d x=%0d y=%0d got=%h expected=%h",D,g,x,y,rgb,want);
     checks=checks+1;
    end
   end
   @(negedge pix_clk);scan_de=0;ptick();
  end
 endtask
 task reset_both;
  begin
   @(negedge rx_clk);rx_rst_n=0;pix_rst_n=0;rx_de=0;rx_vs=0;scan_de=0;scan_start=0;
   repeat(4)rtick();rx_rst_n=1;pix_rst_n=1;settle();
   if(valid||dut.pub_toggle||dut.ack_toggle||dut.active)$fatal(1,"reset did not flush preview identity");
  end
 endtask
 initial begin
  reset_both();frame(1,1,1);settle();
  if(valid)$fatal(1,"preview visible before display boundary ACK");
  frame(99,0,1);settle();
  if(valid)$fatal(1,"unacknowledged bank was replaced");
  swap();scan(1);
  fork frame(2,1,1);scan(1);join
  settle();scan(1);swap();scan(2);
  frame(3,1,0);settle();scan(2);
  frame(4,1,1);swap();scan(4);
  // Capture one sampled pixel, then reset before the delayed write edge.
  @(negedge rx_clk);rx_vs=1;rtick();@(negedge rx_clk);rx_vs=0;rtick();
  @(negedge rx_clk);rx_de=1;rx_rgb=24'h123457;rtick();
  reset_both();frame(5,1,1);
  // Either domain's reset must flush a pending publication and local write.
  @(negedge pix_clk);pix_rst_n=0;repeat(4)ptick();
  if(valid||dut.pub_toggle||dut.active)$fatal(1,"pixel-only reset retained preview ownership");
  pix_rst_n=1;settle();frame(6,1,1);swap();scan(6);
  $display("PASS PREVIEW_WRITE_PIPELINE D=%0d checks=%0d publications=%0d all_rgb24=1 last_sample=1 ACK_backpressure=1 cross_frame=1 invalid_frame=1 reset=1",D,checks,publications);$finish;
 end
 initial begin #300000;$fatal(1,"preview write pipeline timeout D=%0d",D);end
endmodule
