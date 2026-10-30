`timescale 1ns/1ps
module c_frame_mode_controller(
 input wire clk,rst_n,enabled,raw_request,
 input wire frame_valid,frame_bank,frame_geometry_valid,
 input wire[31:0] frame_generation,frame_capture_ms,
 output wire frame_ready,start_correct,abort_correct,
 input wire path_ready,path_busy,path_done,path_error,fault_condition,
 input wire[3:0] path_failure_reason,
 input wire display_ack,
 output wire source_select_bank,
 output reg result_write_bank,publish_toggle,publish_bank,publish_raw,
 output reg[31:0] published_generation,published_capture_ms,
 output reg[31:0] displayed_generation,displayed_capture_ms,
 output reg release_valid,release_bank,output reg[31:0]release_generation,
 output reg[31:0] raw_publications,corrected_publications,rejected_frames,
 output reg session_error,output reg[3:0]reason,output reg[2:0]state
);
 localparam WAIT_SOURCE=0,PROCESS=1,WAIT_DISPLAY=2,DRAIN=3,FAULT=4;
 reg held_bank,raw_lease_valid,raw_lease_bank;
 reg[31:0]held_generation,held_capture_ms,raw_lease_generation;
 assign frame_ready=rst_n&&enabled&&!fault_condition&&state==WAIT_SOURCE&&path_ready;
 assign start_correct=frame_valid&&frame_ready&&!raw_request&&frame_geometry_valid&&!(raw_lease_valid&&raw_lease_bank==frame_bank);
 // Abort persists only until the soft-aborted path has actually drained.
 // A hard memory/source fault instead holds every lease until shared reset.
 assign abort_correct=(state==PROCESS&&(!enabled||fault_condition))||(state==DRAIN&&path_busy)||state==FAULT;
 assign source_select_bank=state==WAIT_SOURCE?frame_bank:held_bank;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   result_write_bank<=0;publish_toggle<=0;publish_bank<=0;publish_raw<=0;
   published_generation<=0;published_capture_ms<=0;displayed_generation<=0;displayed_capture_ms<=0;
   release_valid<=0;release_bank<=0;release_generation<=0;raw_publications<=0;corrected_publications<=0;
   rejected_frames<=0;session_error<=0;reason<=0;state<=WAIT_SOURCE;
   held_bank<=0;held_generation<=0;held_capture_ms<=0;raw_lease_valid<=0;raw_lease_bank<=0;raw_lease_generation<=0;
  end else begin
   release_valid<=0;
   if(fault_condition)begin state<=FAULT;session_error<=1;reason<=7;end
   else case(state)
    WAIT_SOURCE:if(frame_valid&&frame_ready)begin
     held_bank<=frame_bank;held_generation<=frame_generation;held_capture_ms<=frame_capture_ms;
     // The manager must never offer a bank still displayed by RAW.
     if(raw_lease_valid&&raw_lease_bank==frame_bank)begin state<=FAULT;session_error<=1;reason<=7;end
     else if(raw_request)begin
      publish_bank<=frame_bank;publish_raw<=1;publish_toggle<=~publish_toggle;
      published_generation<=frame_generation;published_capture_ms<=frame_capture_ms;
      raw_publications<=raw_publications+1'b1;state<=WAIT_DISPLAY;session_error<=0;reason<=0;
     end else if(frame_geometry_valid)begin state<=PROCESS;session_error<=0;reason<=0;end
     else begin
      release_valid<=1;release_bank<=frame_bank;release_generation<=frame_generation;
      rejected_frames<=rejected_frames+1'b1;session_error<=1;reason<=3;
     end
    end
    PROCESS:begin
     if(path_error||!enabled)begin
      state<=DRAIN;session_error<=1;reason<=path_error?path_failure_reason:4'd1;
      rejected_frames<=rejected_frames+1'b1;
     end else if(path_done)begin
      release_valid<=1;release_bank<=held_bank;release_generation<=held_generation;
      publish_raw<=0;publish_bank<=result_write_bank;publish_toggle<=~publish_toggle;
      published_generation<=held_generation;published_capture_ms<=held_capture_ms;
      corrected_publications<=corrected_publications+1'b1;state<=WAIT_DISPLAY;session_error<=0;reason<=0;
     end
    end
    WAIT_DISPLAY:if(display_ack==publish_toggle)begin
     // The ACK represents a real PIX frame-boundary switch. Return the
     // PREVIOUS RAW source, never the newly published/displayed source.
     if(raw_lease_valid)begin release_valid<=1;release_bank<=raw_lease_bank;release_generation<=raw_lease_generation;end
     raw_lease_valid<=publish_raw;
     if(publish_raw)begin raw_lease_bank<=held_bank;raw_lease_generation<=held_generation;end
     else result_write_bank<=~result_write_bank;
     displayed_generation<=published_generation;displayed_capture_ms<=published_capture_ms;state<=WAIT_SOURCE;
    end
    DRAIN:if(!path_busy&&path_ready)begin
     release_valid<=1;release_bank<=held_bank;release_generation<=held_generation;state<=WAIT_SOURCE;
    end
    FAULT:begin end
    default:begin state<=FAULT;session_error<=1;reason<=7;end
   endcase
  end
 end
endmodule
