`timescale 1ns/1ps
`default_nettype none
// Dual-clock packet FIFO. A shared asynchronous reset asserts immediately and
// releases through independent synchronizers in the write/read clock domains.
module async_packet_fifo #(
 parameter DATA_WIDTH=285,
 parameter ADDR_BITS=9
)(
 input wire wr_clk,rd_clk,rst_n,
 input wire wr_en,input wire [DATA_WIDTH-1:0] wr_data,output wire full,
 input wire rd_en,output reg [DATA_WIDTH-1:0] rd_data,
 output reg rd_valid,output wire empty
);
 localparam PTR_BITS=ADDR_BITS+1;
 localparam DEPTH=(1<<ADDR_BITS);
 (* ram_style="block" *) reg [DATA_WIDTH-1:0] memory[0:DEPTH-1];
 reg [1:0] wr_release,rd_release;
 wire wr_local_rst_n=wr_release[1];
 wire rd_local_rst_n=rd_release[1];
 reg [PTR_BITS-1:0] wr_bin,wr_gray,rd_bin,rd_gray;
 (* ASYNC_REG="TRUE" *) reg [PTR_BITS-1:0] rd_gray_w1,rd_gray_w2;
 (* ASYNC_REG="TRUE" *) reg [PTR_BITS-1:0] wr_gray_r1,wr_gray_r2;
 reg full_reg,empty_reg;
 wire wr_take=wr_en&&!full;
 wire rd_take=rd_en&&!empty;
 wire [PTR_BITS-1:0] wr_bin_next=wr_bin+wr_take;
 wire [PTR_BITS-1:0] rd_bin_next=rd_bin+rd_take;
 wire [PTR_BITS-1:0] wr_gray_next=(wr_bin_next>>1)^wr_bin_next;
 wire [PTR_BITS-1:0] rd_gray_next=(rd_bin_next>>1)^rd_bin_next;
 wire [PTR_BITS-1:0] full_compare={~rd_gray_w2[PTR_BITS-1:PTR_BITS-2],rd_gray_w2[PTR_BITS-3:0]};
 assign full=!wr_local_rst_n||full_reg;
 assign empty=!rd_local_rst_n||empty_reg;

 always @(posedge wr_clk or negedge rst_n)begin
  if(!rst_n)wr_release<=0;
  else wr_release<={wr_release[0],1'b1};
 end
 always @(posedge rd_clk or negedge rst_n)begin
  if(!rst_n)rd_release<=0;
  else rd_release<={rd_release[0],1'b1};
 end
 always @(posedge wr_clk or negedge wr_local_rst_n)begin
  if(!wr_local_rst_n)begin rd_gray_w1<=0;rd_gray_w2<=0;end
  else begin rd_gray_w1<=rd_gray;rd_gray_w2<=rd_gray_w1;end
 end
 always @(posedge rd_clk or negedge rd_local_rst_n)begin
  if(!rd_local_rst_n)begin wr_gray_r1<=0;wr_gray_r2<=0;end
  else begin wr_gray_r1<=wr_gray;wr_gray_r2<=wr_gray_r1;end
 end
 // Keep the inferred dual-port RAM read/write processes free of reset logic.
 always @(posedge wr_clk)if(wr_take)memory[wr_bin[ADDR_BITS-1:0]]<=wr_data;
 always @(posedge rd_clk)if(rd_take)rd_data<=memory[rd_bin[ADDR_BITS-1:0]];
 always @(posedge wr_clk or negedge wr_local_rst_n)begin
  if(!wr_local_rst_n)begin wr_bin<=0;wr_gray<=0;full_reg<=0;end
  else begin
   if(wr_take)begin wr_bin<=wr_bin_next;wr_gray<=wr_gray_next;end
   full_reg<=wr_gray_next==full_compare;
  end
 end
 always @(posedge rd_clk or negedge rd_local_rst_n)begin
  if(!rd_local_rst_n)begin rd_bin<=0;rd_gray<=0;empty_reg<=1;rd_valid<=0;end
  else begin
   rd_valid<=rd_take;
   if(rd_take)begin rd_bin<=rd_bin_next;rd_gray<=rd_gray_next;end
   empty_reg<=rd_gray_next==wr_gray_r2;
  end
 end
endmodule
`default_nettype wire
