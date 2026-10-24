`timescale 1ns/1ps
module tb;
reg cfg_clk=0,pix_clk=0;always #5 cfg_clk=~cfg_clk;always #3.5 pix_clk=~pix_clk;
reg cfg_rst=0,pix_rst=0,key1_pattern_n=1,key2_nearest_n=1,scan_start=0,image_valid=1;
reg[4:0]pix_status=9;reg status_on=1,telemetry_on=1;
reg[23:0]status_rgb=24'h123456,telemetry_rgb=24'habcdef;
wire overlay_on;wire[23:0]overlay_rgb;
reg[31:0]debug_display_id=1;reg freeze_display=0;wire[4:0]observed_status;
presentation_policy #(.DIAGNOSTIC_HOLD_CYCLES(4),.PRESENTATION_STALE_FRAMES(4)) dut(.*);
task frame;
begin @(negedge pix_clk);if(!freeze_display)debug_display_id++;scan_start=1;@(negedge pix_clk);scan_start=0;repeat(2)@(negedge pix_clk);#0.1;end endtask
task expect_off;begin if(overlay_on!==0)$fatal(1,"CLEAN_FULLHD_IMAGE_OBSCURED");end endtask
initial begin
 #30;cfg_rst=1;pix_rst=1;frame();expect_off();
 pix_status=12;frame();expect_off();pix_status=13;frame();expect_off();
 pix_status=21;#2;expect_off();frame();if(!overlay_on||overlay_rgb!==status_rgb)$fatal(1,"FAULT_HIDDEN");
 status_on=0;#1;expect_off();
 pix_status=9;frame();expect_off();
 key1_pattern_n=0;key2_nearest_n=0;repeat(20)@(negedge cfg_clk);#1;expect_off();
 frame();if(!overlay_on||overlay_rgb!==telemetry_rgb)$fatal(1,"DIAGNOSTIC_NOT_AVAILABLE");
 repeat(50)@(negedge cfg_clk);frame();if(!overlay_on)$fatal(1,"HELD_CHORD_RETOGGLED");
 key1_pattern_n=1;key2_nearest_n=1;repeat(12)@(negedge cfg_clk);
 // A short bounce cannot count as another completed press.
 key1_pattern_n=0;key2_nearest_n=0;repeat(2)@(negedge cfg_clk);key1_pattern_n=1;key2_nearest_n=1;
 repeat(12)@(negedge cfg_clk);frame();if(!overlay_on)$fatal(1,"BOUNCE_TOGGLED");
 key1_pattern_n=0;key2_nearest_n=0;repeat(20)@(negedge cfg_clk);frame();expect_off();
 key1_pattern_n=1;key2_nearest_n=1;repeat(12)@(negedge cfg_clk);
 image_valid=0;status_on=1;frame();if(!overlay_on)$fatal(1,"WAIT_INPUT_HIDDEN");
 image_valid=1;pix_status=9;frame();expect_off();
 freeze_display=1;pix_status=13;repeat(5)frame();
 if(!overlay_on||observed_status!=13)$fatal(1,"LONG_STALE_FRAME_HIDDEN");
 pix_status=9;frame();if(!overlay_on||observed_status!=13)$fatal(1,"LOCAL_STALE_STATUS_NOT_OVERRIDDEN");
 pix_status=21;frame();if(!overlay_on||observed_status!=21)$fatal(1,"STALE_MASKED_REAL_FAULT");
 freeze_display=0;pix_status=9;frame();expect_off();
 cfg_rst=0;pix_rst=0;#30;cfg_rst=1;pix_rst=1;frame();expect_off();
 $display("PASS PRESENTATION clean_RAW_corrected_held=1 faults_visible=1 chord_toggle=1 debounce=1 frame_boundary=1 reset=1");$finish;
end
initial begin #100000;$fatal(1,"TIMEOUT");end
endmodule
