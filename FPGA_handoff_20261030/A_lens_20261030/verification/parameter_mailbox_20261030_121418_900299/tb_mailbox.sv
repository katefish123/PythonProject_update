`timescale 1ns/1ps
module tb_mailbox;
 parameter integer D_PHASE_PS=1733;
 reg s_clk=0,d_clk=0,rst_n=0,s_valid=0,d_ready=0;
 reg[239:0]s_affine=0;reg[15:0]s_sequence=0;
 wire s_ready,s_commit_valid,d_valid;wire[15:0]s_commit_sequence,d_sequence;wire[239:0]d_affine;
 always #18.518 s_clk=~s_clk;
 initial begin #(D_PHASE_PS*0.001);forever #6.734 d_clk=~d_clk;end
 lens_parameter_mailbox dut(.*);
 reg[239:0]vectors[0:159],expected_affine[0:255];reg[15:0]seqs[0:159],expected_seq[0:255];
 integer submitted=0,consumed=0,committed=0,total_committed=0,source_cycles=0,dest_cycles=0;
 integer src_stalls=0,dest_stalls=0,app_pauses=0;reg pause_destination=0,random_ready=1;
 reg[31:0]rng=32'h6ad18372;reg[239:0]held_d;reg[15:0]held_d_seq;reg d_stalled=0;
 reg[239:0]preserved_affine;reg[15:0]preserved_seq;
 always @(negedge d_clk)begin
  rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  if(!rst_n||pause_destination)d_ready=0;
  else if(random_ready)d_ready=rng[2:0]==3'b011;
  else d_ready=1;
 end
 always @(posedge s_clk)begin
  if(!rst_n)begin submitted=0;committed=0;source_cycles=0;end
  else begin
   source_cycles=source_cycles+1;
   if(s_valid&&!s_ready)src_stalls=src_stalls+1;
   if(s_commit_valid)begin
    if(committed>=consumed)$fatal(1,"COMMIT_BEFORE_DESTINATION_CONSUMPTION");
    if(s_commit_sequence!==expected_seq[committed])$fatal(1,"COMMIT_SEQUENCE_MISMATCH expected=%h got=%h",expected_seq[committed],s_commit_sequence);
    committed=committed+1;total_committed=total_committed+1;
   end
   if(s_valid&&s_ready)begin
    expected_affine[submitted]=s_affine;expected_seq[submitted]=s_sequence;submitted=submitted+1;
   end
  end
 end
 always @(posedge d_clk)begin
  if(!rst_n)begin consumed=0;dest_cycles=0;d_stalled=0;end
  else begin
   dest_cycles=dest_cycles+1;
   if(d_stalled&&(!d_valid||d_affine!==held_d||d_sequence!==held_d_seq))$fatal(1,"PAYLOAD_TORE_UNDER_DESTINATION_BACKPRESSURE");
   d_stalled=d_valid&&!d_ready;held_d=d_affine;held_d_seq=d_sequence;
   if(d_valid&&!d_ready)dest_stalls=dest_stalls+1;
   if(d_valid&&d_ready)begin
    if(consumed>=submitted)$fatal(1,"DESTINATION_WITHOUT_SOURCE_TRANSACTION");
    if(d_affine!==expected_affine[consumed]||d_sequence!==expected_seq[consumed])$fatal(1,"ATOMIC_PAYLOAD_MISMATCH transaction=%0d",consumed);
    consumed=consumed+1;
   end
  end
 end
 task put(input[239:0]data,input[15:0]seq);
  integer t;
  begin
   @(negedge s_clk);s_valid=1;s_affine=data;s_sequence=seq;
   for(t=0;t<10000&&!s_ready;t=t+1)@(negedge s_clk);
   if(!s_ready)$fatal(1,"SOURCE_WAIT_TIMEOUT");
   @(posedge s_clk);@(negedge s_clk);
   // Source may immediately change all fields after its acceptance edge.
   s_valid=0;s_affine=~data;s_sequence=~seq;
  end
 endtask
 task drain;
  integer t;
  begin
   for(t=0;t<10000&&(committed!=submitted||consumed!=submitted||!s_ready);t=t+1)@(negedge s_clk);
   if(committed!=submitted||consumed!=submitted||!s_ready)$fatal(1,"DRAIN_TIMEOUT submitted=%0d consumed=%0d committed=%0d",submitted,consumed,committed);
  end
 endtask
 task shared_reset;
  begin
   @(negedge s_clk);rst_n=0;s_valid=0;pause_destination=1;
   repeat(7)@(negedge s_clk);rst_n=1;
   repeat(10)@(negedge s_clk);
   if(d_valid||s_commit_valid||submitted!=0||consumed!=0||committed!=0||!s_ready)$fatal(1,"RESET_LEAK");
   pause_destination=0;
  end
 endtask
 initial begin
  $readmemh("payload.hex",vectors);$readmemh("sequence.hex",seqs);
  repeat(5)@(negedge s_clk);rst_n=1;
  // 128 random/full-width transactions, immediately placing the next request
  // under source backpressure while the destination has not consumed the last.
  for(integer n=0;n<128;n=n+1)put(vectors[n],seqs[n]);drain();
  if(total_committed!=128)$fatal(1,"FIRST_BATCH_COUNT");
  preserved_affine=d_affine;preserved_seq=d_sequence;
  // Application-only reset is represented by stopping frame-boundary ready;
  // mailbox stays running. Last active parameters must survive the pause.
  pause_destination=1;app_pauses=app_pauses+1;
  repeat(500)@(negedge s_clk);
  if(d_affine!==preserved_affine||d_sequence!==preserved_seq)$fatal(1,"APPLICATION_PAUSE_LOST_PARAMETERS");
  put(vectors[128],seqs[128]);
  repeat(300)@(negedge s_clk);
  if(committed!=128||consumed!=128||!d_valid||s_ready)$fatal(1,"PAUSED_APPLICATION_CONSUMED");
  if(d_affine!==vectors[128]||d_sequence!==seqs[128])$fatal(1,"PAUSED_PENDING_PAYLOAD");
  pause_destination=0;drain();
  for(integer n=129;n<144;n=n+1)put(vectors[n],seqs[n]);drain();
  if(total_committed!=144)$fatal(1,"SECOND_BATCH_COUNT");
  // Cancel a fully captured but unconsumed transaction with the shared reset.
  pause_destination=1;put(vectors[144],seqs[144]);repeat(20)@(negedge s_clk);
  if(!d_valid||s_ready)$fatal(1,"CANCEL_FIXTURE_NOT_PENDING");
  shared_reset();repeat(200)@(negedge s_clk);
  if(total_committed!=144||d_valid||s_commit_valid)$fatal(1,"OLD_COMMIT_AFTER_RESET");
  random_ready=0;
  for(integer n=145;n<160;n=n+1)put(vectors[n],seqs[n]);drain();
  if(total_committed!=159||submitted!=15||consumed!=15||committed!=15)$fatal(1,"FINAL_COUNTS");
  if(src_stalls<100||dest_stalls<100)$fatal(1,"BACKPRESSURE_NOT_EXERCISED");
  $display("PARAMETER_MAILBOX_PASS phase_ps=%0d committed=%0d random_payload_bits=240 source_stall_cycles=%0d destination_stall_cycles=%0d application_pause=%0d shared_reset_cancel=1 next_input_changed=1 sequence_wrap=1",D_PHASE_PS,total_committed,src_stalls,dest_stalls,app_pauses);$finish;
 end
 initial begin #30000000;$fatal(1,"MAILBOX_TEST_TIMEOUT");end
endmodule
