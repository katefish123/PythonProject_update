`timescale 1ns/1ps
module tb_selftest_status;
 reg clk=0,rst=0,rsp=0,rw=0;always #5 clk=~clk;
 wire cv,cw,sp,sf;wire[27:0]ca;wire[255:0]cd;wire[31:0]mask;wire[3:0]reason;
 reg test_passed=0;
 video_correct_ddr_core #(.IN_W(16),.IN_H(8),.SRC_W(16),.SRC_H(8),.OUT_W(8),.OUT_H(8),.SCALE(1),.BIST_BEATS(1),.FIFO_ADDR_BITS(4),
 .H_SYNC(2),.H_BACK(2),.H_ACTIVE(32),.H_FRONT(2),.V_SYNC(1),.V_BACK(1),.V_ACTIVE(16),.V_FRONT(1)) dut(
 .proc_clk(clk),.proc_rst_n(rst),.rx_clk(clk),.rx_rst_n(rst),.pix_clk(clk),.pix_rst_n(rst),.ui_clk(clk),.ui_rst_n(rst),
 .hdmi_ready(1'b1),.ddr_ready(1'b1),.memory_fault(1'b0),.rx_vs(1'b0),.rx_de(1'b0),.rx_rgb(24'd0),.nearest(1'b0),.force_pattern(1'b0),
 .hsync(),.vsync(),.de(),.rgb(),.image_valid(),.working(),.frame_error(),.input_wait(),.display_underrun(),
 .selftest_passed(sp),.selftest_failed(sf),.good_frames(),.rejected_frames(),.cmd_valid(cv),.cmd_write(cw),.cmd_addr(ca),.cmd_wdata(cd),.cmd_wstrb(mask),
 .cmd_ready(1'b1),.rsp_valid(rsp),.rsp_write(rw),.rsp_rdata(256'd0),.diagnostic_reason(reason),.diagnostic_phase(),
 .preview_valid(1'b0),.preview_rgb(24'd0),.overlay_on(1'b0),.overlay_rgb(24'd0),.scan_x(),.scan_y(),.scan_de(),.scan_start(),.scan_reset_n());
 // Deliberately corrupt BIST reads, exercising the actual DDR self-test.
 always @(posedge clk)begin rsp<=rst&&cv;rw<=cw;end
 initial begin #30;rst=1;wait(sf);repeat(12)@(negedge clk);
 if(reason!=7)$fatal(1,"DDR_SELFTEST_FAILURE_NOT_DISPLAYED reason=%d",reason);
 if(sp)$fatal(1,"corrupt memory passed selftest");test_passed=1;$display("DDR_SELFTEST_STATUS_PASS");$finish;end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
