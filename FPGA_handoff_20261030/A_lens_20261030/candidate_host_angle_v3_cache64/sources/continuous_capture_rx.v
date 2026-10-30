`timescale 1ns/1ps
`default_nettype none
// Two native-resolution source banks. END and next BEGIN share one VS edge.
// Queue reserves four of eight entries for control records, so terminal events
// survive downstream FIFO-full indefinitely. A bank remains owned until credit.
module continuous_capture_rx #(
 parameter IN_W=1920,IN_H=1080,SRC_W=1920,SRC_H=1080
)(
 input wire clk,rst_n,enabled,rx_vs,rx_de,input wire[23:0]rx_rgb,
 input wire release_valid,release_bank,input wire[31:0]release_generation,
 output wire packet_valid,input wire packet_ready,output wire[319:0]packet_data,
 output wire sample_valid,sample_first,output wire[11:0]sample_x,sample_y,
 output wire sample_bank,output wire[31:0]sample_generation,
 output reg close_valid,close_bank,close_ok,output reg[31:0]close_generation,output reg[3:0]close_reason,
 output reg[31:0]dropped_frames,admitted_frames,output reg fault,
 output wire[1:0]owned_banks
);
 localparam[1:0]BEGIN_FRAME=0,PIXEL_DATA=1,END_FRAME=2;
 reg vs_d,de_d,active,bank,frame_bad,overflow;
 (* ASYNC_REG="TRUE" *)reg[2:0]enabled_sync;
 reg[31:0]generation,bank_generation[0:1];reg[1:0]used;
 reg[12:0]x_count,y_count;reg[23:0]sampled,word_addr;
 reg[2:0]pack_count;reg[255:0]pixel_pack;
 reg[319:0]queue[0:7];reg[2:0]head,tail;reg[3:0]count;
 wire pop=packet_valid&&packet_ready;
 wire vs_rise=rx_vs&&!vs_d;
 // Validate credits before they can drive the wide packet queue controls.
 // Suppress a duplicate while its accepted credit is still in this stage;
 // otherwise a duplicate coincident with reallocation could free the new owner.
 reg credit_return0,credit_return1,credit_bad;
 wire match0=release_valid&&!release_bank&&used[0]&&!credit_return0&&bank_generation[0]==release_generation&&(!active||bank);
 wire match1=release_valid&&release_bank&&used[1]&&!credit_return1&&bank_generation[1]==release_generation&&(!active||!bank);
 wire free0=!used[0]||credit_return0;
 wire free1=!used[1]||credit_return1;
 wire allocate=vs_rise&&enabled_sync[2]&&(free0||free1);
 wire next_bank=!free0;
 wire good_end=!frame_bad&&!overflow&&y_count==IN_H&&x_count==0&&!rx_de&&sampled==SRC_W*SRC_H&&pack_count==0;
 wire[3:0]end_reason=overflow?4'd13:!good_end?4'd12:4'd0;
 assign owned_banks=used;
 assign packet_valid=rst_n&&count!=0;
 assign packet_data=queue[head];
 assign sample_valid=active&&!vs_rise&&rx_de&&x_count<IN_W&&y_count<IN_H;
 assign sample_first=sample_valid&&sampled==0;
 assign sample_x=x_count[11:0];assign sample_y=y_count[11:0];
 assign sample_bank=bank;assign sample_generation=generation;
 wire[255:0]assembled=pixel_pack|({232'd0,rx_rgb}<<(pack_count*32));
 wire data_due=sample_valid&&pack_count==7&&!frame_bad&&!overflow;
 wire data_space=(count-(pop?1:0))<4;
 wire[1:0]push_count=vs_rise?({1'b0,active}+{1'b0,allocate}):(data_due&&data_space?2'd1:2'd0);
 wire[319:0]end_packet={END_FRAME,bank,generation,word_addr,good_end,end_reason,256'd0};
 wire[319:0]begin_packet={BEGIN_FRAME,next_bank,generation+32'd1,24'd0,1'b1,4'd0,256'd0};
 wire[319:0]data_packet={PIXEL_DATA,bank,generation,word_addr,1'b1,4'd0,assembled};
 // Each physical slot has a static write port. This avoids sharing an
 // indexed old-word feedback mux across the entire eight-word queue.
 // The speculative primary write and second BEGIN write keep their original
 // enables and priority; queue storage holds its contents throughout reset.
 wire[2:0]second_tail_slot=tail+3'd1;
 wire[319:0]primary_queue_word=vs_rise?(active?end_packet:begin_packet):data_packet;
 genvar queue_slot;
 generate for(queue_slot=0;queue_slot<8;queue_slot=queue_slot+1)begin: local_queue_write
  localparam[2:0]SLOT=queue_slot;
  always @(posedge clk)begin
   if(rst_n)begin
    if((count<8||pop)&&tail==SLOT)queue[queue_slot]<=primary_queue_word;
    // Deliberately independent of the primary-write enable, as before.
    if(push_count==2&&second_tail_slot==SLOT)queue[queue_slot]<=begin_packet;
   end
  end
 end endgenerate
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 credit_return0<=0;credit_return1<=0;credit_bad<=0;vs_d<=0;de_d<=0;enabled_sync<=0;active<=0;bank<=0;frame_bad<=0;overflow<=0;generation<=0;bank_generation[0]<=0;bank_generation[1]<=0;used<=0;
 x_count<=0;y_count<=0;sampled<=0;word_addr<=0;pack_count<=0;pixel_pack<=0;head<=0;tail<=0;count<=0;
 close_valid<=0;close_bank<=0;close_ok<=0;close_generation<=0;close_reason<=0;dropped_frames<=0;admitted_frames<=0;fault<=0;
 end else begin
 credit_return0<=match0;credit_return1<=match1;credit_bad<=release_valid&&!(match0||match1);
 vs_d<=rx_vs;de_d<=rx_de;enabled_sync<={enabled_sync[1:0],enabled};close_valid<=0;
 if(pop)head<=head+1'b1;
 count<=count+push_count-(pop?1'b1:1'b0);
 if(push_count!=0)tail<=tail+push_count;
 if(credit_return0)used[0]<=0;
 if(credit_return1)used[1]<=0;
 if(credit_bad)fault<=1;
 if(vs_rise)begin
 active<=0;
 if(active)begin close_valid<=1;close_bank<=bank;close_generation<=generation;close_ok<=good_end;close_reason<=end_reason;end
 if(allocate)begin
 active<=1;bank<=next_bank;generation<=generation+1'b1;used[next_bank]<=1;bank_generation[next_bank]<=generation+1'b1;
 frame_bad<=rx_de;overflow<=0;x_count<=0;y_count<=0;sampled<=0;word_addr<=0;pack_count<=0;pixel_pack<=0;
 admitted_frames<=admitted_frames+1'b1;
 end else if(enabled_sync[2])dropped_frames<=dropped_frames+1'b1;
 end else if(active)begin
 if(rx_de)begin
 if(x_count>=IN_W||y_count>=IN_H)frame_bad<=1;
 if(x_count!=13'h1fff)x_count<=x_count+1'b1;
 if(sample_valid)begin
 sampled<=sampled+1'b1;
 if(pack_count==7)begin
 if(data_due&&!data_space)overflow<=1;
 word_addr<=word_addr+24'd8;pack_count<=0;pixel_pack<=0;
 end else begin pixel_pack<=assembled;pack_count<=pack_count+1'b1;end
 end
 end
 if(de_d&&!rx_de)begin
 if(x_count!=IN_W||y_count>=IN_H)frame_bad<=1;
 if(y_count!=13'h1fff)y_count<=y_count+1'b1;
 x_count<=0;
 end
 end
 end end
 // synthesis translate_off
 initial if(IN_W!=SRC_W||IN_H!=SRC_H||SRC_W%8!=0)$fatal(1,"continuous RX requires native source and width divisible8");
 always @(posedge clk)if(rst_n&&(count>8||count+push_count-(pop?1:0)>8))$fatal(1,"reserved terminal queue overflow");
 // synthesis translate_on
endmodule
`default_nettype wire

