`timescale 1ns/1ps
`default_nettype none
// Complete beats are owned until the corresponding UI response returns.
// Both resets must assert together with the memory command engine hard reset.
module ddr_result_writer_stream #(
 parameter OUT_W=768,OUT_H=1080,
 parameter [27:0] BASE0=28'h0200000,BASE1=28'h0400000,
 parameter FIFO_ADDR_BITS=6
)(
 input wire clk,rst_n,ui_clk,ui_rst_n,
 input wire frame_start,abort_frame,frame_bank,
 input wire write_valid,output wire write_ready,
 input wire [23:0] write_addr,write_rgb,
 output wire drained,output reg fault,
 output wire cmd_valid,input wire cmd_ready,
 output wire cmd_write,output wire [27:0] cmd_addr,
 output wire [255:0] cmd_wdata,output wire [31:0] cmd_wstrb,
 input wire rsp_valid,rsp_write
);
 localparam COUNT_BITS=FIFO_ADDR_BITS+3;
 localparam [23:0] LAST_ADDR=OUT_W*OUT_H-1;
 wire common_rst_n=rst_n&&ui_rst_n;
 reg [1:0] source_release,ui_release;
 always @(posedge clk or negedge common_rst_n)
  if(!common_rst_n)source_release<=0;else source_release<={source_release[0],1'b1};
 always @(posedge ui_clk or negedge common_rst_n)
  if(!common_rst_n)ui_release<=0;else ui_release<={ui_release[0],1'b1};
 wire source_live=source_release[1],ui_live=ui_release[1];
 reg active,aborted;
 reg [27:0] frame_base;
 reg [23:0] expected_addr;
 reg [2:0] buffered;
 reg [255:0] pixels;
 reg [31:0] strobes;
 reg [COUNT_BITS-1:0] owned;
 wire qfull,qempty,qvalid;
 wire [315:0] qdata;
 wire afull,aempty,avalid;
 wire [0:0] adata;
 wire good_addr=(write_addr==expected_addr)&&(write_addr<OUT_W*OUT_H);
 wire closes=(buffered==7)||(write_addr==LAST_ADDR);
 assign write_ready=source_live&&active&&!aborted&&!fault&&!abort_frame&&!frame_start&&(!closes||!qfull);
 wire take=write_valid&&write_ready;
 wire enqueue=take&&good_addr&&closes;
 wire [255:0] completed_pixels=pixels|({232'b0,write_rgb} << (buffered*32));
 wire [31:0] completed_strobes=strobes|(32'hf << (buffered*4));
 wire [27:0] beat_address=frame_base+{4'b0,write_addr[23:3],3'b0};
 assign drained=source_live&&(owned==0)&&(buffered==0);
 wire qpop;
 stream_writer_async_fifo #(.WIDTH(316),.ADDR_BITS(FIFO_ADDR_BITS)) command_fifo(
  .wr_clk(clk),.rd_clk(ui_clk),.rst_n(common_rst_n),.wr_en(enqueue),
  .wr_data({beat_address,completed_strobes,completed_pixels}),.full(qfull),
  .rd_en(qpop),.rd_data(qdata),.rd_valid(qvalid),.empty(qempty));
 wire ack_push;
 stream_writer_async_fifo #(.WIDTH(1),.ADDR_BITS(FIFO_ADDR_BITS)) acknowledgement_fifo(
  .wr_clk(ui_clk),.rd_clk(clk),.rst_n(common_rst_n),.wr_en(ack_push),
  .wr_data({!rsp_write}),.full(afull),.rd_en(!aempty),.rd_data(adata),.rd_valid(avalid),.empty(aempty));
 always @(posedge clk or negedge source_live) begin
  if(!source_live) begin
   active<=0;aborted<=1;frame_base<=0;expected_addr<=0;buffered<=0;pixels<=0;strobes<=0;owned<=0;fault<=0;
  end else begin
   case({enqueue,avalid})
    2'b10:owned<=owned+1'b1;
    2'b01:if(owned!=0)owned<=owned-1'b1;
    default:owned<=owned;
   endcase
   if(avalid&&((owned==0)||adata[0]))begin fault<=1;aborted<=1;buffered<=0;pixels<=0;strobes<=0;end
   if(frame_start) begin
    if(drained) begin
     active<=1;aborted<=0;fault<=0;frame_base<=frame_bank?BASE1:BASE0;expected_addr<=0;
    end else begin fault<=1;aborted<=1;buffered<=0;pixels<=0;strobes<=0;end
   end
   if(take) begin
    if(!good_addr)begin fault<=1;aborted<=1;buffered<=0;pixels<=0;strobes<=0;end
    else begin
     expected_addr<=expected_addr+1'b1;
     if(closes)begin buffered<=0;pixels<=0;strobes<=0;end
     else begin buffered<=buffered+1'b1;pixels<=completed_pixels;strobes<=completed_strobes;end
    end
   end
   if(abort_frame)begin aborted<=1;fault<=0;buffered<=0;pixels<=0;strobes<=0;end
  end
 end
 // One outstanding UI transaction reserves one free acknowledgement slot.
 // Until its response, no other producer can consume that slot. The command
 // holding register is independent, so the following FIFO beat is prefetched.
 reg [315:0] command_hold;
 reg hold_valid,read_pending,inflight;
 assign qpop=ui_live&&!hold_valid&&!read_pending&&!qempty;
 assign cmd_valid=ui_live&&hold_valid&&!inflight&&!afull;
 assign cmd_write=1'b1;
 assign cmd_addr=command_hold[315:288];
 assign cmd_wstrb=command_hold[287:256];
 assign cmd_wdata=command_hold[255:0];
 wire issue=cmd_valid&&cmd_ready;
 assign ack_push=ui_live&&rsp_valid&&(inflight||issue);
 always @(posedge ui_clk or negedge ui_live) begin
  if(!ui_live)begin command_hold<=0;hold_valid<=0;read_pending<=0;inflight<=0;end
  else begin
   if(qpop)read_pending<=1;
   if(qvalid)begin command_hold<=qdata;hold_valid<=1;read_pending<=0;end
   if(issue)begin hold_valid<=0;inflight<=!rsp_valid;end
   if(rsp_valid&&inflight)inflight<=0;
  end
 end
 // synthesis translate_off
 initial begin
  if(FIFO_ADDR_BITS<2)$fatal(1,"FIFO_ADDR_BITS must be >= 2");
  if(OUT_W*OUT_H<1||OUT_W*OUT_H>16777215)$fatal(1,"frame extent exceeds address range");
 end
 always @(posedge ui_clk)if(ui_live&&ack_push&&afull)$fatal(1,"ACK reservation violated");
 // synthesis translate_on
endmodule

// Gray-pointer dual-clock FIFO with registered RAM read and explicit valid.
module stream_writer_async_fifo #(parameter WIDTH=316,ADDR_BITS=6)(
 input wire wr_clk,rd_clk,rst_n,wr_en,input wire[WIDTH-1:0]wr_data,
 output wire full,input wire rd_en,output reg[WIDTH-1:0]rd_data,
 output reg rd_valid,output wire empty
);
 localparam P=ADDR_BITS+1;
 reg[WIDTH-1:0] mem[0:(1<<ADDR_BITS)-1];
 reg[1:0] wr_release,rd_release;
 wire wr_reset=wr_release[1],rd_reset=rd_release[1];
 reg[P-1:0] wb,wg,rb,rg;
 (* ASYNC_REG="TRUE" *) reg[P-1:0] rg1,rg2,wg1,wg2;
 reg f,e;
 wire wt=wr_en&&!full,rt=rd_en&&!empty;
 wire[P-1:0] wn=wb+wt,rn=rb+rt;
 wire[P-1:0] wgn=(wn>>1)^wn,rgn=(rn>>1)^rn;
 assign full=!wr_reset||f;assign empty=!rd_reset||e;
 always @(posedge wr_clk or negedge rst_n)if(!rst_n)wr_release<=0;else wr_release<={wr_release[0],1'b1};
 always @(posedge rd_clk or negedge rst_n)if(!rst_n)rd_release<=0;else rd_release<={rd_release[0],1'b1};
 always @(posedge wr_clk or negedge wr_reset)begin
  if(!wr_reset)begin wb<=0;wg<=0;rg1<=0;rg2<=0;f<=0;end
  else begin rg1<=rg;rg2<=rg1;wb<=wn;wg<=wgn;f<=(wgn=={~rg2[P-1:P-2],rg2[P-3:0]});end
 end
 always @(posedge rd_clk or negedge rd_reset)begin
  if(!rd_reset)begin rb<=0;rg<=0;wg1<=0;wg2<=0;e<=1;rd_valid<=0;end
  else begin wg1<=wg;wg2<=wg1;rb<=rn;rg<=rgn;e<=(rgn==wg2);rd_valid<=rt;end
 end
 always @(posedge wr_clk)if(wt)mem[wb[ADDR_BITS-1:0]]<=wr_data;
 always @(posedge rd_clk)if(rt)rd_data<=mem[rb[ADDR_BITS-1:0]];
endmodule
`default_nettype wire
