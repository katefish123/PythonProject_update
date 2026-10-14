`timescale 1ns/1ps
`default_nettype none
// Owns one immutable source snapshot and two destination banks. Only complete
// results are published. A failed frame leaves the displayed bank untouched.
module frame_session #(
    parameter CAPTURE_TIMEOUT=54000000,
    parameter RETRY_CYCLES=270000,
    parameter RESET_CYCLES=8
)(
    input wire clk,rst_n,enabled,
    output reg capture_request,
    input wire capture_complete,capture_ok,
    output reg processor_start,
    output wire processor_reset_n,
    input wire processor_done,processor_error,
    output reg write_bank,publish_toggle,
    output wire publish_bank,
    input wire display_ack,
    output reg frame_error,input_wait,
    output wire working,
    output reg [31:0] good_frames,rejected_frames
);
    localparam WAIT_ENABLE=0,REQUEST=1,CAP_WAIT=2,CAP_SETTLE=3,
        START_PROCESS=4,PROCESS=5,PUBLISH=6,DISPLAY_WAIT=7,RETRY=8,CLEAR=9;
    reg [3:0] state;
    reg [31:0] timer;
    (* ASYNC_REG="TRUE" *) reg [2:0] complete_sync,ok_sync,ack_sync;
    assign publish_bank=write_bank;
    assign working=state==PROCESS || state==START_PROCESS;
    assign processor_reset_n=rst_n && state!=CLEAR;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=WAIT_ENABLE;timer<=0;capture_request<=0;processor_start<=0;
            complete_sync<=0;ok_sync<=0;ack_sync<=0;
            write_bank<=1;publish_toggle<=0;frame_error<=0;input_wait<=0;
            good_frames<=0;rejected_frames<=0;
        end else begin
            complete_sync<={complete_sync[1:0],capture_complete};
            ok_sync<={ok_sync[1:0],capture_ok};
            ack_sync<={ack_sync[1:0],display_ack};
            processor_start<=0;
            case(state)
                WAIT_ENABLE: if(enabled) begin timer<=0;state<=REQUEST;end
                REQUEST: begin
                    capture_request<=~capture_request;
                    timer<=0;input_wait<=0;state<=CAP_WAIT;
                end
                CAP_WAIT: begin
                    // Keep the outstanding request unchanged when RX clock is
                    // absent. Repeated toggles would cancel a pending capture.
                    if(timer<CAPTURE_TIMEOUT)timer<=timer+1;
                    else input_wait<=1;
                    if(complete_sync[2]==capture_request) begin
                        timer<=0;state<=CAP_SETTLE;
                    end
                end
                CAP_SETTLE: begin
                    timer<=timer+1;
                    if(timer==3) begin
                        timer<=0;input_wait<=0;
                        if(ok_sync[2])state<=START_PROCESS;
                        else begin
                            rejected_frames<=rejected_frames+1;
                            frame_error<=1;state<=RETRY;
                        end
                    end
                end
                START_PROCESS: begin processor_start<=1;state<=PROCESS;end
                PROCESS: begin
                    if(processor_error) begin
                        rejected_frames<=rejected_frames+1;
                        frame_error<=1;timer<=0;state<=CLEAR;
                    end else if(processor_done) begin
                        good_frames<=good_frames+1;frame_error<=0;state<=PUBLISH;
                    end
                end
                PUBLISH: begin publish_toggle<=~publish_toggle;state<=DISPLAY_WAIT;end
                DISPLAY_WAIT: if(ack_sync[2]==publish_toggle) begin
                    // Ack means the new bank is now the displayed bank. The
                    // other bank can be written for the next completed result.
                    write_bank<=~write_bank;state<=REQUEST;
                end
                CLEAR: begin
                    timer<=timer+1;
                    if(timer==RESET_CYCLES-1) begin timer<=0;state<=RETRY;end
                end
                RETRY: begin
                    timer<=timer+1;
                    if(timer==RETRY_CYCLES-1) begin timer<=0;state<=REQUEST;end
                end
                default: begin state<=WAIT_ENABLE;timer<=0;end
            endcase
        end
    end
