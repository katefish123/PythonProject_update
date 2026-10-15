`timescale 1ns/1ps
module tb_preview_raster;
 reg rc=0,pc=0,rst=0,vs=0,rxde=0;reg[23:0]input_rgb=0;
 always #3 rc=~rc;always #5 pc=~pc;
 wire[11:0]x,y;wire sd,ss,srst,pv,ack,hs,ovs,de,iv,un,cv;wire[23:0]prgb,rgb;wire[27:0]ca;
 ddr_result_display #(.OUT_W(8),.OUT_H(8),.SCALE(1),.H_SYNC(2),.H_BACK(2),.H_ACTIVE(32),.H_FRONT(2),.V_SYNC(1),.V_BACK(1),.V_ACTIVE(16),.V_FRONT(1)) display(
 .capture_guard(1'b0),.prefetch_busy(),.ui_clk(pc),.ui_rst_n(rst),.pix_clk(pc),.pix_rst_n(rst),.publish_toggle(1'b0),.publish_bank(1'b0),.ack_toggle(ack),.force_pattern(1'b0),
 .cmd_valid(cv),.cmd_ready(1'b1),.cmd_addr(ca),.rsp_valid(1'b0),.rsp_rdata(256'd0),.hsync(hs),.vsync(ovs),.de(de),.rgb(rgb),.image_valid(iv),.underrun(un),
 .preview_valid(pv),.preview_rgb(prgb),.overlay_on(1'b0),.overlay_rgb(24'd0),.scan_x(x),.scan_y(y),.scan_de(sd),.scan_start(ss),.scan_reset_n(srst));
 rx_preview_stream #(.IN_W(32),.IN_H(16),.DECIMATE(2)) preview(
 .rx_clk(rc),.rx_rst_n(rst),.rx_vs(vs),.rx_de(rxde),.rx_rgb(input_rgb),.pix_clk(pc),.pix_rst_n(srst),.scan_x(x),.scan_y(y),.scan_de(sd),.scan_start(ss),.rgb(prgb),.valid(pv),.observed_width(),.observed_height(),.bad_frame());
 function[23:0]pattern(input integer xx,input integer yy);pattern={(8'(yy*13+xx)),8'(xx*7),8'(yy*11)};endfunction
 task pulse;begin @(negedge rc);vs=1;@(negedge rc);vs=0;repeat(4)@(negedge rc);end endtask
 integer checks=0;reg[23:0]want;reg[23:0]display_want=0;reg display_check=0;
 always @(posedge pc)begin
  // Registered preview data is consumed by the display on the next edge.
  if(sd&&pv)begin
   want=pattern((x/2)*2,(y/2)*2);
   #1;if(prgb!==want)$fatal(1,"raster preview mismatch x=%0d y=%0d got=%h want=%h",x,y,prgb,want);
   checks=checks+1;
  end
 end
 initial begin
  #30;rst=1;repeat(20)@(negedge rc);pulse;
  for(integer j=0;j<16;j=j+1)begin
   for(integer i=0;i<32;i=i+1)begin @(negedge rc);rxde=1;input_rgb=pattern(i,j);end
   @(negedge rc);rxde=0;repeat(3)@(negedge rc);
  end
  pulse;wait(pv);repeat(3500)@(negedge pc);
  if(checks<1536)$fatal(1,"insufficient raster checks");
  $display("PASS preview registered row raster checks=%0d",checks);$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
