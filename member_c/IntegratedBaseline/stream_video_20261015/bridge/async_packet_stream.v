`timescale 1ns/1ps
`default_nettype none
// Registered-read CDC FIFO adapter. Reserved includes both skid entries and
// the FIFO read pipeline. Four skid slots permit a new read on every rd_clk.
module async_packet_stream #(parameter DATA_WIDTH=32,ADDR_BITS=9)(
 input wire wr_clk,rd_clk,rst_n,
 input wire s_valid,output wire s_ready,input wire[DATA_WIDTH-1:0]s_data,
 output wire m_valid,input wire m_ready,output wire[DATA_WIDTH-1:0]m_data
);
 wire full,empty,rd_valid;wire[DATA_WIDTH-1:0]rd_data;
 reg[DATA_WIDTH-1:0]skid[0:3];reg[1:0]head,tail;
 reg[2:0]count,reserved;
 wire pop=m_valid&&m_ready;
 // Four reserved slots cover the registered FIFO read and skid write latency.
 // Do not borrow a slot from this cycle's downstream pop: that lookahead
 // feeds cache tag lookup through rd_ready into the FIFO Gray/empty cone.
 // A full queue's first pop frees a slot for the next cycle; the remaining
 // three entries cover the refill latency while sustaining one packet/clock.
 wire rd_en=rst_n&&!empty&&reserved<4;
 assign s_ready=rst_n&&!full;
 assign m_valid=rst_n&&count!=0;
 assign m_data=skid[head];
 async_packet_fifo #(.DATA_WIDTH(DATA_WIDTH),.ADDR_BITS(ADDR_BITS)) fifo(
 .wr_clk(wr_clk),.rd_clk(rd_clk),.rst_n(rst_n),
 .wr_en(s_valid&&s_ready),.wr_data(s_data),.full(full),
 .rd_en(rd_en),.rd_data(rd_data),.rd_valid(rd_valid),.empty(empty));
 always @(posedge rd_clk or negedge rst_n)begin
 if(!rst_n)begin head<=0;tail<=0;count<=0;reserved<=0;end
 else begin
 case({rd_en,pop})2'b10:reserved<=reserved+1;2'b01:reserved<=reserved-1;default:begin end endcase
 case({rd_valid,pop})2'b10:count<=count+1;2'b01:count<=count-1;default:begin end endcase
 if(rd_valid)begin skid[tail]<=rd_data;tail<=tail+1;end
 if(pop)head<=head+1;
 end end
endmodule
`default_nettype wire
