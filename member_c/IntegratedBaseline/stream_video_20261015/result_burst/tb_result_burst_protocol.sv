`timescale 1ns/1ps
module tb_result_burst_protocol;
 reg clk=0,rst_n=0,cv=0,awready=0,wready=0,wlast=0;always #4 clk=~clk;
 reg cw=1,sb=0,rb=1;reg[27:0]ca=28'h200000;
 reg[3:0]wid=0;reg[2047:0]payload=0;
 wire ready,rsp,write_rsp,fault,av,arv;wire[3:0]reason,len,id,arlen,arid;wire[27:0]awaddr,araddr;
 wire[255:0]wdata,rdata;wire[31:0]mask;wire awap,arap;reg test_passed=0;
 ddr_word_engine_result_burst #(.WATCHDOG_CYCLES(8),.CAPTURE_BURST_BEATS(1),.SOURCE_WORDS(64),.RESULT_WORDS(80),.RESULT_BASE0(28'h200000),.RESULT_BASE1(28'h400000)) dut(
  .clk(clk),.rst_n(rst_n),.init_done(rst_n),.cmd_valid(cv),.cmd_ready(ready),.cmd_source_block(sb),.cmd_result_block(rb),.result_block_data(payload),.rsp_source_block(),.cmd_write(cw),.cmd_addr(ca),
  .cmd_wdata(256'h100),.cmd_wstrb(32'hffffffff),.capture_burst_data(2048'hbadbad),.rsp_valid(rsp),.rsp_write(write_rsp),.rsp_rdata(rdata),.fault(fault),.fault_reason(reason),
  .axi_awaddr(awaddr),.axi_awuser_ap(awap),.axi_awuser_id(id),.axi_awlen(len),.axi_awvalid(av),.axi_awready(awready),
  .axi_wdata(wdata),.axi_wstrb(mask),.axi_wready(wready),.axi_wusero_id(wid),.axi_wusero_last(wlast),
  .axi_araddr(araddr),.axi_aruser_ap(arap),.axi_aruser_id(arid),.axi_arlen(arlen),.axi_arvalid(arv),.axi_arready(1'b0),
  .axi_rdata(256'd0),.axi_rid(4'd0),.axi_rlast(1'b0),.axi_rvalid(1'b0));
 task run_case(input integer mode);
  begin
   @(negedge clk);rst_n=0;cv=0;awready=0;wready=0;wid=0;wlast=0;
   repeat(3)@(negedge clk);if(fault||rsp||ready||av||arv)$fatal(1,"BURST_RESET");rst_n=1;
   repeat(2)@(negedge clk);cv=1;@(posedge clk);#1;@(negedge clk);cv=0;
   if(!av||len!=7||awaddr!=28'h200000)$fatal(1,"RESULT_BURST_AW len=%0d",len);awready=1;
   if(mode==5)begin wready=1;wlast=0;if(wdata!==payload[255:0])$fatal(1,"sameAWdata");end
   @(posedge clk);#1;@(negedge clk);awready=0;
   for(integer k=(mode==5?1:0);k<8;k=k+1)begin
    if(mode==4&&k==3)begin
     wready=0;repeat(10)@(negedge clk);
     if(!fault||reason!=5)$fatal(1,"BURST_MIDDLE_TIMEOUT");break;
    end
    wready=0;repeat(k%3)begin @(negedge clk);if(wdata!==256'h100+k||rsp)$fatal(1,"stalled WDATA changed");end
    wready=1;wid=(mode==3&&k==3)?4'd5:4'd0;
    wlast=(mode==1&&k==2)?1'b1:(mode==2&&k==7)?1'b0:(k==7);
    if(wdata!==256'h100+k||mask!==32'hffffffff||rsp)$fatal(1,"BURST_DATA_OR_EARLY_RESPONSE mode=%0d beat=%0d",mode,k);
    @(posedge clk);#1;
    if((mode==1&&k==2)||(mode==2&&k==7)||(mode==3&&k==3))begin
     if(!fault||reason!=2||!rsp)$fatal(1,"BURST_PROTOCOL_FAULT mode=%0d",mode);@(negedge clk);break;
    end
    if((mode==0||mode==5)&&k==7)begin if(fault||!rsp||!write_rsp)$fatal(1,"FINAL_BEAT_RESPONSE");end
    @(negedge clk);
   end
   wready=0;wid=0;wlast=0;
   if(mode!=0&&mode!=5)begin repeat(2)@(negedge clk);if(ready||av||arv||!fault)$fatal(1,"STICKY_BURST_FAULT");end
  end
 endtask
 task illegal(input integer mode);
 begin
  @(negedge clk);rst_n=0;cv=0;awready=0;wready=0;wid=0;wlast=0;
  repeat(3)@(negedge clk);rst_n=1;@(negedge clk);
  cw=(mode!=0);sb=(mode==4);rb=1;
  ca=(mode==1)?28'h200008:(mode==2)?28'h200040:(mode==3)?28'd0:28'h200000;
  cv=1;@(posedge clk);#1;@(negedge clk);cv=0;
  if(!fault||reason!=1||!rsp||av||arv)$fatal(1,"illegal result block mode=%0d",mode);
  repeat(2)@(negedge clk);if(ready)$fatal(1,"illegal not hard stop");
  cw=1;sb=0;ca=28'h200000;
 end
 endtask
 initial begin
  for(integer k=0;k<8;k=k+1)payload[k*256+:256]=256'h100+k;
  for(integer mode=0;mode<6;mode=mode+1)run_case(mode);
  for(integer mode=0;mode<5;mode=mode+1)illegal(mode);
  @(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;@(negedge clk);cv=1;
  @(posedge clk);#1;@(negedge clk);cv=0;repeat(10)@(negedge clk);
  if(!fault||reason!=4||ready)$fatal(1,"AW timeout missing");
  @(negedge clk);rst_n=0;repeat(2)@(negedge clk);if(fault||rsp||av)$fatal(1,"FINAL_RESET");
  test_passed=1;$display("PASS RESULT_BURST_PROTOCOL_FAULT_RESET");$finish;
 end
 initial begin #20000;$fatal(1,"BURST_PROTOCOL_TIMEOUT");end
endmodule


