`timescale 1ns/1ps
`default_nettype none
// Observation only. No command, protection, abort, credit or reset outputs.
// rst_n must assert in BOTH clock domains together. UI inputs are UI-owned.
// proc_source_fault is an opaque raw four-bit source diagnostic, not a label.
module fault_diagnostics_stream #(parameter integer TICK_BITS=48)(
 input wire proc_clk,ui_clk,rst_n,
 input wire ui_engine_fault,input wire[3:0]ui_engine_reason,
 input wire ui_phy_fail,ui_align_error,ui_self_fail,
 input wire[3:0]ui_stage,ui_dqs_valid,proc_source_fault,
 output wire current_fault_any,
 output reg[4:0]current_mask,output reg[2:0]current_kind,
 output reg[3:0]current_raw_reason,current_engine_reason,current_source_fault,
 output reg[TICK_BITS-1:0]current_ui_tick,current_source_proc_tick,current_source_received_ui_tick,
 output reg[3:0]current_ui_stage,current_dqs_valid,
 output reg source_snapshot_valid,
 output reg first_valid,output reg[4:0]first_mask,output reg[2:0]first_kind,
 output reg[3:0]first_raw_reason,first_engine_reason,first_source_fault,
 output reg[TICK_BITS-1:0]first_ui_tick,first_source_proc_tick,
 output reg[3:0]first_ui_stage,first_dqs_valid,
 output reg source_first_valid,output reg[3:0]source_first_fault,
 output reg[TICK_BITS-1:0]source_first_proc_tick,source_first_received_ui_tick
);
 localparam integer PAYLOAD_BITS=9+2*TICK_BITS;
 localparam[2:0]NONE=0,SOURCE=1,ENGINE=2,PHY=3,ALIGN=4,SELF=5;
 (* ASYNC_REG="TRUE" *)reg[1:0]proc_reset_pipe,ui_reset_pipe;
 always @(posedge proc_clk or negedge rst_n)
  if(!rst_n)proc_reset_pipe<=0;else proc_reset_pipe<={proc_reset_pipe[0],1'b1};
 always @(posedge ui_clk or negedge rst_n)
  if(!rst_n)ui_reset_pipe<=0;else ui_reset_pipe<={ui_reset_pipe[0],1'b1};
 wire proc_local_rst_n=proc_reset_pipe[1],ui_local_rst_n=ui_reset_pipe[1];
 reg[TICK_BITS-1:0]proc_tick,ui_tick;
 reg proc_first_valid;reg[3:0]proc_first_fault;reg[TICK_BITS-1:0]proc_first_tick;
 reg[PAYLOAD_BITS-1:0]mailbox_hold;
 reg proc_request,ui_ack;
 (* ASYNC_REG="TRUE" *)reg[1:0]proc_ack_sync,ui_request_sync;
 wire next_first_valid=proc_first_valid||(|proc_source_fault);
 wire[3:0]next_first_fault=proc_first_valid?proc_first_fault:proc_source_fault;
 wire[TICK_BITS-1:0]next_first_tick=proc_first_valid?proc_first_tick:proc_tick;
 always @(posedge proc_clk or negedge proc_local_rst_n)begin
  if(!proc_local_rst_n)begin
   proc_tick<=0;proc_first_valid<=0;proc_first_fault<=0;proc_first_tick<=0;
   mailbox_hold<=0;proc_request<=0;proc_ack_sync<=0;
  end else begin
   proc_tick<=proc_tick+1'b1;proc_ack_sync<={proc_ack_sync[0],ui_ack};
   // Capture the first source pulse independently of mailbox availability.
   if(!proc_first_valid&&|proc_source_fault)begin
    proc_first_valid<=1;proc_first_fault<=proc_source_fault;proc_first_tick<=proc_tick;
   end
   // Refresh at every completed handshake. Intermediate later source levels
   // may coalesce; the persistent first-source record cannot be lost.
   if(proc_request==proc_ack_sync[1])begin
    mailbox_hold<={proc_source_fault,proc_tick,next_first_valid,next_first_fault,next_first_tick};
    proc_request<=~proc_request;
   end
  end
 end
 wire source_update=ui_request_sync[1]!=ui_ack;
 wire[TICK_BITS-1:0]mail_first_tick=mailbox_hold[TICK_BITS-1:0];
 wire[3:0]mail_first_fault=mailbox_hold[TICK_BITS+:4];
 wire mail_first_valid=mailbox_hold[TICK_BITS+4];
 wire[TICK_BITS-1:0]mail_proc_tick=mailbox_hold[TICK_BITS+5+:TICK_BITS];
 wire[3:0]mail_source=mailbox_hold[2*TICK_BITS+5+:4];
 wire[3:0]sample_source=source_update?mail_source:current_source_fault;
 wire[TICK_BITS-1:0]sample_proc_tick=source_update?mail_proc_tick:current_source_proc_tick;
 wire new_source_first=source_update&&mail_first_valid&&!source_first_valid;
 // Bits 0..4: source, engine, PHY, ALIGN, self-test. Preserve simultaneous causes.
 wire[4:0]sample_mask={ui_self_fail,ui_align_error,ui_phy_fail,ui_engine_fault,|sample_source};
 // A first-source pulse can arrive in history after current source is clear.
 // This affects history only, never the current fault/LED selection.
 wire[4:0]event_mask=sample_mask|{4'd0,new_source_first};
 wire[3:0]event_source=|sample_source?sample_source:new_source_first?mail_first_fault:4'd0;
 wire[TICK_BITS-1:0]event_source_tick=|sample_source?sample_proc_tick:mail_first_tick;
 function[2:0]choose_kind(input[4:0]mask);
  begin
   if(mask[0])choose_kind=SOURCE;else if(mask[1])choose_kind=ENGINE;
   else if(mask[2])choose_kind=PHY;else if(mask[3])choose_kind=ALIGN;
   else if(mask[4])choose_kind=SELF;else choose_kind=NONE;
  end
 endfunction
 assign current_fault_any=|current_mask;
 always @(posedge ui_clk or negedge ui_local_rst_n)begin
  if(!ui_local_rst_n)begin
   ui_tick<=0;ui_ack<=0;ui_request_sync<=0;source_snapshot_valid<=0;
   current_mask<=0;current_kind<=NONE;current_raw_reason<=0;current_engine_reason<=0;current_source_fault<=0;
   current_ui_tick<=0;current_source_proc_tick<=0;current_source_received_ui_tick<=0;current_ui_stage<=0;current_dqs_valid<=0;
   first_valid<=0;first_mask<=0;first_kind<=NONE;first_raw_reason<=0;first_engine_reason<=0;first_source_fault<=0;
   first_ui_tick<=0;first_source_proc_tick<=0;first_ui_stage<=0;first_dqs_valid<=0;
   source_first_valid<=0;source_first_fault<=0;source_first_proc_tick<=0;source_first_received_ui_tick<=0;
  end else begin
   ui_tick<=ui_tick+1'b1;ui_request_sync<={ui_request_sync[0],proc_request};
   current_mask<=sample_mask;current_kind<=choose_kind(sample_mask);
   current_raw_reason<=|sample_source?sample_source:ui_engine_fault?ui_engine_reason:4'd0;
   current_engine_reason<=ui_engine_fault?ui_engine_reason:4'd0;
   current_source_fault<=sample_source;current_ui_tick<=ui_tick;
   current_source_proc_tick<=sample_proc_tick;current_ui_stage<=ui_stage;current_dqs_valid<=ui_dqs_valid;
   if(source_update)begin
    ui_ack<=ui_request_sync[1];source_snapshot_valid<=1;current_source_received_ui_tick<=ui_tick;
    if(mail_first_valid&&!source_first_valid)begin
     source_first_valid<=1;source_first_fault<=mail_first_fault;
     source_first_proc_tick<=mail_first_tick;source_first_received_ui_tick<=ui_tick;
    end
   end
   // FIRST OBSERVED means this UI sampling order, not a physical ordering
   // comparison between unrelated proc/UI timestamp counters.
   if(!first_valid&&|event_mask)begin
    first_valid<=1;first_mask<=event_mask;first_kind<=choose_kind(event_mask);
    first_raw_reason<=event_mask[0]?event_source:ui_engine_fault?ui_engine_reason:4'd0;
    first_engine_reason<=ui_engine_fault?ui_engine_reason:4'd0;first_source_fault<=event_source;
    first_ui_tick<=ui_tick;first_source_proc_tick<=event_mask[0]?event_source_tick:{TICK_BITS{1'b0}};
    first_ui_stage<=ui_stage;first_dqs_valid<=ui_dqs_valid;
   end
  end
 end
 // synthesis translate_off
 initial if(TICK_BITS<1)$fatal(1,"TICK_BITS must be positive");
 // synthesis translate_on
endmodule
`default_nettype wire
