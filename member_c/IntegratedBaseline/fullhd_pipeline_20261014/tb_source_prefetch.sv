`timescale 1ns/1ps
module tb_source_prefetch;
 localparam [27:0] S1=28'h0800000,R0=28'h0100000;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,cv=0,cw=0;reg [27:0] ca=0;reg [255:0] cd=0;wire cr,rv,rw,fault;wire [255:0] rd;
 wire [27:0] aa,ra;wire [3:0] al,rl,aid,rid;wire ap,rp,av,arv;wire [255:0] wd;wire [31:0] wm;
 reg rvalid=0,rlast=0;reg [255:0] rdata=0;reg pending=0;reg [27:0] read_addr=0;
 integer read_index=0,read_total=0,delay_count=0,reads=0,expected_len=0;
 reg override0=0,override1=0;reg [255:0] changed0=0,changed1=0;reg test_passed=0;
`ifdef LEGACY_ENGINE
 ddr_word_engine #(.READ_AHEAD_ENABLE(1),.RESULT_WORDS(128)) dut(
`else
 ddr_word_engine #(.READ_AHEAD_ENABLE(1),.RESULT_WORDS(128),.SOURCE_PREFETCH_ENABLE(1),.SOURCE_WORDS(80),.SOURCE_BASE1(S1)) dut(
`endif
 .clk(clk),.rst_n(rst_n),.init_done(rst_n),.cmd_valid(cv),.cmd_ready(cr),.cmd_write(cw),.cmd_addr(ca),.cmd_wdata(cd),.cmd_wstrb(32'hffffffff),
 .rsp_valid(rv),.rsp_write(rw),.rsp_rdata(rd),.fault(fault),
 .axi_awaddr(aa),.axi_awuser_ap(ap),.axi_awuser_id(aid),.axi_awlen(al),.axi_awvalid(av),.axi_awready(1'b1),
 .axi_wdata(wd),.axi_wstrb(wm),.axi_wready(1'b1),.axi_wusero_id(4'd0),.axi_wusero_last(1'b1),
 .axi_araddr(ra),.axi_aruser_ap(rp),.axi_aruser_id(rid),.axi_arlen(rl),.axi_arvalid(arv),.axi_arready(!pending),
 .axi_rdata(rdata),.axi_rid(4'd0),.axi_rlast(rlast),.axi_rvalid(rvalid));
 function [255:0] word(input [27:0] addr);
  begin
   if(addr==0&&override0)word=changed0;
   else if(addr==S1+8&&override1)word=changed1;
   else for(integer k=0;k<8;k=k+1)word[k*32+:32]=32'h21430000+addr+k;
  end
 endfunction
 always @(posedge clk)if(rst_n)begin
  if(fault)$fatal(1,"source prefetch engine fault");
  if(arv&&!pending)begin
   if(rl!==expected_len)$fatal(1,"SOURCE_PREFETCH_NOT_PRESENT expected_len=%0d actual=%0d addr=%h",expected_len,rl,ra);
   read_addr<=ra;read_index<=0;read_total<=rl+1;delay_count<=4;pending<=1;reads=reads+1;
  end
  if(av)begin
   if(aa==0)begin override0<=1;changed0<=wd;end
   else if(aa==S1+8)begin override1<=1;changed1<=wd;end
   else $fatal(1,"unexpected source write");
  end
 end
 always @(negedge clk)begin
  rvalid=0;rlast=0;
  if(pending)begin
   if(delay_count>0)delay_count=delay_count-1;
   else begin
    rdata=word(read_addr+read_index*8);rvalid=1;rlast=(read_index==read_total-1);read_index=read_index+1;
    if(read_index==read_total)pending=0;
   end
  end
 end
 task request(input [27:0] addr,input integer len,input integer write_mode);
  integer before_reads;begin
   @(negedge clk);before_reads=reads;ca=addr;cw=write_mode;cd=256'h0123456789abcdef;expected_len=len;cv=1;
   @(posedge clk);while(!cr)@(posedge clk);@(negedge clk);cv=0;
   wait(rv);@(negedge clk);
   if(rw!==write_mode)$fatal(1,"response type mismatch");
   if(!write_mode&&rd!==word(addr))$fatal(1,"stale or incorrect cached word %h",addr);
   if(len==-1&&reads!=before_reads)$fatal(1,"cache hit caused physical read");
   if(!write_mode&&len>=0&&reads!=before_reads+1)$fatal(1,"missing physical read");
   repeat(2)@(negedge clk);
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  request(0,7,0);request(8,-1,0);request(R0,7,0);request(16,-1,0);request(R0+8,-1,0);
  request(56,-1,0);request(64,0,0);request(72,0,0);
  request(S1,7,0);request(S1+8,-1,1);request(S1+8,7,0);
  request(0,7,0);request(S1+8,-1,1);request(8,-1,0);
  request(0,-1,1);request(0,7,0);request(24,-1,0);
  test_passed=1;$display("SOURCE_PREFETCH_PASS cache_reuse independent_scanout bounded_tail source_banks write_invalidation");$finish;
 end
 initial begin #100000;$fatal(1,"source cache test timeout");end
endmodule
