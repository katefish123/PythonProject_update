`timescale 1ns/1ps
`default_nettype none
// Join independent RX geometry and UI write-drain completions in proc domain.
// A per-bank token alone is insufficient: alternating banks reuse that token.
module geometry_frame_join(
 input wire clk,rst_n,request_toggle,request_bank,
 input wire writer_complete,writer_ok,metadata_toggle,metadata_token,metadata_bank,metadata_ok,
 input wire [95:0] metadata_corners,
 output reg complete_toggle,capture_ok,
 output reg [95:0] corners0,corners1,output reg valid0,valid1
);
 (* ASYNC_REG="TRUE" *) reg [2:0] writer_sync,ok_sync,metadata_sync;
 reg request_seen,metadata_seen,metadata_ready,geometry_good;
 reg writer_seen,writer_ready,writer_good;
 reg [1:0] writer_settle;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   writer_sync<=0;ok_sync<=0;metadata_sync<=0;request_seen<=0;metadata_seen<=0;
   metadata_ready<=0;geometry_good<=0;complete_toggle<=0;capture_ok<=0;
   corners0<=0;corners1<=0;valid0<=0;valid1<=0;
   writer_seen<=0;writer_ready<=0;writer_good<=0;writer_settle<=0;
  end else begin
   writer_sync<={writer_sync[1:0],writer_complete};ok_sync<={ok_sync[1:0],writer_ok};
   metadata_sync<={metadata_sync[1:0],metadata_toggle};
   if(request_toggle!=request_seen)begin
    request_seen<=request_toggle;metadata_ready<=0;geometry_good<=0;writer_ready<=0;
    if(request_bank)valid1<=0;else valid0<=0;
   end
   // Completion protects a held status payload, but its independent status
   // synchronizer can trail the event. Wait two additional destination edges
   // before freezing that payload. Writer holds it until the next request.
   if(writer_sync[2]!=writer_seen)begin
    writer_seen<=writer_sync[2];writer_ready<=0;writer_settle<=2;
   end else if(writer_settle!=0)begin
    writer_settle<=writer_settle-1'b1;
    if(writer_settle==1)begin writer_good<=ok_sync[2];writer_ready<=1;end
   end
   if(metadata_sync[2]!=metadata_seen)begin
    metadata_seen<=metadata_sync[2];
    if(metadata_token==request_toggle && complete_toggle!=request_toggle)begin
     metadata_ready<=1;geometry_good<=metadata_ok&&(metadata_bank==request_bank);
     if(metadata_bank==request_bank)begin
      if(request_bank)begin corners1<=metadata_corners;valid1<=metadata_ok;end
      else begin corners0<=metadata_corners;valid0<=metadata_ok;end
     end
    end
   end
   if(request_seen==request_toggle && complete_toggle!=request_toggle && writer_seen==request_toggle && writer_ready)begin
    if(!writer_good||metadata_ready)begin
     complete_toggle<=request_toggle;capture_ok<=writer_good&&geometry_good;
     if(!writer_good||!geometry_good)begin
      if(request_bank)valid1<=0;else valid0<=0;
     end
    end
   end
  end
 end
endmodule
`default_nettype wire
