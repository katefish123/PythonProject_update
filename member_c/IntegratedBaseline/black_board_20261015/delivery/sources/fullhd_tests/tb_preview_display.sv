`timescale 1ns/1ps
module tb_preview_display;
 reg rc=0,pc=0,rst=0,vs=0,rxde=0;reg[23:0]input_rgb=24'h234567;always #3 rc=~rc;always #5 pc=~pc;
 wire[11:0]x,y;wire sd,ss,srst,pv,ack,hs,ovs,de,iv,un,cv;wire[23:0]prgb,rgb;wire[27:0]ca;
 ddr_result_display #(.OUT_W(8),.OUT_H(8),.SCALE(1),.H_SYNC(2),.H_BACK(2),.H_ACTIVE(32),.H_FRONT(2),.V_SYNC(1),.V_BACK(1),.V_ACTIVE(16),.V_FRONT(1)) display(.capture_guard(1'b0),.prefetch_busy(),
 .ui_clk(pc),.ui_rst_n(rst),.pix_clk(pc),.pix_rst_n(rst),.publish_toggle(1'b0),.publish_bank(1'b0),.ack_toggle(ack),.force_pattern(1'b0),
 .cmd_valid(cv),.cmd_ready(1'b1),.cmd_addr(ca),.rsp_valid(1'b0),.rsp_rdata(256'd0),.hsync(hs),.vsync(ovs),.de(de),.rgb(rgb),.image_valid(iv),.underrun(un),
 .preview_valid(pv),.preview_rgb(prgb),.overlay_on(1'b0),.overlay_rgb(24'd0),.scan_x(x),.scan_y(y),.scan_de(sd),.scan_start(ss),.scan_reset_n(srst));
 rx_preview #(.IN_W(32),.IN_H(16),.DECIMATE(2)) preview(.rx_clk(rc),.rx_rst_n(rst),.rx_vs(vs),.rx_de(rxde),.rx_rgb(input_rgb),
 .pix_clk(pc),.pix_rst_n(srst),.scan_x(x),.scan_y(y),.scan_de(sd),.scan_start(ss),.rgb(prgb),.valid(pv),.observed_width(),.observed_height(),.bad_frame());
 task pulse;begin @(negedge rc);vs=1;@(negedge rc);vs=0;repeat(4)@(negedge rc);end endtask
 integer checks=0;reg test_passed=0;
 initial begin #30;rst=1;repeat(20)@(negedge rc);pulse;
 for(integer j=0;j<16;j=j+1)begin for(integer i=0;i<32;i=i+1)begin @(negedge rc);rxde=1;end @(negedge rc);rxde=0;repeat(3)@(negedge rc);end
 pulse;wait(pv);repeat(1000)@(negedge pc);
 repeat(1200)begin @(negedge pc);if(de)begin
 if(rgb!==24'h234567)$fatal(1,"preview/display latency mismatch rgb=%h",rgb);
 if(iv)$fatal(1,"preview marked as corrected");checks=checks+1;end end
 if(checks<512)$fatal(1,"insufficient checked pixels");test_passed=1;$display("PREVIEW_DISPLAY_ALIGNMENT_PASS checks=%d",checks);$finish;end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