endmodule
`default_nettype wire

`default_nettype none
// Two immutable source banks: a complete ready frame cannot be overwritten.
// Capture bank is selected one cycle before the request toggle for bundled CDC.
module frame_session_overlap #(
 parameter CAPTURE_TIMEOUT=54000000,RETRY_CYCLES=270000,RESET_CYCLES=8
)(
 input wire clk,rst_n,enabled,capture_permitted,
 output reg capture_request,capture_bank,source_bank,
 input wire capture_complete,capture_ok,
 output reg processor_start,output wire processor_reset_n,
 input wire processor_done,processor_error,
 output reg write_bank,publish_toggle,output wire publish_bank,
 input wire display_ack,
 output reg frame_error,input_wait,output wire working,
 output reg [31:0] good_frames,output wire [31:0] rejected_frames,
 output wire capture_inflight,source_ready
);
 localparam WAIT_FRAME=0,START_PROCESS=1,PROCESS=2,PUBLISH=3,DISPLAY_WAIT=4,CLEAR=5,RETRY=6;
 localparam CAP_IDLE=0,CAP_LAUNCH=1,CAP_WAIT=2,CAP_SETTLE=3,CAP_RETRY=4;
 reg [2:0] state,cap_state;
 reg [31:0] timer,cap_timer,cap_rejected,proc_rejected;
 reg source_locked,ready_valid;
 (* ASYNC_REG="TRUE" *) reg [2:0] complete_sync,ok_sync,ack_sync;
 assign publish_bank=write_bank;
 assign processor_reset_n=rst_n&&(state!=CLEAR);
 assign working=(state==START_PROCESS)||(state==PROCESS);
 assign rejected_frames=cap_rejected+proc_rejected;
 assign capture_inflight=(cap_state==CAP_LAUNCH)||(cap_state==CAP_WAIT)||(cap_state==CAP_SETTLE);
 assign source_ready=ready_valid;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=WAIT_FRAME;cap_state<=CAP_IDLE;timer<=0;cap_timer<=0;
   cap_rejected<=0;proc_rejected<=0;good_frames<=0;
   capture_request<=0;capture_bank<=0;source_bank<=0;
   source_locked<=0;ready_valid<=0;processor_start<=0;
   write_bank<=1;publish_toggle<=0;frame_error<=0;input_wait<=0;
   complete_sync<=0;ok_sync<=0;ack_sync<=0;
  end else begin
   complete_sync<={complete_sync[1:0],capture_complete};
   ok_sync<={ok_sync[1:0],capture_ok};
   ack_sync<={ack_sync[1:0],display_ack};
   processor_start<=0;
   case(cap_state)
    CAP_IDLE:if(enabled&&!ready_valid&&(!source_locked||capture_permitted))begin
     capture_bank<=source_locked?~source_bank:1'b0;
     cap_state<=CAP_LAUNCH;
    end
    CAP_LAUNCH:begin
     capture_request<=~capture_request;cap_timer<=0;input_wait<=0;cap_state<=CAP_WAIT;
    end
    CAP_WAIT:begin
     if(cap_timer<CAPTURE_TIMEOUT)cap_timer<=cap_timer+1'b1;
     else input_wait<=1;
     // Never cancel a pending capture when RX is stopped.
     if(complete_sync[2]==capture_request)begin cap_timer<=0;cap_state<=CAP_SETTLE;end
    end
    CAP_SETTLE:begin
     cap_timer<=cap_timer+1'b1;
     if(cap_timer==3)begin
      cap_timer<=0;input_wait<=0;
      if(ok_sync[2])begin ready_valid<=1;cap_state<=CAP_IDLE;end
      else begin cap_rejected<=cap_rejected+1'b1;cap_state<=CAP_RETRY;end
     end
    end
    CAP_RETRY:begin
     cap_timer<=cap_timer+1'b1;
     if(cap_timer==RETRY_CYCLES-1)begin cap_timer<=0;cap_state<=CAP_IDLE;end
    end
    default:cap_state<=CAP_IDLE;
   endcase
   case(state)
    WAIT_FRAME:if(enabled&&ready_valid)begin
     source_bank<=capture_bank;source_locked<=1;ready_valid<=0;state<=START_PROCESS;
    end
    START_PROCESS:begin processor_start<=1;state<=PROCESS;end
    PROCESS:begin
     if(processor_error)begin proc_rejected<=proc_rejected+1'b1;timer<=0;state<=CLEAR;end
     else if(processor_done)begin
      good_frames<=good_frames+1'b1;source_locked<=0;state<=PUBLISH;
     end
    end
    PUBLISH:begin publish_toggle<=~publish_toggle;state<=DISPLAY_WAIT;end
    DISPLAY_WAIT:if(ack_sync[2]==publish_toggle)begin write_bank<=~write_bank;state<=WAIT_FRAME;end
    CLEAR:begin
     timer<=timer+1'b1;
     if(timer==RESET_CYCLES-1)begin source_locked<=0;timer<=0;state<=RETRY;end
    end
    RETRY:begin
     timer<=timer+1'b1;
     if(timer==RETRY_CYCLES-1)begin timer<=0;state<=WAIT_FRAME;end
    end
    default:begin source_locked<=0;state<=WAIT_FRAME;end
   endcase
   // Capture failure and processing failure cannot lose a rejection count.
   if((cap_state==CAP_SETTLE&&cap_timer==3&&!ok_sync[2])||
      (state==PROCESS&&processor_error))frame_error<=1;
   else if(state==PROCESS&&processor_done)frame_error<=0;
  end
 end
endmodule
`default_nettype wire
