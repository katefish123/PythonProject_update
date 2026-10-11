`timescale 1ns/1ps
// Three source frame slots. Aborted writes keep ownership until drained.
module ddr_frame_slots(input clk,rst_n,capture_start,write_complete,capture_abort,read_acquire,read_release,
 output reg capture_grant,capture_drop,writing,output reg [1:0] write_slot,
 output reg latest_valid,output reg [1:0] latest_slot,output reg [31:0] latest_frame_id,
 output reg read_locked,output reg [1:0] read_slot,output reg [31:0] read_frame_id);
reg write_failed;
reg [31:0] next_id;
reg free_found;
reg [1:0] free_slot;
integer i;
always @*begin
 free_found=0;free_slot=0;
 for(i=2;i>=0;i=i-1)begin
  if((!latest_valid || latest_slot!=i) && (!read_locked || read_slot!=i) && (!writing || write_slot!=i))begin
   free_found=1;free_slot=i;
  end
 end
end
always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
  capture_grant<=0;capture_drop<=0;writing<=0;write_slot<=0;write_failed<=0;
  latest_valid<=0;latest_slot<=0;latest_frame_id<=0;next_id<=1;
  read_locked<=0;read_slot<=0;read_frame_id<=0;
 end else begin
  capture_grant<=0;capture_drop<=0;
  if(read_release)read_locked<=0;
  // Acquire the latest frame visible before this edge, never a pending write.
  if(read_acquire && (!read_locked || read_release) && latest_valid)begin
   read_locked<=1;read_slot<=latest_slot;read_frame_id<=latest_frame_id;
  end
  if(writing)begin
   if(capture_abort)write_failed<=1;
   if(write_complete)begin
    writing<=0;write_failed<=0;
    if(!write_failed && !capture_abort)begin
     latest_valid<=1;latest_slot<=write_slot;latest_frame_id<=next_id;next_id<=next_id+1'b1;
    end
   end
  end
  // Conservative: a completion/release on this edge does not free a slot yet.
  if(capture_start)begin
   if(!writing && free_found && !capture_abort)begin
    writing<=1;write_slot<=free_slot;write_failed<=0;capture_grant<=1;
   end else capture_drop<=1;
  end
 end
end
endmodule
