`timescale 1ns/1ps
module tb_overlap_session;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,enabled=0,cap_complete=0,cap_ok=0,pdone=0,perror=0,ack=0;
 wire req,start,prst,wbank,pub,pbank,ferror,iwait,working;
 wire [31:0] good,rejected;
 wire cbank,sbank;
 reg test_passed=0;integer starts=0;reg request_seen=0,publish_seen=0;
`ifdef LEGACY_SESSION
 assign cbank=0;assign sbank=0;
 frame_session #(.CAPTURE_TIMEOUT(32),.RETRY_CYCLES(6)) dut(
`else
 frame_session_overlap #(.CAPTURE_TIMEOUT(32),.RETRY_CYCLES(6)) dut(
  .capture_bank(cbank),.source_bank(sbank),.capture_inflight(),.source_ready(),
`endif
 .clk(clk),.rst_n(rst_n),.enabled(enabled),.capture_request(req),.capture_complete(cap_complete),.capture_ok(cap_ok),
 .processor_start(start),.processor_reset_n(prst),.processor_done(pdone),.processor_error(perror),
 .write_bank(wbank),.publish_toggle(pub),.publish_bank(pbank),.display_ack(ack),
 .frame_error(ferror),.input_wait(iwait),.working(working),.good_frames(good),.rejected_frames(rejected));
 always @(posedge clk)if(rst_n&&start)starts=starts+1;
 task next_request;
  integer n;begin
   n=0;while(req==request_seen&&n<80)begin @(negedge clk);n=n+1;end
   if(req==request_seen)$fatal(1,"NO_BACKGROUND_CAPTURE: next request did not overlap processing");
   request_seen=req;
  end
 endtask
 task capture_done(input integer ok);
  begin repeat(3)@(negedge clk);cap_ok=ok;cap_complete=request_seen;repeat(2)@(negedge clk);end
 endtask
 task processor_done;
  begin @(negedge clk);pdone=1;@(negedge clk);pdone=0;wait(pub!=publish_seen);publish_seen=pub;end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;enabled=1;
  next_request();if(cbank!=0)$fatal(1,"initial source bank");capture_done(1);
  wait(start);@(negedge clk);if(sbank!=0)$fatal(1,"first processing source bank");
  next_request();if(!working||cbank==sbank)$fatal(1,"capture not isolated from processing bank");
  capture_done(1);
  repeat(90)begin @(negedge clk);if(req!=request_seen||sbank!=0)$fatal(1,"ready source overwritten or active bank changed");end
  processor_done();repeat(40)@(negedge clk);
  if(starts!=1)$fatal(1,"result bank reused before display acknowledgement");
  ack=pub;wait(start);@(negedge clk);if(sbank!=1)$fatal(1,"ready bank was not consumed");
  next_request();if(cbank!=0)$fatal(1,"released bank not reused");
  // Malformed background capture must not interrupt the valid processor.
  capture_done(0);repeat(10)@(negedge clk);
  if(!working||rejected!=1)$fatal(1,"capture failure damaged active processing");
  next_request();capture_done(1);
  // A processing error resets its pipeline but preserves the other ready frame.
  @(negedge clk);perror=1;@(negedge clk);perror=0;
  wait(!prst);wait(prst);wait(start);@(negedge clk);
  if(sbank!=0||good!=1||rejected!=2)$fatal(1,"processing-error recovery lost ready frame");
  next_request();if(cbank!=1)$fatal(1,"background bank after recovery");
  repeat(90)begin @(negedge clk);if(req!=request_seen)$fatal(1,"absent RX cancelled pending request");end
  if(!iwait)$fatal(1,"missing RX timeout diagnostic");capture_done(1);
  processor_done();ack=pub;wait(start);@(negedge clk);if(sbank!=1)$fatal(1,"RX recovery not consumed");
  // Common reset abandons the previous capture and publication tokens.
  rst_n=0;enabled=0;cap_complete=0;cap_ok=0;ack=0;request_seen=0;publish_seen=0;
  repeat(5)@(negedge clk);rst_n=1;enabled=1;
  next_request();capture_done(1);wait(start);@(negedge clk);
  if(sbank!=0||good!=0||rejected!=0)$fatal(1,"common reset did not clear ownership");
  processor_done();ack=pub;repeat(10)@(negedge clk);
  test_passed=1;$display("OVERLAP_SESSION_PASS overlap ownership backpressure bad_capture process_error rx_pause reset");$finish;
 end
 initial begin #100000;$fatal(1,"session test timeout");end
endmodule
