`timescale 1ns/1ps
`default_nettype none
// Packs eight RGB888 pixels into a 256-bit memory beat, with a zero padding
// byte per pixel. A result is not publishable until drained is asserted.
module ddr_result_writer #(
 parameter OUT_W=320,OUT_H=452,
 parameter [27:0] BASE0=28'h0100000,BASE1=28'h0200000
)(
 input wire clk,rst_n,frame_start,abort_frame,frame_bank,
 input wire write_valid,output wire write_ready,
 input wire [23:0] write_addr,write_rgb,
 output wire drained,output reg fault,
 output wire cmd_valid,input wire cmd_ready,
 output wire cmd_write,output reg [27:0] cmd_addr,
 output wire [255:0] cmd_wdata,output wire [31:0] cmd_wstrb,
 input wire rsp_valid,rsp_write
);
 localparam FILL=0,SEND=1,WAIT_RSP=2;
 reg [1:0] state;
 reg [255:0] packed_pixels;
 reg [31:0] strobes;
 reg [23:0] expected_addr;
 reg [3:0] buffered;
 reg aborted;
 assign write_ready=rst_n&&state==FILL&&!fault&&!abort_frame;
 assign drained=rst_n&&state==FILL&&buffered==0;
 assign cmd_valid=rst_n&&state==SEND&&!abort_frame;
 assign cmd_write=1'b1;
 assign cmd_wdata=packed_pixels;assign cmd_wstrb=strobes;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=FILL;packed_pixels<=0;strobes<=0;expected_addr<=0;
   buffered<=0;cmd_addr<=0;fault<=0;aborted<=0;
  end else begin
   if(frame_start&&drained)begin expected_addr<=0;fault<=0;aborted<=0;end
   case(state)
    FILL:if(write_valid&&write_ready)begin
     if(write_addr!=expected_addr||write_addr>=OUT_W*OUT_H)fault<=1;
     else begin
      packed_pixels[write_addr[2:0]*32+:32]<={8'd0,write_rgb};
      strobes[write_addr[2:0]*4+:4]<=4'hf;
      expected_addr<=expected_addr+1;buffered<=buffered+1;
      if(write_addr[2:0]==0)cmd_addr<=(frame_bank?BASE1:BASE0)+{4'd0,write_addr[23:3],3'b000};
      if(write_addr[2:0]==7||write_addr==OUT_W*OUT_H-1)state<=SEND;
     end
    end
    SEND:if(cmd_valid&&cmd_ready)begin
     if(rsp_valid)begin
      if(!rsp_write)fault<=1;
      state<=FILL;buffered<=0;strobes<=0;packed_pixels<=0;
     end else state<=WAIT_RSP;
    end
    WAIT_RSP:if(rsp_valid)begin
     if(!rsp_write)fault<=1;
     state<=FILL;buffered<=0;strobes<=0;packed_pixels<=0;
    end
    default:begin state<=FILL;fault<=1;end
   endcase
   if(abort_frame)begin
    aborted<=1;fault<=0;
    // Accepted transactions must finish; unaccepted partial data is discarded.
    if(state!=WAIT_RSP)begin state<=FILL;buffered<=0;strobes<=0;packed_pixels<=0;end
   end
  end
 end
endmodule
`default_nettype wire
