`timescale 1ns/1ps
module tb_frame_modes;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,enabled=1,raw_request=1,frame_valid=0,frame_bank=0,frame_geometry_valid=0;
 reg[31:0]frame_generation=0,frame_capture_ms=0;
 reg path_ready=1,path_busy=0,path_done=0,path_error=0,fault_condition=0;
 reg[3:0]path_failure_reason=4;reg display_ack=0;
 wire frame_ready,start_correct,abort_correct,source_select_bank,result_write_bank,publish_toggle,publish_bank,publish_raw;
 wire[31:0]published_generation,published_capture_ms,displayed_generation,displayed_capture_ms;
 wire release_valid,release_bank;wire[31:0]release_generation,raw_publications,corrected_publications,rejected_frames;
 wire session_error;wire[3:0]reason;wire[2:0]state;
 c_frame_mode_controller dut(.*);
 integer releases=0,starts=0;reg last_released_bank;reg[31:0]last_released_generation;
 always @(posedge clk)begin
  if(rst_n&&release_valid)begin releases=releases+1;last_released_bank=release_bank;last_released_generation=release_generation;end
  if(rst_n&&start_correct)starts=starts+1;
 end
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task offer(input bit bank,input integer gen,input bit geo);
  begin frame_bank=bank;frame_generation=gen;frame_capture_ms=gen*10;frame_geometry_valid=geo;frame_valid=1;
   #1;if(!frame_ready)$fatal(1,"RAW_OR_CORRECTION_FRAME_NOT_ACCEPTED");
   tick();frame_valid=0;
  end
 endtask
 task ack;
  begin display_ack=publish_toggle;tick();tick();end
 endtask
 initial begin
  repeat(3)tick();rst_n=1;tick();
  offer(0,1,0);
  if(!publish_raw||publish_bank!=0||published_generation!=1||starts!=0||release_valid)$fatal(1,"RAW needs no geometry/B/release");
  raw_request=0;repeat(8)begin tick();if(frame_ready||release_valid||!publish_raw)$fatal(1,"unACKed RAW lease or mode changed");end
  ack();if(releases!=0||displayed_generation!=1)$fatal(1,"first RAW bank released while displayed");
  raw_request=1;offer(1,2,0);if(releases!=0)$fatal(1,"old RAW source released before display ACK");
  ack();if(releases!=1||last_released_bank!=0||last_released_generation!=1)$fatal(1,"old RAW lease not returned after swap");
  raw_request=0;offer(0,3,1);if(starts!=1||state!=1||result_write_bank!=0)$fatal(1,"correct mode did not start B");
  path_busy=1;repeat(4)tick();path_done=1;tick();path_done=0;path_busy=0;tick();
  if(publish_raw||published_generation!=3||releases!=2||last_released_bank!=0)$fatal(1,"correct completion release/publish");
  ack();if(releases!=3||last_released_bank!=1||last_released_generation!=2||result_write_bank!=1)$fatal(1,"RAW to correct lease transition");
  offer(1,4,0);tick();if(starts!=1||corrected_publications!=1||rejected_frames!=1||reason!=3||releases!=4)$fatal(1,"invalid geometry published or B called");
  offer(1,5,1);path_busy=1;path_ready=0;path_error=1;tick();path_error=0;
  repeat(8)begin tick();if(release_valid||frame_ready)$fatal(1,"abort released source before drain");end
  path_busy=0;path_ready=1;tick();tick();if(releases!=5||last_released_generation!=5)$fatal(1,"drained source not returned");
  offer(0,6,1);path_busy=1;fault_condition=1;tick();path_busy=0;path_ready=1;fault_condition=0;
  repeat(8)begin tick();if(frame_ready||release_valid||published_generation!=3)$fatal(1,"hard fault resumed/released without shared reset");end
  rst_n=0;tick();rst_n=1;raw_request=1;display_ack=0;tick();offer(0,7,0);ack();
  if(raw_publications!=1||corrected_publications!=0||displayed_generation!=7)$fatal(1,"shared reset restart");
  // A broken upstream owner must not launch correction against displayed RAW.
  raw_request=0;frame_valid=1;frame_bank=0;frame_generation=8;frame_geometry_valid=1;
  #1;if(start_correct)$fatal(1,"LOCKED_RAW_BANK_LAUNCHED_CORRECTION");
  tick();frame_valid=0;tick();if(state!=4||release_valid)$fatal(1,"locked RAW bank ownership violation not contained");
  $display("PASS RAW_NO_GEOMETRY_FULL_SOURCE_LEASE_MODE_ACK_ABORT_DRAIN_HARD_RESET");$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule
