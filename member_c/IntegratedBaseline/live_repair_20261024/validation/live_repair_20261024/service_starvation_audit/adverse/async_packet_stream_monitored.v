`timescale 1ns/1ps
`default_nettype none
// Registered-read CDC FIFO adapter. Reserved covers skid entries, the FIFO
// read pipeline and an output pop awaiting one-cycle registered reclamation.
module async_packet_stream_monitored #(parameter DATA_WIDTH=32,ADDR_BITS=9)(
 output wire[ADDR_BITS:0]wr_peak,input wire wr_clk,rd_clk,rst_n,
 input wire s_valid,output wire s_ready,input wire[DATA_WIDTH-1:0]s_data,
 output wire m_valid,input wire m_ready,output wire[DATA_WIDTH-1:0]m_data
);
 wire full,empty,rd_valid;wire[DATA_WIDTH-1:0]rd_data;
 reg[DATA_WIDTH-1:0]skid[0:3];reg[1:0]head,tail;
 reg[2:0]count,reserved;reg pop_q;
 wire pop=m_valid&&m_ready;
 // Invariant: reserved = count + rd_valid + pop_q for this one-cycle FIFO.
 // Reclaim the previous output acceptance, never the current downstream ready.
 // Four slots cover delayed reclamation and the read pipeline: a full skid
 // drains 4->3->2->1->1 and sustains one output per clock during refill.
 wire rd_en=rst_n&&!empty&&reserved<4;
 assign s_ready=rst_n&&!full;
 assign m_valid=rst_n&&count!=0;
 assign m_data=skid[head];
 async_packet_fifo_monitored #(.DATA_WIDTH(DATA_WIDTH),.ADDR_BITS(ADDR_BITS)) fifo(
 .wr_clk(wr_clk),.rd_clk(rd_clk),.rst_n(rst_n),
 .wr_peak(wr_peak),.wr_en(s_valid&&s_ready),.wr_data(s_data),.full(full),
 .rd_en(rd_en),.rd_data(rd_data),.rd_valid(rd_valid),.empty(empty));
 always @(posedge rd_clk or negedge rst_n)begin
 if(!rst_n)begin head<=0;tail<=0;count<=0;reserved<=0;pop_q<=0;end
 else begin
 pop_q<=pop;
 case({rd_en,pop_q})2'b10:reserved<=reserved+1;2'b01:reserved<=reserved-1;default:begin end endcase
 case({rd_valid,pop})2'b10:count<=count+1;2'b01:count<=count-1;default:begin end endcase
 if(rd_valid)begin skid[tail]<=rd_data;tail<=tail+1;end
 if(pop)head<=head+1;
 end end
endmodule
`default_nettype wire
