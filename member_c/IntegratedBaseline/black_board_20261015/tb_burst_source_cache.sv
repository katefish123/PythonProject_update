`timescale 1ns/1ps
module tb_burst_source_cache;
 localparam [27:0] S1=28'h0800000,R0=28'h0100000;
 reg clk=0;always #4 clk=~clk;
 reg rst=0,cv=0,cw=0;reg[27:0]ca=0;reg[255:0]cd=0;reg[2047:0]payload=0;
 wire ready,rsp,rw,fault,av,arv,awap,arap;wire[3:0]reason,awlen,arlen,awid,arid;
 wire[27:0]aa,ra;wire[255:0]wd,rd;wire[31:0]mask;
 reg awready=0,wready=0,wlast=0;reg[3:0]wid=0;
 reg rvalid=0,rlast=0;reg[3:0]read_id=0;reg[255:0]rdata=0;
 reg[255:0]mem0[0:9],mem1[0:9];
 reg writing=0,reading=0;reg[27:0]wb=0,rb=0;
 integer wi=0,wn=0,ri=0,rn=0,reads=0,writes=0,cycles=0;
 reg test_passed=0;
 ddr_word_engine #(.WATCHDOG_CYCLES(32),.CAPTURE_BURST_BEATS(8),
  .SOURCE_PREFETCH_ENABLE(1),.SOURCE_WORDS(80),.SOURCE_BASE1(S1),.READ_AHEAD_ENABLE(1)) dut(
  .clk(clk),.rst_n(rst),.init_done(rst),.cmd_valid(cv),.cmd_ready(ready),.cmd_write(cw),.cmd_addr(ca),
  .cmd_wdata(cd),.cmd_wstrb(32'hffffffff),.capture_burst_data(payload),
  .rsp_valid(rsp),.rsp_write(rw),.rsp_rdata(rd),.fault(fault),.fault_reason(reason),
  .axi_awaddr(aa),.axi_awuser_ap(awap),.axi_awuser_id(awid),.axi_awlen(awlen),.axi_awvalid(av),.axi_awready(awready),
  .axi_wdata(wd),.axi_wstrb(mask),.axi_wready(wready),.axi_wusero_id(wid),.axi_wusero_last(wlast),
  .axi_araddr(ra),.axi_aruser_ap(arap),.axi_aruser_id(arid),.axi_arlen(arlen),.axi_arvalid(arv),.axi_arready(!reading),
  .axi_rdata(rdata),.axi_rid(read_id),.axi_rlast(rlast),.axi_rvalid(rvalid));
 function[255:0] word(input[27:0]addr);
  word=(addr>=S1)?mem1[(addr-S1)/8]:mem0[addr/8];
 endfunction
 // DDR model consumes every beat at WREADY, including AW/W same edge.
 always @(posedge clk)if(rst)begin
  if(av&&awready)begin
   if(writing)$fatal(1,"overlapping AW");
   if(awlen!==7||aa!==ca||awid!==0)$fatal(1,"two-bank source burst AW mismatch addr=%h len=%d",aa,awlen);
   writing=1;wb=aa;wi=0;wn=awlen+1;writes=writes+1;
  end
  if(writing&&wready)begin
   if(wd!==(256'hc000+wi)||mask!==32'hffffffff)$fatal(1,"burst payload changed under stall");
   if(wb>=S1)mem1[(wb-S1)/8+wi]=wd;else mem0[wb/8+wi]=wd;
   wi=wi+1;if(wi==wn)writing=0;
  end
  if(arv&&!reading)begin
   rb=ra;ri=0;rn=arlen+1;reading=1;reads=reads+1;
  end
 end
 always @(negedge clk)begin
  cycles=cycles+1;awready=(cycles%3!=0);wready=writing||av;
  if(cycles%4==0)wready=0;
  wlast=writing?(wi==wn-1):1'b0;
  rvalid=0;rlast=0;
  if(reading&&cycles%3!=0)begin
   rdata=word(rb+ri*8);rvalid=1;rlast=(ri==rn-1);ri=ri+1;
   if(ri==rn)reading=0;
  end
 end
 task request(input[27:0]addr,input integer write_mode,input integer expect_reads);
  integer before_reads;begin
   @(negedge clk);#1;before_reads=reads;ca=addr;cw=write_mode;cd=256'hc000;
   for(integer k=0;k<8;k=k+1)payload[k*256+:256]=256'hc000+k;
   cv=1;@(posedge clk);while(!ready)@(posedge clk);
   @(negedge clk);#1;cv=0;payload='1;cd='1;
   wait(rsp);#1;
   if(fault||rw!==write_mode)$fatal(1,"unexpected engine fault/type reason=%0d addr=%h",reason,addr);
   if(!write_mode&&rd!==word(addr))$fatal(1,"stale source cache after burst addr=%h",addr);
   if(reads-before_reads!=expect_reads)$fatal(1,"physical AR count mismatch");
   if(write_mode&&writing)$fatal(1,"early burst response");
   repeat(3)@(negedge clk);
  end
 endtask
 task reject_tail(input[27:0]addr);
  begin
   @(negedge clk);#1;ca=addr;cw=1;cv=1;@(posedge clk);while(!ready)@(posedge clk);
   @(negedge clk);#1;cv=0;
   if(!rsp||!fault||reason!=1||av)$fatal(1,"source tail/alignment accepted or wrong screen reason");
   repeat(3)@(negedge clk);if(ready)$fatal(1,"fault not sticky");
   rst=0;repeat(3)@(negedge clk);rst=1;repeat(3)@(negedge clk);
  end
 endtask
 initial begin
  for(integer k=0;k<10;k=k+1)begin mem0[k]=256'h1000+k;mem1[k]=256'h2000+k;end
  repeat(5)@(negedge clk);rst=1;repeat(3)@(negedge clk);
  request(0,0,1);request(8,0,0);request(0,1,0);request(0,0,1);request(56,0,0);
  request(S1,0,1);request(S1+8,0,0);request(S1,1,0);request(S1,0,1);request(S1+56,0,0);
  request(0,0,1);request(S1,1,0);request(8,0,0);
  if(writes!=3)$fatal(1,"missing complete capture bursts");
  reject_tail(64);reject_tail(S1+64);reject_tail(S1+8);
  @(negedge clk);#1;read_id=3;ca=0;cw=0;cv=1;@(posedge clk);while(!ready)@(posedge clk);
  @(negedge clk);#1;cv=0;wait(fault);#1;
  if(reason!=3||ready)$fatal(1,"read protocol screen reason mismatch");
  test_passed=1;$display("BURST_SOURCE_CACHE_PASS two_banks immutable_payload AW_W_same_edge stalls invalidation safe_tail reset read_protocol_reason");$finish;
 end
 initial begin #100000;$fatal(1,"burst source cache timeout");end
endmodule
