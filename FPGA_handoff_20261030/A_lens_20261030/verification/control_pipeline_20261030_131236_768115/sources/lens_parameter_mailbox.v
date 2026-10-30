`timescale 1ns/1ps
`default_nettype none
// One outstanding source transaction. Source payload remains stable until
// destination frame-boundary consumption returns the acknowledgement toggle.
// Both domains share this public reset; application/DDR recovery does not
// reset this mailbox, so its last affine parameters survive recovery.
module lens_parameter_mailbox(
 input wire s_clk,d_clk,rst_n,
 input wire s_valid,output wire s_ready,input wire[239:0]s_affine,input wire[15:0]s_sequence,
 output reg s_commit_valid,output reg[15:0]s_commit_sequence,
 output reg d_valid,input wire d_ready,output reg[239:0]d_affine,output reg[15:0]d_sequence
);
 localparam[239:0]DEFAULT_AFFINE={40'sh0006000000,40'sh0000fe56d6,40'sh0000000000,40'sh0008b988e6,40'sh0000000000,40'sh0000fe56d6};
 reg[1:0]s_release,d_release;
 always @(posedge s_clk or negedge rst_n)if(!rst_n)s_release<=0;else s_release<={s_release[0],1'b1};
 always @(posedge d_clk or negedge rst_n)if(!rst_n)d_release<=0;else d_release<={d_release[0],1'b1};
 wire s_live=s_release[1],d_live=d_release[1];
 reg request_toggle,ack_toggle,ack_seen;
 reg[239:0]payload_affine;reg[15:0]payload_sequence;
 (* ASYNC_REG="TRUE" *)reg[1:0]request_sync,ack_sync;
 assign s_ready=s_live&&(request_toggle==ack_sync[1]);
 always @(posedge s_clk or negedge s_live)begin
  if(!s_live)begin request_toggle<=0;ack_sync<=0;ack_seen<=0;payload_affine<=DEFAULT_AFFINE;payload_sequence<=0;s_commit_valid<=0;s_commit_sequence<=0;end
  else begin
   ack_sync<={ack_sync[0],ack_toggle};s_commit_valid<=0;
   if(s_valid&&s_ready)begin payload_affine<=s_affine;payload_sequence<=s_sequence;request_toggle<=!request_toggle;end
   if(ack_sync[1]!=ack_seen)begin ack_seen<=ack_sync[1];s_commit_valid<=1;s_commit_sequence<=payload_sequence;end
  end
 end
 always @(posedge d_clk or negedge d_live)begin
  if(!d_live)begin request_sync<=0;ack_toggle<=0;d_valid<=0;d_affine<=DEFAULT_AFFINE;d_sequence<=0;end
  else begin
   request_sync<={request_sync[0],request_toggle};
   if(!d_valid&&request_sync[1]!=ack_toggle)begin d_affine<=payload_affine;d_sequence<=payload_sequence;d_valid<=1;end
   if(d_valid&&d_ready)begin d_valid<=0;ack_toggle<=request_sync[1];end
  end
 end
endmodule
`default_nettype wire