`timescale 1ns/1ps
module tb_hdmi_bram_stale;
reg wc=0,rc=0,rst=0,de=0,fs=0,re=0;
reg source_clock_running=1;
reg [23:0] pixel=0;reg [15:0] ra=0;
wire [23:0] q;wire valid;
wire [15:0] samples;wire [2:0] flags;
integer test_passed=0,test_failed=0;
always #5 if(source_clock_running)wc=~wc;
always #7 rc=~rc;
hdmi_bram_probe #(.SAMPLE_STEP(1),.FRAME_WORDS(2),.FRAME_GAP(4),.STALE_FRAME_LIMIT(3)) dut(
 .wr_clk(wc),.wr_reset_n(rst),.de(de),.pixel(pixel),.rd_clk(rc),.rd_reset_n(rst),
 .frame_start(fs),.rd_enable(re),.rd_addr(ra),.rd_pixel(q),.frame_valid(valid),.samples_written(samples),.writer_flags(flags));
task display_boundary;
begin
 repeat(6)@(negedge rc);fs=1;@(negedge rc);fs=0;@(negedge rc);
end endtask
task source_frame;input [23:0] base;
begin
 repeat(10)@(negedge wc);
 de=1;pixel=base;@(negedge wc);pixel=base+1;@(negedge wc);de=0;
 repeat(6)@(negedge wc);
end endtask
task fail;input [255:0] reason;
begin test_failed=1;$display("FAIL_STALE %s",reason);$finish;end endtask
initial begin
 #40;rst=1;
 source_frame(24'h112233);display_boundary;
 if(valid!==1)fail("first frame absent");
 source_clock_running=0;
 display_boundary;display_boundary;
 if(valid!==1)fail("timeout too early");
 display_boundary;
 if(valid!==0)fail("stopped source remains valid");
 re=1;repeat(2)@(negedge rc);
 if(q!==0)fail("stale pixels still readable");
 source_clock_running=1;
 source_frame(24'h445566);display_boundary;
 if(valid!==1)fail("reconnect not adopted");
 repeat(2)@(negedge rc);
 if(q!==24'h445566)fail("reconnect pixels incorrect");
 rst=0;#10;if(valid!==0)fail("reset still valid");
 test_passed=1;$display("PASS_BRAM_STALE_TIMEOUT_AND_RECOVERY");$finish;
end
initial begin #10000;fail("test timeout");end
endmodule
