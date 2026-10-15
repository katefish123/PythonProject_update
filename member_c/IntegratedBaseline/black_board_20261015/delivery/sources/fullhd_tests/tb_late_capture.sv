`timescale 1ns/1ps
module tb_late_capture;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,complete=0,ok=0,done=0,ack=0,allowed=0;
 wire req,cb,sb,start,prst,wb,pub,pb,err,iw,work;wire [31:0] good,bad;
 reg test_passed=0;reg last_req=0;
 frame_session_overlap #(.CAPTURE_TIMEOUT(100),.RETRY_CYCLES(6)) dut(.phase(),.capture_rejected(),
`ifndef LEGACY_LATE
 .capture_permitted(allowed),
`endif
 .clk(clk),.rst_n(rst_n),.enabled(1'b1),.capture_request(req),.capture_bank(cb),.source_bank(sb),
 .capture_complete(complete),.capture_ok(ok),.processor_start(start),.processor_reset_n(prst),
 .processor_done(done),.processor_error(1'b0),.write_bank(wb),.publish_toggle(pub),.publish_bank(pb),.display_ack(ack),
 .frame_error(err),.input_wait(iw),.working(work),.good_frames(good),.rejected_frames(bad),.capture_inflight(),.source_ready());
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  wait(req!=last_req);last_req=req;repeat(3)@(negedge clk);ok=1;complete=req;
  wait(start);@(negedge clk);
  repeat(30)begin @(negedge clk);if(req!=last_req)$fatal(1,"CAPTURE_BEFORE_WINDOW: next snapshot too early");end
  allowed=1;wait(req!=last_req);last_req=req;
  if(cb==sb||!work)$fatal(1,"late capture bank ownership");
  repeat(3)@(negedge clk);complete=req;
  repeat(12)@(negedge clk);done=1;@(negedge clk);done=0;allowed=0;
  wait(pub==1);ack=pub;wait(start);@(negedge clk);
  if(sb!=1)$fatal(1,"late ready source not consumed");
  repeat(20)begin @(negedge clk);if(req!=last_req)$fatal(1,"stale previous progress launched another capture");end
  test_passed=1;$display("LATE_CAPTURE_PASS initial_capture window bank_protection ready_consumption");$finish;
 end
 initial begin #100000;$fatal(1,"late capture test timeout");end
endmodule
