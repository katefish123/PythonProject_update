`timescale 1ns/1ps
module tb_geometry_join;
 reg clk=0;always #18.519 clk=~clk;
 reg rst=0,req=0,bank=0,raw=0,rawok=0,mt=0,mid=0,mb=0,mok=0;
 reg [95:0] mc=0;wire complete,good;wire [95:0] c0,c1;wire v0,v1;
 reg test_passed=0;
 geometry_frame_join dut(.failure_reason(),.writer_reason(4'd0),.clk(clk),.rst_n(rst),.request_toggle(req),.request_bank(bank),
  .writer_complete(raw),.writer_ok(rawok),.metadata_toggle(mt),.metadata_token(mid),.metadata_bank(mb),.metadata_ok(mok),.metadata_corners(mc),
  .complete_toggle(complete),.capture_ok(good),.corners0(c0),.corners1(c1),.valid0(v0),.valid1(v1));
 task wait_cycles(input integer n);repeat(n)@(negedge clk);endtask
 initial begin
  wait_cycles(5);rst=1;req=1;bank=0;wait_cycles(3);raw=1;
  // Inject one destination-clock of independent status synchronizer skew.
  wait_cycles(1);rawok=1;
  wait_cycles(12);if(complete==req)$fatal(1,"published before geometry");
  mc=96'h123456;mb=0;mok=1;mt=1;mid=1;wait(complete==req);wait_cycles(2);
  if(!good||!v0||c0!=mc)$fatal(1,"first geometry lost");
  req=0;bank=1;wait_cycles(3);mt=0;mid=0;mb=1;mc=96'habcd;
  wait_cycles(12);if(complete==req)$fatal(1,"published before DDR drain");
  raw=0;wait(complete==req);wait_cycles(2);
  if(!good||!v1||c1!=mc||c0!=96'h123456)$fatal(1,"bank ownership broken");
  // Reuse bank0 with the same per-bank token; clear stale ready state.
  req=1;bank=0;wait_cycles(4);raw=1;wait_cycles(10);
  if(complete==req)$fatal(1,"stale per-bank token accepted");
  mt=1;mid=1;mb=0;mok=0;wait(complete==req);wait_cycles(2);
  if(good||v0)$fatal(1,"failed geometry accepted");
  // Good geometry cannot override a failed DDR frame with delayed status.
  req=0;bank=1;mt=0;mid=0;mb=1;mok=1;wait_cycles(8);raw=0;
  wait_cycles(1);rawok=0;wait(complete==req);wait_cycles(2);
  if(good)$fatal(1,"bad capture accepted");
  req=1;bank=0;wait_cycles(3);rawok=1;raw=1;mb=1;mt=1;mid=1;mok=1;
  wait(complete==req);wait_cycles(2);if(good||v0)$fatal(1,"wrong bank geometry accepted");
  // A subsequent failed capture retires even if it has no metadata event.
  req=0;bank=1;wait_cycles(3);rawok=0;raw=0;wait(complete==req);wait_cycles(2);
  if(good||v1)$fatal(1,"failed capture without metadata accepted");
  rst=0;req=0;raw=0;rawok=0;mt=0;mid=0;wait_cycles(5);rst=1;
  wait_cycles(3);if(complete||v0||v1)$fatal(1,"reset did not flush metadata");
  req=1;bank=0;wait_cycles(3);raw=1;rawok=1;mt=1;mid=1;mb=0;mok=1;mc=96'hff;
  wait(complete==req);wait_cycles(2);if(!good||!v0||c0!=mc)$fatal(1,"reset recovery failed");
  test_passed=1;$display("GEOMETRY_JOIN_PASS arrival_orders bank_reuse rejection missing_metadata wrong_bank reset");$finish;
 end
 initial begin #100000;$fatal(1,"geometry join timeout");end
endmodule
