`timescale 1ns/1ps
`default_nettype none
// Proc-domain two-slot join/ownership manager. No source credit is returned
// before terminal writer ACKs and immutable geometry have both retired.
module continuous_capture_manager #(parameter PROC_CYCLES_PER_MS=54000)(
 input wire clk,rst_n,
 input wire allocation_valid,output wire allocation_ready,input wire[32:0]allocation_data,
 input wire terminal_valid,output wire terminal_ready,input wire[37:0]terminal_data,
 input wire metadata_valid,output wire metadata_ready,input wire[129:0]metadata_data,
 output wire frame_valid,input wire frame_ready,output wire frame_bank,
 output wire[31:0]frame_generation,output wire[95:0]frame_corners,output wire frame_geometry_valid,
 output wire[31:0]frame_capture_ms,output wire[511:0]reject_reason_counts,
 input wire release_valid,release_bank,input wire[31:0]release_generation,
 output wire return_valid,input wire return_ready,output wire[32:0]return_data,
 output reg[31:0]rejected_frames,output reg[3:0]last_failure_reason,output reg fault
);
 localparam FREE=0,WAIT_JOIN=1,READY=2,LOCKED=3,RETURNING=4;
 reg[2:0]state[0:1];reg[31:0]generation[0:1];reg[95:0]corners[0:1];
 localparam MS_BITS=PROC_CYCLES_PER_MS<2?1:$clog2(PROC_CYCLES_PER_MS);
 reg[MS_BITS-1:0]ms_prescaler;reg[31:0]now_ms,capture_ms[0:1],reason_count[0:15];
 reg[1:0]writer_seen,writer_good,geometry_seen,geometry_good;reg[3:0]writer_reason[0:1];
 reg descriptor_valid,descriptor_bank;
 wire reject0=state[0]==WAIT_JOIN&&writer_seen[0]&&geometry_seen[0]&&!(writer_good[0]&&geometry_good[0]);
 wire reject1=state[1]==WAIT_JOIN&&writer_seen[1]&&geometry_seen[1]&&!(writer_good[1]&&geometry_good[1]);
 wire[3:0]reject_reason0=!writer_good[0]?(writer_reason[0]!=0?writer_reason[0]:4'd12):4'd3;
 wire[3:0]reject_reason1=!writer_good[1]?(writer_reason[1]!=0?writer_reason[1]:4'd12):4'd3;
 wire ab=allocation_data[32];wire[31:0]ag=allocation_data[31:0];
 wire tb=terminal_data[37];wire[31:0]tg=terminal_data[36:5];
 wire mb=metadata_data[129];wire[31:0]mg=metadata_data[128:97];
 assign allocation_ready=1'b1;
 // Metadata can precede BEGIN when the RX->UI data FIFO is backpressured.
 // Retain that future-generation result until its authoritative allocation.
 assign terminal_ready=state[tb]!=FREE||$signed(tg-generation[tb])<=0;
 assign metadata_ready=state[mb]!=FREE||$signed(mg-generation[mb])<=0;
 assign frame_valid=rst_n&&descriptor_valid;assign frame_bank=descriptor_bank;
 assign frame_generation=generation[descriptor_bank];assign frame_corners=corners[descriptor_bank];assign frame_geometry_valid=frame_valid;
 assign frame_capture_ms=capture_ms[descriptor_bank];
 genvar reason_n;
 generate for(reason_n=0;reason_n<16;reason_n=reason_n+1)begin: reason_counts
 assign reject_reason_counts[reason_n*32+:32]=reason_count[reason_n];
 end endgenerate
 wire rb=state[0]!=RETURNING;
 assign return_valid=rst_n&&(state[0]==RETURNING||state[1]==RETURNING);
 assign return_data={rb,generation[rb]};
 integer i,reason_i;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 state[0]<=FREE;state[1]<=FREE;generation[0]<=0;generation[1]<=0;corners[0]<=0;corners[1]<=0;writer_seen<=0;writer_good<=0;geometry_seen<=0;geometry_good<=0;writer_reason[0]<=0;writer_reason[1]<=0;
 descriptor_valid<=0;descriptor_bank<=0;rejected_frames<=0;last_failure_reason<=0;fault<=0;
 ms_prescaler<=0;now_ms<=0;capture_ms[0]<=0;capture_ms[1]<=0;
 for(reason_i=0;reason_i<16;reason_i=reason_i+1)reason_count[reason_i]<=0;
 end else begin
 if(ms_prescaler==PROC_CYCLES_PER_MS-1)begin ms_prescaler<=0;now_ms<=now_ms+1'b1;end
 else ms_prescaler<=ms_prescaler+1'b1;
 if(reject0||reject1)rejected_frames<=rejected_frames+{31'd0,reject0}+{31'd0,reject1};
 for(reason_i=0;reason_i<16;reason_i=reason_i+1)
 if((reject0&&reject_reason0==reason_i)||(reject1&&reject_reason1==reason_i))
 reason_count[reason_i]<=reason_count[reason_i]+{31'd0,reject0&&reject_reason0==reason_i}+{31'd0,reject1&&reject_reason1==reason_i};
 if(return_valid&&return_ready)state[rb]<=FREE;
 if(allocation_valid)begin
 if(state[ab]!=FREE)fault<=1;
 else begin state[ab]<=WAIT_JOIN;generation[ab]<=ag;capture_ms[ab]<=now_ms;corners[ab]<=0;writer_seen[ab]<=0;writer_good[ab]<=0;geometry_seen[ab]<=0;geometry_good[ab]<=0;writer_reason[ab]<=0;end
 end
 if(terminal_valid&&terminal_ready)begin
 if(state[tb]!=WAIT_JOIN||generation[tb]!=tg||writer_seen[tb])fault<=1;
 else begin writer_seen[tb]<=1;writer_good[tb]<=terminal_data[4];writer_reason[tb]<=terminal_data[3:0];end
 end
 if(metadata_valid&&metadata_ready)begin
 if(state[mb]!=WAIT_JOIN||generation[mb]!=mg||geometry_seen[mb])fault<=1;
 else begin geometry_seen[mb]<=1;geometry_good[mb]<=metadata_data[96];corners[mb]<=metadata_data[95:0];end
 end
 for(i=0;i<2;i=i+1)if(state[i]==WAIT_JOIN&&writer_seen[i]&&geometry_seen[i])begin
 if(writer_good[i]&&geometry_good[i])state[i]<=READY;
 else begin state[i]<=RETURNING;last_failure_reason<=!writer_good[i]?(writer_reason[i]!=0?writer_reason[i]:4'd12):4'd3;end
 end
 if(!descriptor_valid)begin
 if(state[0]==READY||state[1]==READY)begin
 descriptor_valid<=1;
 if(state[0]==READY&&state[1]==READY)descriptor_bank<=$signed(generation[0]-generation[1])>=0;
 else descriptor_bank<=state[0]!=READY;
 end
 end else if(frame_ready)begin descriptor_valid<=0;state[descriptor_bank]<=LOCKED;end
 if(release_valid)begin
 if(state[release_bank]!=LOCKED||generation[release_bank]!=release_generation)fault<=1;
 else state[release_bank]<=RETURNING;
 end
 end end
endmodule
`default_nettype wire
