`timescale 1ns/1ps
module tb_ddr_writer_a_engine #(parameter USE_SESSION=0);
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,start=0,abort_frame=0,pv=0,pl=0;
 reg [23:0] rgb=0;reg [31:0] base=0;
 wire pr,bv,br,bl,sr,busy,done,ok;
 wire [255:0] bd;wire [31:0] bs;
 wire cv,cr,cw,rv,rw,fault;
 wire [27:0] ca;wire [255:0] cd,rd;wire [31:0] cs;
 wire [27:0] awaddr,araddr;wire awap,arap,av,arv;
 wire [3:0] awid,arid,awlen,arlen;
 wire [255:0] wd;wire [31:0] ws;
 reg awready=0,wready=0,stall_write=0;integer cycle=0,delay=0,writes=0;
 reg pending=0;reg [27:0] write_addr=0;
 reg [31:0] memory[0:63];integer j,k,test_passed=0;
 rgb888_block_packer pack(.clk(clk),.rst_n(rst_n),.in_valid(pv),.in_ready(pr),
  .in_rgb(rgb),.in_last(pl),.in_abort(abort_frame),.out_valid(bv),.out_ready(br),
  .out_data(bd),.out_strb(bs),.out_last(bl));
 generate if(USE_SESSION)begin: session_mode
  ddr_capture_session #(.SRC_W(16),.SRC_H(1),.OUT_W(8),.OUT_H(8)) session(
   .clk(clk),.rst_n(rst_n),.capture_start(start),.capture_ready(sr),
   .source_done(pv&&pr&&pl),.source_ok(1'b1),.capture_abort(abort_frame),
   .block_valid(bv),.block_ready(br),.block_data(bd),.block_strb(bs),.block_last(bl),
   .busy(busy),.capture_done(done),.capture_ok(ok),.cmd_valid(cv),.cmd_ready(cr),.cmd_write(cw),
   .cmd_addr(ca),.cmd_wdata(cd),.cmd_wstrb(cs),.rsp_valid(rv),.rsp_write(rw),.mem_fault(fault),
   .read_acquire(1'b0),.read_release(1'b0),.latest_valid(),.latest_slot(),.latest_frame_id(),
   .read_locked(),.read_slot(),.read_frame_id(),.result_base0_byte(),.result_base1_byte(),.layout_valid());
 end else begin: writer_mode
  ddr_block_writer writer(clk,rst_n,start,sr,base,abort_frame,bv,br,bd,bs,bl,
   busy,done,ok,cv,cr,cw,ca,cd,cs,rv,rw,fault);
 end endgenerate
 ddr_word_engine #(.WATCHDOG_CYCLES(32)) engine(
  .clk(clk),.rst_n(rst_n),.init_done(1'b1),.cmd_valid(cv),.cmd_ready(cr),
  .cmd_write(cw),.cmd_addr(ca),.cmd_wdata(cd),.cmd_wstrb(cs),
  .rsp_valid(rv),.rsp_write(rw),.rsp_rdata(rd),.fault(fault),
  .axi_awaddr(awaddr),.axi_awuser_ap(awap),.axi_awuser_id(awid),.axi_awlen(awlen),
  .axi_awvalid(av),.axi_awready(awready),.axi_wdata(wd),.axi_wstrb(ws),
  .axi_wready(wready),.axi_wusero_id(4'd0),.axi_wusero_last(1'b1),
  .axi_araddr(araddr),.axi_aruser_ap(arap),.axi_aruser_id(arid),.axi_arlen(arlen),
  .axi_arvalid(arv),.axi_arready(1'b0),.axi_rdata(256'd0),.axi_rid(4'd0),
  .axi_rlast(1'b0),.axi_rvalid(1'b0));
 // Controller-level handshake model: AW stalls, delayed W consumption, no B.
 always @(negedge clk)begin
  cycle=cycle+1;awready=!pending&&(cycle%5==0);wready=pending&&(delay==0)&&!stall_write;
 end
 always @(posedge clk)begin
  if(!rst_n)begin pending<=0;delay<=0;writes<=0;end
  else begin
   if(av&&awready)begin
    if(awlen!=0||awid!=0||awap)$fatal(1,"unexpected burst contract");
    pending<=1;delay<=4;write_addr<=awaddr;
   end
   if(pending&&delay>0)delay<=delay-1;
   if(pending&&wready)begin
    for(j=0;j<8;j=j+1)for(k=0;k<4;k=k+1)
     if(ws[j*4+k])memory[(write_addr%(USE_SESSION?16:2073600))+j][k*8+:8]<=wd[j*32+k*8+:8];
    pending<=0;writes<=writes+1;
   end
   if(arv)$fatal(1,"write pipeline issued read");
  end
 end
 task tick;begin @(posedge clk);#1;end endtask
 task frame(input integer count,input integer id);integer n;begin
  @(negedge clk);base=id*8294400;start=1;tick;@(negedge clk);start=0;
  for(n=0;n<count;n=n+1)begin
   while(!pr)tick;
   @(negedge clk);pv=1;pl=(n==count-1);rgb=24'h102030+n+id*256;
   tick;@(negedge clk);pv=0;
  end
  while(!done)tick;
  if(!ok||fault)$fatal(1,"real A engine failed write frame");
  for(n=0;n<count;n=n+1)if(memory[n] !== (32'h00102030+n+id*256))
   $fatal(1,"pixel mismatch at %0d",n);
  if(count==19&&memory[19]!==32'ha5a5a5a5)$fatal(1,"partial strobe overwrote trailing pixel");
  tick;
 end endtask
 initial begin
  for(j=0;j<64;j=j+1)memory[j]=32'ha5a5a5a5;
  tick;@(negedge clk);rst_n=1;tick;
  if(USE_SESSION)begin frame(16,0);frame(16,1);end
  else begin frame(19,1);frame(16,2);end
  if(writes!=(USE_SESSION?4:5))$fatal(1,"wrong count of accepted DDR beats");
  @(negedge clk);start=1;base=0;stall_write=1;tick;@(negedge clk);start=0;
  for(integer n=0;n<8;n=n+1)begin
   while(!pr)tick;@(negedge clk);pv=1;pl=!USE_SESSION&&(n==7);rgb=n;tick;@(negedge clk);pv=0;
  end
  while(!done)tick;
  if(ok||!fault||writes!=(USE_SESSION?4:5))$fatal(1,"A timeout incorrectly published frame");
  test_passed=1;
  if(USE_SESSION)$display("PASS_DDR_SESSION_A_ENGINE pixels=32 beats=4 timeout");
  else $display("PASS_DDR_WRITER_A_ENGINE pixels=35 beats=5 partial_mask timeout");
  $finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
