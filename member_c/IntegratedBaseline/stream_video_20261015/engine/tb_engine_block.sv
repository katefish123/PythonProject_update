`timescale 1ns/1ps
module tb_engine_block;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,init_done=1,cmd_valid=0,cmd_write=0,cmd_source_block=0;wire cmd_ready;
reg[27:0]cmd_addr=0;reg[255:0]cmd_wdata=0;reg[31:0]cmd_wstrb='1;reg[2047:0]capture_burst_data=0;
wire rsp_valid,rsp_write,fault;wire[255:0]rsp_rdata;wire[2047:0]rsp_source_block;wire[3:0]fault_reason;
wire[27:0]axi_awaddr,axi_araddr;wire axi_awuser_ap,axi_aruser_ap;wire[3:0]axi_awuser_id,axi_aruser_id,axi_awlen,axi_arlen;wire axi_awvalid,axi_arvalid;
reg axi_awready=1,axi_wready=1,axi_arready=1;reg[3:0]axi_wusero_id=0,axi_rid=0;reg axi_wusero_last=1,axi_rlast=0,axi_rvalid=0;reg[255:0]axi_rdata=0;wire[255:0]axi_wdata;wire[31:0]axi_wstrb;
integer n,b,l,reads=0;integer seed=901;reg[2047:0]expected;
ddr_word_engine #(.WATCHDOG_CYCLES(12),.SOURCE_PREFETCH_ENABLE(0),.READ_AHEAD_ENABLE(1),.SOURCE_WORDS(1050),.SOURCE_BASE0(0),.SOURCE_BASE1(28'h800000)) dut(.*);
always @(posedge clk)if(axi_arvalid&&axi_arready)reads=reads+1;
task reset;begin @(negedge clk);rst_n=0;cmd_valid=0;axi_rvalid=0;axi_arready=1;axi_rid=0;repeat(3)@(negedge clk);rst_n=1;@(negedge clk);end endtask
task request(input[27:0]addr,input wr,input forced);begin
 while(!cmd_ready)@(negedge clk);cmd_addr=addr;cmd_write=wr;cmd_source_block=forced;cmd_valid=1;
 @(posedge clk);#1;@(negedge clk);cmd_valid=0;
end endtask
task returnblock(input[27:0]addr,input integer bad);integer k,j;reg[255:0]d;begin
 if(!axi_arvalid||axi_araddr!==addr||axi_arlen!==7)$fatal(1,"forced random block did not issue 8 beats addr=%h len=%d",axi_araddr,axi_arlen);
 @(posedge clk);@(negedge clk);expected=0;
 for(k=0;k<8;k=k+1)begin
  for(j=0;j<8;j=j+1)d[j*32+:32]=32'hc0000000+addr+k*8+j;
  expected[k*256+:256]=d;axi_rdata=d;axi_rvalid=1;axi_rlast=(k==7);axi_rid=(bad==1&&k==2)?1:0;
  if(bad==2&&k==2)axi_rlast=1;
  @(posedge clk);#1;
  if((bad!=0)&&k==2)begin if(!fault||fault_reason!=3||!rsp_valid||rsp_source_block!==0)$fatal(1,"bad read beat not hard fault");k=8;end
  else if(k<7&&rsp_valid)$fatal(1,"early block completion");
  else if(k==7)begin if(!rsp_valid||rsp_source_block!==expected||rsp_rdata!==expected[255:0])$fatal(1,"full block/last beat lost");end
  @(negedge clk);
 end
 axi_rvalid=0;axi_rlast=0;axi_rid=0;@(negedge clk);
end endtask
initial begin
 reset();
 for(n=0;n<20;n=n+1)begin b=(($random(seed)&15)*64);request(b,0,1);if(axi_arvalid)returnblock(b,0);else begin if(!rsp_valid||rsp_source_block!==expected)$fatal(1,"random cached block wrong");@(negedge clk);end end
 reset();request(28'h800180,0,1);returnblock(28'h800180,0);l=reads;
 request(28'h800180,0,1);if(!rsp_valid||axi_arvalid||rsp_source_block!==expected||reads!=l)$fatal(1,"block cache hit failed");@(negedge clk);
 request(28'h800180,1,0);while(!rsp_valid)@(negedge clk);@(negedge clk);
 request(28'h800180,0,1);returnblock(28'h800180,0);if(reads!=l+1)$fatal(1,"source write failed to invalidate");
 $display("PASS random forced blocks with prefetch disabled, full last beat, hit, source invalidation");
 reset();request(8,0,1);if(!fault||fault_reason!=1||!rsp_valid||axi_arvalid)$fatal(1,"unaligned forced command accepted");
 reset();request(1024,0,1);if(!fault||fault_reason!=1||axi_arvalid)$fatal(1,"unsafe tail forced command accepted");
 reset();request(1088,0,1);if(!fault||fault_reason!=1||axi_arvalid)$fatal(1,"out of source forced command accepted");
 reset();request(0,1,1);if(!fault||fault_reason!=1||axi_awvalid)$fatal(1,"forced write accepted");
 reset();request(0,0,1);returnblock(0,1);if(cmd_ready)$fatal(1,"fault not hard stop");
 reset();request(64,0,1);returnblock(64,2);
 reset();axi_arready=0;request(128,0,1);repeat(14)@(negedge clk);if(!fault||fault_reason!=6||cmd_ready)$fatal(1,"AR timeout missing");
 reset();request(192,0,1);@(posedge clk);@(negedge clk);repeat(14)@(negedge clk);if(!fault||fault_reason!=7||cmd_ready)$fatal(1,"R timeout missing");
 $display("PASS forced illegal commands, wrong RID/early RLAST, AR/R timeouts, hard reset recovery");$finish;
end
initial begin #100000;$fatal(1,"engine watchdog");end
endmodule

