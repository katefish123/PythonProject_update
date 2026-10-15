`timescale 1ns/1ps
module tb_frame_telemetry;
 reg proc_clk=0,pix_clk=0,run_pix=1;
 always #9.259 proc_clk=~proc_clk;
 always begin #3.367; if(run_pix) pix_clk=~pix_clk; end
 reg proc_rst_n=0,pix_rst_n=0,scan_de=1,scan_start=0,image_valid=1;
 reg [11:0] x=0,y=0;
 reg [31:0] displayed_frame_id=42,display_age_ms=23200,admitted_frames=101,published_frames=40,rejected_frames=61;
 reg [511:0] reject_reason_counts=0;
 wire on; wire [23:0] rgb;
 frame_telemetry_overlay #(.PROC_CYCLES_PER_MS(80)) dut(.*);
 task frame;
 begin @(negedge pix_clk);scan_start=1;@(negedge pix_clk);scan_start=0;end
 endtask
 task wait_request;
 integer k;
 begin k=0;while(dut.req_sync[2]==dut.ack_pix && k<3000)begin @(negedge pix_clk);k=k+1;end
 if(k==3000)$fatal(1,"mailbox snapshot never arrived");repeat(3)@(negedge pix_clk);end
 endtask
 task pixel(input integer px,py,input bit expected,input [23:0] color);
 begin x=px;y=py;#1;if(on!==expected)$fatal(1,"pixel %0d,%0d expected on=%0d got %0d",px,py,expected,on);
 if(expected&&rgb!==color)$fatal(1,"wrong color %h",rgb);end
 endtask
 function [34:0] expected_font(input [7:0] c);
 begin
 case(c)
 "H":expected_font=35'b10001_10001_10001_11111_10001_10001_10001;
 "E":expected_font=35'b11111_10000_10000_11110_10000_10000_11111;
 "L":expected_font=35'b10000_10000_10000_10000_10000_10000_11111;
 "D":expected_font=35'b11110_10001_10001_10001_10001_10001_11110;
 "A":expected_font=35'b01110_10001_10001_11111_10001_10001_10001;
 "G":expected_font=35'b01111_10000_10000_10111_10001_10001_01111;
 "0":expected_font=35'b01110_10001_10011_10101_11001_10001_01110;
 "2":expected_font=35'b01110_10001_00001_00010_00100_01000_11111;
 "3":expected_font=35'b11110_00001_00001_01110_00001_00001_11110;
 ".":expected_font=35'b00000_00000_00000_00000_00000_00000_10000;
 "S":expected_font=35'b01111_10000_10000_01110_00001_00001_11110;
 default:expected_font=0;
 endcase
 end
 endfunction
 task age_line(input [127:0] text_line,input [23:0] color);
 integer xx,yy,cc,gx,gy;reg[34:0] bits;reg expected;
 begin
 for(yy=0;yy<32;yy=yy+1)for(xx=0;xx<256;xx=xx+1)begin
 cc=xx/16;gx=(xx%16)/2;gy=(yy%16)/2;
 bits=expected_font(text_line[(15-cc)*8+:8]);expected=0;
 if(yy<16&&gx<5&&gy<7)expected=bits[34-gy*5-gx];
 pixel(16+xx,80+yy,expected,color);
 end
 end
 endtask
 reg[360:0] saved;
 integer k;
 initial begin
 reject_reason_counts[3*32+:32]=11;reject_reason_counts[4*32+:32]=12;
 reject_reason_counts[12*32+:32]=13;reject_reason_counts[13*32+:32]=25;
 #50;proc_rst_n=1;pix_rst_n=1;
 wait_request();
 if(dut.shown_valid!==0)$fatal(1,"snapshot applied mid-frame");
 frame();#1;
 if(dut.shown[39:0]!==40'h0000023200 || dut.shown[79:40]!==40'h0000000042 || dut.shown[360]!==1)
 $fatal(1,"held age/frame decimal conversion wrong: %h",dut.shown);
 if(dut.shown[119:80]!==40'h0000000040 || dut.shown[159:120]!==40'h0000000101 || dut.shown[199:160]!==40'h0000000061 || dut.shown[239:200]!==40'h0000000011 || dut.shown[279:240]!==40'h0000000013 || dut.shown[319:280]!==40'h0000000025 || dut.shown[359:320]!==40'h0000000012)$fatal(1,"counter routing incorrect");
 // H upper left, first glyph row, x16 has ink; x18 is blank at top of H.
 pixel(16,80,1,24'hffb040);pixel(18,80,0,0);pixel(24,80,1,24'hffb040);
 // HELD 023.2S: first digit 0 top middle, decimal exact placement.
 pixel(98,80,1,24'hffb040);pixel(144,92,1,24'hffb040);
 saved=dut.shown;displayed_frame_id=43;display_age_ms=32;published_frames=41;
 age_line("HELD 023.2S     ",24'hffb040);
 wait_request();repeat(20)@(negedge pix_clk);
 if(dut.shown!==saved)$fatal(1,"display telemetry tore within frame");
 frame();#1;
 if(dut.shown[39:0]!==40'h0000000032 || dut.shown[79:40]!==40'h0000000043 || dut.shown[360]!==0)$fatal(1,"fresh recovery incorrect");
 // AGE prefix: top of A has three center pixels.
 pixel(18,80,1,24'h40ff80);pixel(16,80,0,0);
 age_line("AGE  000.0S     ",24'h40ff80);
 image_valid=0;pixel(18,80,0,0);image_valid=1;scan_de=0;pixel(18,80,0,0);scan_de=1;
 for(k=560;k<1920;k=k+17)pixel(k,80,0,0);
 // Receiver stops: no ACK and held mailbox must not change even as counters churn.
 @(negedge pix_clk);run_pix=0;repeat(300)@(negedge proc_clk);saved=dut.mailbox;
 for(k=0;k<700;k=k+1)begin @(negedge proc_clk);display_age_ms=k;displayed_frame_id=k;end
 if(dut.mailbox!==saved)$fatal(1,"mailbox changed without ACK");
 run_pix=1;wait_request();frame();
 // Saturation and full unsigned 32-bit decimal, followed by threshold boundaries.
 display_age_ms=32'hffffffff;displayed_frame_id=32'hffffffff;wait_request();frame();wait_request();frame();#1;
 if(dut.shown[39:0]!==40'h0000999900 || dut.shown[79:40]!==40'h4294967295)$fatal(1,"age saturation or 32-bit BCD incorrect %h",dut.shown);
 display_age_ms=249;wait_request();frame();wait_request();frame();#1;if(dut.shown[360]!==0)$fatal(1,"249 ms falsely held");
 display_age_ms=250;wait_request();frame();wait_request();frame();#1;if(dut.shown[360]!==1)$fatal(1,"250 ms not held");
 // Randomized frame ACK delays; published/captured/frameID remain one snapshot.
 for(k=0;k<24;k=k+1)begin
 @(negedge proc_clk);display_age_ms=23200;displayed_frame_id=1000+k;published_frames=1000+k;admitted_frames=1000+k;
 wait_request();frame();wait_request();
 saved=dut.mailbox;
 repeat($urandom_range(80,900))@(negedge proc_clk);
 if(dut.mailbox!==saved)$fatal(1,"random ACK stall altered mailbox");
 frame();#1;
 if(dut.shown[79:40]!==dut.shown[119:80] || dut.shown[79:40]!==dut.shown[159:120])$fatal(1,"random frame received torn counters");
 end
 // Common hard reset clears both handshake epochs and all display state.
 proc_rst_n=0;pix_rst_n=0;#50;proc_rst_n=1;pix_rst_n=1;#1;
 if(dut.shown_valid!==0)$fatal(1,"reset left stale display valid");
 display_age_ms=250;wait_request();frame();#1;if(dut.shown[39:0]!==40'h0000000250)$fatal(1,"reset recovery failed");
 $display("PASS frame telemetry held23.2 recovery32 saturation async mailbox frame consistency fullpixels gating reset randomizedACK24");$finish;
 end
 initial begin #3000000;$fatal(1,"timeout");end
endmodule
