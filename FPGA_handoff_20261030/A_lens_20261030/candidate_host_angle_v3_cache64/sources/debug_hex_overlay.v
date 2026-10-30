`timescale 1ns/1ps
`default_nettype none
// Readable hexadecimal diagnostic rows in the unused corrected left margin.
// In RAW this is an overlay, never a scale/crop of the source image.
// Row00 is actual PIX display metadata; rows01..15 are atomic PROC snapshots.
module debug_hex_overlay(input wire proc_clk,pix_clk,rst_n,scan_de,
 input wire[11:0]x,y,input wire[1919:0]data,input wire[79:0]pix_metadata,
 output reg on,output reg[23:0]rgb);
 wire[1919:0]snapshot;wire valid;
 snapshot_cdc #(.WIDTH(1920)) crossing(.s_clk(proc_clk),.d_clk(pix_clk),.rst_n(rst_n),.s_data(data),.d_data(snapshot),.d_valid(valid));
 reg[1919:0]shown;reg[79:0]row_word;
 wire[4:0]row=(y-64)>>5;wire[4:0]column=x>>4;
 wire[3:0]digit=column==0?{3'd0,row[4]}:column==1?row[3:0]:column>=3&&column<23?row_word[79-(column-3)*4-:4]:4'd0;
 reg[6:0]segments;
 always @*case(digit)
 0:segments=7'b1111110;1:segments=7'b0110000;2:segments=7'b1101101;3:segments=7'b1111001;
 4:segments=7'b0110011;5:segments=7'b1011011;6:segments=7'b1011111;7:segments=7'b1110000;
 8:segments=7'b1111111;9:segments=7'b1111011;10:segments=7'b1110111;11:segments=7'b0011111;
 12:segments=7'b1001110;13:segments=7'b0111101;14:segments=7'b1001111;15:segments=7'b1000111;
 endcase
 wire[3:0]cx=x[3:0];wire[4:0]cy=y[4:0];
 wire horizontal=cx>=3&&cx<=8;
 wire top=cy>=2&&cy<=3,middle=cy>=9&&cy<=10,bottom=cy>=16&&cy<=17;
 wire left=cx>=1&&cx<=2,right=cx>=9&&cx<=10,upper=cy>=4&&cy<=8,lower=cy>=11&&cy<=15;
 wire ink=(horizontal&&((top&&segments[6])||(middle&&segments[0])||(bottom&&segments[3])))
 ||(upper&&((right&&segments[5])||(left&&segments[1])))||(lower&&((right&&segments[4])||(left&&segments[2])));
 always @(posedge pix_clk or negedge rst_n)begin
 if(!rst_n)begin shown<=0;row_word<=0;on<=0;rgb<=0;end
 else begin
 // y wraps during leading vertical blank. Hold all rows throughout active
 // scan, including horizontal blanking, so coefficients never mix frames.
 if(!scan_de&&y>=12'h800&&valid)begin shown<=snapshot;shown[79:0]<=pix_metadata;end
 row_word<=shown[row*80+:80];
 on<=scan_de&&y>=64&&y<832&&x<368;
 rgb<=(column!=2&&ink)?24'hffffff:24'h101010;
 end end
endmodule
`default_nettype wire
