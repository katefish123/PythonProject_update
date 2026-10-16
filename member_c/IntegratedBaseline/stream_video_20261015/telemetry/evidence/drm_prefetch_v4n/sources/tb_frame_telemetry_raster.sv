`timescale 1ns/1ps
module tb_frame_telemetry_raster;
 reg proc_clk=0,pix_clk=0,run_pix=1;
 always #9.259 proc_clk=~proc_clk;
 always begin #3.367; if(run_pix) pix_clk=~pix_clk; end
 reg proc_rst_n=0,pix_rst_n=0,scan_de=1,scan_start=0,image_valid=1;
 reg [11:0] x=0,y=0;
 reg [31:0] displayed_frame_id=42,display_age_ms=23200,admitted_frames=101,published_frames=40,rejected_frames=61;
 reg [511:0] reject_reason_counts=0;
 wire on; wire [23:0] rgb;
 frame_telemetry_overlay #(.PROC_CYCLES_PER_MS(80)) dut(.*);
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
 "1":expected_font=35'b00100_01100_00100_00100_00100_00100_01110;
 "4":expected_font=35'b00010_00110_01010_10010_11111_00010_00010;
 "5":expected_font=35'b11111_10000_10000_11110_00001_00001_11110;
 "6":expected_font=35'b01110_10000_10000_11110_10001_10001_01110;
 "7":expected_font=35'b11111_00001_00010_00100_01000_01000_01000;
 "8":expected_font=35'b01110_10001_10001_01110_10001_10001_01110;
 "9":expected_font=35'b01110_10001_10001_01111_00001_00001_01110;
 "F":expected_font=35'b11111_10000_10000_11110_10000_10000_10000;
 "R":expected_font=35'b11110_10001_10001_11110_10100_10010_10001;
 "M":expected_font=35'b10001_11011_10101_10101_10001_10001_10001;
 "P":expected_font=35'b11110_10001_10001_11110_10000_10000_10000;
 "U":expected_font=35'b10001_10001_10001_10001_10001_10001_01110;
 "B":expected_font=35'b11110_10001_10001_11110_10001_10001_11110;
 "C":expected_font=35'b01111_10000_10000_10000_10000_10000_01111;
 "J":expected_font=35'b00111_00010_00010_00010_10010_10010_01100;
 "K":expected_font=35'b10001_10010_10100_11000_10100_10010_10001;
 "O":expected_font=35'b01110_10001_10001_10001_10001_10001_01110;
 "V":expected_font=35'b10001_10001_10001_10001_10001_01010_00100;
 default:expected_font=0;
 endcase
 end
 endfunction

 reg[127:0] text_line[0:8];
 integer frames_checked=0,ink_checked=0;
 task raster(input bit fresh);
 integer xx,yy,row,col,gx,gy;reg expected;reg[34:0] glyph;reg[23:0]color;
 begin
 text_line[0]=fresh?"AGE  000.0S     ":"HELD 023.2S     ";
 text_line[1]=fresh?"FRAME 0000000043":"FRAME 0000000042";
 text_line[2]=fresh?"PUB   0000000041":"PUB   0000000040";
 text_line[3]="CAP   0000000101";text_line[4]="REJ   0000000061";
 text_line[5]="MARK  0000000011";text_line[6]="SHAPE 0000000013";
 text_line[7]="OVER  0000000025";text_line[8]="SOLVE 0000000012";
 color=fresh?24'h40ff80:24'hffb040;
 for(yy=0;yy<1125;yy=yy+1)for(xx=0;xx<2200;xx=xx+1)begin
 @(negedge pix_clk);x=xx;y=yy;scan_de=xx<1920&&yy<1080;scan_start=(xx==0&&yy==0);
 #1;expected=0;glyph=0;
 if(xx>=16&&xx<272&&yy>=80&&yy<350)begin
 row=(yy-80)/32;col=(xx-16)/16;gx=((xx-16)%16)/2;gy=((yy-80)%32)/2;
 glyph=expected_font(text_line[row][(15-col)*8+:8]);
 if(gx<5&&gy<7)expected=glyph[34-gy*5-gx];
 end
 if(on!==expected || (expected&&rgb!==color))$fatal(1,"full raster mismatch fresh=%0d x=%0d y=%0d expected=%0b on=%0b color=%h",fresh,xx,yy,expected,on,rgb);
 if(expected)ink_checked=ink_checked+1;
 end
 frames_checked=frames_checked+1;
 end
 endtask
 initial begin
 reject_reason_counts[3*32+:32]=11;reject_reason_counts[4*32+:32]=12;
 reject_reason_counts[12*32+:32]=13;reject_reason_counts[13*32+:32]=25;
 #50;proc_rst_n=1;pix_rst_n=1;repeat(200)@(negedge proc_clk);
 raster(0);
 // Consume any one-entry pending old snapshot, then admit updated statistics.
 @(negedge pix_clk);scan_start=1;@(negedge pix_clk);scan_start=0;
 displayed_frame_id=43;display_age_ms=32;published_frames=41;
 repeat(200)@(negedge proc_clk);
 raster(1);
 if(frames_checked!=2 || ink_checked<10000)$fatal(1,"coverage incomplete");
 $display("PASS fullHD telemetry raster frames=%0d ink=%0d exactcoordinates noportraitoverlap allrows",frames_checked,ink_checked);$finish;
 end
 initial begin #100000000;$fatal(1,"raster timeout");end
endmodule
