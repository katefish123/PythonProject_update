`timescale 1ns/1ps
`default_nettype none
// Complete64word result blocks remain owned until the native8beat write response.
// Both resets must assert together with the memory command engine hard reset.
module ddr_result_writer_burst64 #(
 parameter OUT_W=768,OUT_H=1080,
 parameter [27:0] BASE0=28'h0200000,BASE1=28'h0400000,
 parameter FIFO_ADDR_BITS=4,TILED_ORDER=0
)(
 input wire clk,rst_n,ui_clk,ui_rst_n,
 input wire frame_start,abort_frame,frame_bank,frame_tiled,
 input wire write_valid,output wire write_ready,
 input wire [23:0] write_addr,write_rgb,
 output wire drained,output reg fault,
 output wire cmd_valid,input wire cmd_ready,
 output wire cmd_write,output wire [27:0] cmd_addr,
 output wire [255:0] cmd_wdata,output wire [31:0] cmd_wstrb,
 output wire cmd_write_block,output wire [2047:0]cmd_block_data,
 input wire rsp_valid,rsp_write
);
 localparam COUNT_BITS=FIFO_ADDR_BITS+3;

 wire common_rst_n=rst_n&&ui_rst_n;
 reg [1:0] source_release,ui_release;
 always @(posedge clk or negedge common_rst_n)
  if(!common_rst_n)source_release<=0;else source_release<={source_release[0],1'b1};
 always @(posedge ui_clk or negedge common_rst_n)
  if(!common_rst_n)ui_release<=0;else ui_release<={ui_release[0],1'b1};
 wire source_live=source_release[1],ui_live=ui_release[1];
 reg active,aborted,tiled_active;
 reg [27:0] frame_base;
 reg [23:0] expected_addr;
 reg[6:0]tile_row;reg[11:0]tile_column,tile_y_base;
 wire tile_row_final=(tile_row==127)||(tile_y_base+tile_row==OUT_H-1);
 reg [5:0] buffered;reg[31:0]epoch;
 reg [2047:0] pixels;
 
 reg [COUNT_BITS-1:0] owned;
 wire qfull,qempty,qvalid;
 wire [2107:0] qdata;
 wire afull,aempty,avalid;
 wire [32:0] adata;
 wire good_addr=(write_addr==expected_addr)&&(write_addr<OUT_W*OUT_H);
 wire closes=(buffered==63);
 assign write_ready=source_live&&active&&!aborted&&!fault&&!abort_frame&&!frame_start&&(!closes||!qfull);
 wire take=write_valid&&write_ready;
 wire enqueue=take&&good_addr&&closes;
 wire [2047:0] completed_pixels={8'b0,write_rgb,pixels[2015:0]};
 
 wire [27:0] beat_address=frame_base+{4'b0,write_addr[23:6],6'b0};
 assign drained=source_live&&(owned==0)&&(buffered==0);
 reg [2107:0] command_hold;reg hold_valid,read_pending,inflight;reg[31:0]inflight_epoch;
 wire qpop;
 burst64_async_fifo #(.WIDTH(2108),.ADDR_BITS(FIFO_ADDR_BITS)) command_fifo(
  .wr_clk(clk),.rd_clk(ui_clk),.rst_n(common_rst_n),.wr_en(enqueue),
  .wr_data({beat_address,epoch,completed_pixels}),.full(qfull),
  .rd_en(qpop),.rd_data(qdata),.rd_valid(qvalid),.empty(qempty));
 wire ack_push;
 burst64_async_fifo #(.WIDTH(33),.ADDR_BITS(FIFO_ADDR_BITS)) acknowledgement_fifo(
  .wr_clk(ui_clk),.rd_clk(clk),.rst_n(common_rst_n),.wr_en(ack_push),
  .wr_data({inflight?inflight_epoch:command_hold[2079:2048],!rsp_write}),.full(afull),.rd_en(!aempty),.rd_data(adata),.rd_valid(avalid),.empty(aempty));
 always @(posedge clk or negedge source_live) begin
  if(!source_live) begin
   active<=0;aborted<=1;tiled_active<=0;frame_base<=0;expected_addr<=0;tile_row<=0;tile_column<=0;tile_y_base<=0;buffered<=0;pixels<=0;owned<=0;fault<=0;epoch<=0;
  end else begin
   case({enqueue,avalid})
    2'b10:owned<=owned+1'b1;
    2'b01:if(owned!=0)owned<=owned-1'b1;
    default:owned<=owned;
   endcase
   if(avalid&&((owned==0)||adata[0]||adata[32:1]!=epoch))begin fault<=1;aborted<=1;buffered<=0;pixels<=0;end
   if(frame_start) begin
    if(drained) begin
     active<=1;aborted<=0;tiled_active<=TILED_ORDER&&frame_tiled;fault<=0;frame_base<=frame_bank?BASE1:BASE0;expected_addr<=0;tile_row<=0;tile_column<=0;tile_y_base<=0;epoch<=epoch+1;
    end else begin fault<=1;aborted<=1;buffered<=0;pixels<=0;end
   end
   if(take) begin
    if(!good_addr)begin fault<=1;aborted<=1;buffered<=0;pixels<=0;end
    else begin
     if(tiled_active&&closes&&write_addr[6])begin
      // A strict independent schedule checks every physical output address.
      // Data within each64-pixel burst remains contiguous and unchanged.
      if(!tile_row_final)begin expected_addr<=expected_addr+(OUT_W-127);tile_row<=tile_row+1'b1;end
      else begin
       tile_row<=0;
       if(tile_column==OUT_W/128-1)begin expected_addr<=expected_addr+1'b1;tile_column<=0;tile_y_base<=tile_y_base+12'd128;end
       else begin expected_addr<=expected_addr+1'b1-tile_row*OUT_W;tile_column<=tile_column+1'b1;end
      end
     end else expected_addr<=expected_addr+1'b1;
     if(closes)begin buffered<=0;pixels<=0;end
     else begin buffered<=buffered+1'b1;pixels[buffered*32+:32]<={8'b0,write_rgb};end
    end
   end
   if(abort_frame)begin aborted<=1;fault<=0;buffered<=0;pixels<=0;end
  end
 end
 // One outstanding UI transaction reserves one free acknowledgement slot.
 // Until its response, no other producer can consume that slot. The command
 // holding register is independent, so the following FIFO beat is prefetched.


 assign qpop=ui_live&&!hold_valid&&!read_pending&&!qempty;
 // This FIFO has one ACK producer and one outstanding command. Only
 // ack_push can consume the reserved slot; revoke the next-cycle grant
 // on that edge, including an issue with an immediate response.
 reg ack_slot_available;
 always @(posedge ui_clk or negedge ui_live)
  if(!ui_live)ack_slot_available<=0;
  else ack_slot_available<=!afull&&!ack_push;
 assign cmd_valid=ui_live&&hold_valid&&!inflight&&ack_slot_available;
 assign cmd_write=1'b1;
 assign cmd_addr=command_hold[2107:2080];
 assign cmd_wstrb=32'hffffffff;
 assign cmd_write_block=1'b1;assign cmd_block_data=command_hold[2047:0];
 assign cmd_wdata=command_hold[255:0];
 wire issue=cmd_valid&&cmd_ready;
 assign ack_push=ui_live&&rsp_valid&&(inflight||issue);
 always @(posedge ui_clk or negedge ui_live) begin
  if(!ui_live)begin command_hold<=0;hold_valid<=0;read_pending<=0;inflight<=0;inflight_epoch<=0;end
  else begin
   if(qpop)read_pending<=1;
   if(qvalid)begin command_hold<=qdata;hold_valid<=1;read_pending<=0;end
   if(issue)begin hold_valid<=0;inflight<=!rsp_valid;inflight_epoch<=command_hold[2079:2048];end
   if(rsp_valid&&inflight)inflight<=0;
  end
 end
 // synthesis translate_off
 initial begin
  if(OUT_W*OUT_H%64!=0)$fatal(1,"burst64 requires frame pixelcount divisible64");
  if(TILED_ORDER&&(OUT_W<128||OUT_W%128!=0||OUT_H<1))$fatal(1,"TILED_ORDER requires128-column tiles with clipped128-row bands");
  if(FIFO_ADDR_BITS<2)$fatal(1,"FIFO_ADDR_BITS must be >= 2");
  if(OUT_W*OUT_H<1||OUT_W*OUT_H>16777215)$fatal(1,"frame extent exceeds address range");
 end
 always @(posedge ui_clk)if(ui_live&&ack_push&&afull)$fatal(1,"ACK reservation violated");
 // synthesis translate_on
endmodule

// Gray-pointer dual-clock FIFO with registered RAM read and explicit valid.
module burst64_async_fifo #(parameter WIDTH=2108,ADDR_BITS=4)(
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



