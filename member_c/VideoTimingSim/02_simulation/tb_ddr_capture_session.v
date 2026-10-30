`timescale 1ns/1ps
module tb_ddr_capture_session;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,start=0,source_done=0,source_ok=1,abort_frame=0;
 reg bv=0,bl=0;reg [255:0] bd=0;reg [31:0] bs=32'hffffffff;
 reg cr=0,rv=0,rw=1,fault=0,acquire=0,release_read=0;
 wire ready,br,busy,done,ok,cv,cw,latest_valid,locked,map_valid;
 wire [27:0] ca;wire [255:0] cd;wire [31:0] cs;
 wire [1:0] latest_slot,read_slot;wire [31:0] fid,read_id,rb0,rb1;
 integer test_passed=0;
 ddr_capture_session #(.SRC_W(10),.SRC_H(3),.OUT_W(8),.OUT_H(8)) dut(
  .clk(clk),.rst_n(rst_n),.capture_start(start),.capture_ready(ready),
  .source_done(source_done),.source_ok(source_ok),.capture_abort(abort_frame),
  .block_valid(bv),.block_ready(br),.block_data(bd),.block_strb(bs),.block_last(bl),
  .busy(busy),.capture_done(done),.capture_ok(ok),.cmd_valid(cv),.cmd_ready(cr),
  .cmd_write(cw),.cmd_addr(ca),.cmd_wdata(cd),.cmd_wstrb(cs),
  .rsp_valid(rv),.rsp_write(rw),.mem_fault(fault),.read_acquire(acquire),.read_release(release_read),
  .latest_valid(latest_valid),.latest_slot(latest_slot),.latest_frame_id(fid),
  .read_locked(locked),.read_slot(read_slot),.read_frame_id(read_id),
  .result_base0_byte(rb0),.result_base1_byte(rb1),.layout_valid(map_valid));
 wire [31:0] s0,s1,s2,r0,r1,sbytes,rbytes;wire fullmap;
 ddr_memory_layout layout(s0,s1,s2,r0,r1,sbytes,rbytes,fullmap);
 wire capacity_bad,geometry_bad,overflow_bad;
 ddr_memory_layout #(.MEMORY_BYTES(16*1024*1024)) too_small(
  .source_base0_byte(),.source_base1_byte(),.source_base2_byte(),.result_base0_byte(),
  .result_base1_byte(),.source_bytes(),.result_bytes(),.layout_valid(capacity_bad));
 ddr_memory_layout #(.SRC_W(0)) invalid_geometry(
  .source_base0_byte(),.source_base1_byte(),.source_base2_byte(),.result_base0_byte(),
  .result_base1_byte(),.source_bytes(),.result_bytes(),.layout_valid(geometry_bad));
 ddr_memory_layout #(.SRC_W(1073741824),.SRC_H(1073741824),
  .OUT_W(1073741824),.OUT_H(536870912)) overflow_geometry(
  .source_base0_byte(),.source_base1_byte(),.source_base2_byte(),.result_base0_byte(),
  .result_base1_byte(),.source_bytes(),.result_bytes(),.layout_valid(overflow_bad));
 task tick;begin @(posedge clk);#1;end endtask
 task begin_frame;begin
  if(!ready)$fatal(1,"capture not ready");
  @(negedge clk);start=1;tick;@(negedge clk);start=0;
  repeat(8)tick;if(!br||!busy)$fatal(1,"allocation/arm did not start writer");
 end endtask
 task finish_source(input bit valid_frame);begin
  @(negedge clk);source_done=1;source_ok=valid_frame;tick;@(negedge clk);source_done=0;
 end endtask
 task block(input integer index,input integer slot,input bit last,input [31:0] mask);begin
  while(!br)tick;
  @(negedge clk);bv=1;bl=last;bs=mask;bd=index+32'h12345678;tick;
  @(negedge clk);bv=0;
  while(!cv)tick;
  repeat(2)begin tick;if(ca!==slot*32+index*8||cd!==bd||cs!==mask||!cw)
   $fatal(1,"partition address/payload changed");end
  @(negedge clk);cr=1;tick;@(negedge clk);cr=0;
  repeat(3)tick;
  @(negedge clk);rv=1;tick;@(negedge clk);rv=0;
 end endtask
 task wait_done(input bit expected_ok);begin
  while(!done)tick;if(ok!==expected_ok)$fatal(1,"wrong capture qualification");
  tick;
 end endtask
 task reset;begin
  @(negedge clk);rst_n=0;start=0;abort_frame=0;bv=0;cr=0;rv=0;fault=0;source_done=0;
  acquire=0;release_read=0;tick;@(negedge clk);rst_n=1;tick;
 end endtask
 initial begin
  reset;
  if(!fullmap||sbytes!=8294400||s1!=8294400||s2!=16588800||r0!=24883200||
     rbytes!=2314240||r1!=27197440||r0<s2+sbytes)$fatal(1,"full-HD memory partitions overlap");
  if(capacity_bad||geometry_bad||overflow_bad)$fatal(1,"invalid memory layout allowed");
  if(!map_valid||rb0!=384||rb1!=640)$fatal(1,"small-frame aligned layout");
  begin_frame;
  block(0,0,0,32'hffffffff);block(1,0,0,32'hffffffff);block(2,0,0,32'hffffffff);
  block(3,0,1,32'h00ffffff);
  repeat(5)begin tick;if(latest_valid||done||ready)$fatal(1,"published before source validation");end
  finish_source(1);wait_done(1);
  if(!latest_valid||fid!=1||latest_slot!=0)$fatal(1,"first complete frame missing");
  @(negedge clk);acquire=1;tick;@(negedge clk);acquire=0;tick;
  if(!locked||read_slot!=0||read_id!=1)$fatal(1,"reader did not lock first frame");
  begin_frame;finish_source(1);
  block(0,1,0,32'hffffffff);block(1,1,0,32'hffffffff);block(2,1,0,32'hffffffff);
  if(fid!=1)$fatal(1,"early source confirmation published unwritten frame");
  block(3,1,1,32'h00ffffff);wait_done(1);
  if(fid!=2||latest_slot!=1||read_slot!=0)$fatal(1,"locked slot changed");
  begin_frame;
  block(0,2,0,32'hffffffff);block(1,2,0,32'hffffffff);block(2,2,0,32'hffffffff);block(3,2,1,32'h00ffffff);
  @(negedge clk);abort_frame=1;tick;@(negedge clk);abort_frame=0;wait_done(0);
  if(fid!=2||latest_slot!=1)$fatal(1,"late abort published bad frame");
  begin_frame;
  @(negedge clk);bv=1;bs=32'hffffffff;bl=0;bd=10;tick;@(negedge clk);bv=0;
  while(!cv)tick;@(negedge clk);cr=1;tick;@(negedge clk);cr=0;abort_frame=1;tick;
  @(negedge clk);abort_frame=0;
  repeat(6)begin tick;if(done||ready||!busy)$fatal(1,"slot released with outstanding write");end
  @(negedge clk);rv=1;tick;@(negedge clk);rv=0;wait_done(0);
  if(fid!=2)$fatal(1,"aborted drain published");
  begin_frame;@(negedge clk);bv=1;bl=1;bs=32'hffffffff;tick;@(negedge clk);bv=0;
  wait_done(0);if(fid!=2||cv)$fatal(1,"short frame reached DDR or published");
  begin_frame;finish_source(0);wait_done(0);if(fid!=2)$fatal(1,"failed source published");
  begin_frame;@(negedge clk);bv=1;bl=0;bs=32'hfffffffe;tick;@(negedge clk);bv=0;
  wait_done(0);if(fid!=2||cv)$fatal(1,"invalid mask accepted");
  // Complete both conditions, then fail on the actual publication edge.
  begin_frame;
  block(0,2,0,32'hffffffff);block(1,2,0,32'hffffffff);block(2,2,0,32'hffffffff);block(3,2,1,32'h00ffffff);
  finish_source(1);
  while(dut.state!=4)tick;
  @(negedge clk);abort_frame=1;tick;
  if(!done||ok||fid!=2)$fatal(1,"publication-edge abort lost");
  @(negedge clk);abort_frame=0;tick;
  reset;begin_frame;@(negedge clk);abort_frame=1;tick;@(negedge clk);abort_frame=0;wait_done(0);
  if(latest_valid)$fatal(1,"reset/empty cancel published");
  test_passed=1;$display("PASS_DDR_CAPTURE_SESSION partitions qualification lock late_abort drain short_frame source_failure reset");$finish;
 end
 initial begin #200000;$fatal(1,"timeout");end
endmodule
