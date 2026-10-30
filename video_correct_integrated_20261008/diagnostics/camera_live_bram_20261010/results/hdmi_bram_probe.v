`timescale 1ns/1ps
// Diagnostic double-buffered downsample, independent read/write clocks.
module hdmi_bram_probe #(parameter SAMPLE_STEP=6,FRAME_WORDS=57600,FRAME_GAP=16384,STALE_FRAME_LIMIT=120)(
 input wr_clk,wr_reset_n,de,input [23:0] pixel,
 input rd_clk,rd_reset_n,frame_start,rd_enable,input [15:0] rd_addr,
 output reg [23:0] rd_pixel,output reg frame_valid,output [15:0] samples_written,output [2:0] writer_flags);
reg [23:0] memory [0:FRAME_WORDS*2-1];
reg [15:0] write_addr;
reg [14:0] gap;
reg [3:0] x_mod,y_mod;
reg de_previous,capture_enable,write_bank,pending,ready_toggle,ready_bank;
reg acknowledge,ack_meta,ack_sync;
reg ready_meta,ready_sync,bank_meta,bank_sync,read_bank;
// Count output frame boundaries, so a stopped RX clock cannot freeze validity.
// At 60 Hz the default expires after approximately two seconds without a new frame.
localparam AGE_WIDTH=(STALE_FRAME_LIMIT<2) ? 1 : $clog2(STALE_FRAME_LIMIT+1);
reg [AGE_WIDTH-1:0] frame_age;
assign samples_written=write_addr;
assign writer_flags={pending,capture_enable,write_bank};
wire write_enable=capture_enable && de && x_mod==0 && y_mod==0 && write_addr<FRAME_WORDS;
wire [16:0] memory_write_addr=write_addr+(write_bank ? FRAME_WORDS : 0);
wire [16:0] memory_read_addr=rd_addr+(read_bank ? FRAME_WORDS : 0);
always @(posedge wr_clk)if(write_enable)memory[memory_write_addr]<=pixel;
always @(posedge wr_clk or negedge wr_reset_n)begin
 if(!wr_reset_n)begin
  write_addr<=0;gap<=0;x_mod<=0;y_mod<=0;de_previous<=0;capture_enable<=0;
  write_bank<=0;pending<=0;ready_toggle<=0;ready_bank<=0;ack_meta<=0;ack_sync<=0;
 end else begin
  ack_meta<=acknowledge;ack_sync<=ack_meta;de_previous<=de;
  if(de)begin gap<=0;x_mod<=(x_mod==SAMPLE_STEP-1) ? 0 : x_mod+1'b1;end
  else begin
   x_mod<=0;if(gap!=32767)gap<=gap+1'b1;
   if(de_previous)y_mod<=(y_mod==SAMPLE_STEP-1) ? 0 : y_mod+1'b1;
   if(gap>=FRAME_GAP)begin
    y_mod<=0;write_addr<=0;
    if(!pending)capture_enable<=1;
    else if(ack_sync==ready_toggle)begin pending<=0;write_bank<=!write_bank;capture_enable<=1;end
   end
  end
  if(write_enable)begin
   write_addr<=write_addr+1'b1;
   if(write_addr==FRAME_WORDS-1)begin
    ready_bank<=write_bank;ready_toggle<=!ready_toggle;pending<=1;capture_enable<=0;
   end
  end
 end
end
always @(posedge rd_clk or negedge rd_reset_n)begin
 if(!rd_reset_n)begin
  ready_meta<=0;ready_sync<=0;bank_meta<=0;bank_sync<=0;acknowledge<=0;read_bank<=1;frame_valid<=0;frame_age<=0;
 end else begin
  ready_meta<=ready_toggle;ready_sync<=ready_meta;bank_meta<=ready_bank;bank_sync<=bank_meta;
  if(frame_start && ready_sync!=acknowledge)begin
   read_bank<=bank_sync;frame_valid<=1;acknowledge<=ready_sync;frame_age<=0;
  end else if(frame_start && frame_valid && STALE_FRAME_LIMIT>0)begin
   if(frame_age>=STALE_FRAME_LIMIT-1)begin frame_valid<=0;frame_age<=0;end
   else frame_age<=frame_age+1'b1;
  end
 end
end
always @(posedge rd_clk)begin
 if(rd_enable && frame_valid && rd_addr<FRAME_WORDS)rd_pixel<=memory[memory_read_addr];
 else rd_pixel<=0;
end
endmodule
