`timescale 1ns/1ps
module block_region_case #(parameter C=0)(output reg done=0,output integer checked=0);
 localparam integer WORDS=C==0?2073600:C==1?1050:C==2?0:C==3?1:C==4?63:C==5?64:C==6?65:C==7?128:C==8?129:C==9?2147483647:C==10?192:829441;
 localparam integer RWORDS=C==0?829440:WORDS;
 localparam[27:0] SB0=C==0?0:C==7?28'hfffffc0:C==8?28'hffffff7:C==9?28'hfff0001:C==10?28'h7ffffc0:28'(C*1031);
 localparam[27:0] SB1=C==0?28'h800000:C==7?28'hfffff80:C==8?28'hfffffff:C==9?28'hffffffd:C==10?28'hfffffc0:28'(28'h800000+C*77);
 localparam[27:0] RB0=C==0?28'h400000:C==7?28'hfffffc0:C==8?28'hfffffff:C==9?28'hffffffc:C==10?28'h7ffff80:28'(28'h200000+C*19);
 localparam[27:0] RB1=C==0?28'h600000:C==7?28'hfffff80:C==8?28'hffffff9:C==9?28'hffffff7:C==10?28'hfffffc0:28'(28'h400000+C*129);
 reg[27:0]address=0;reg wr=0,sb=0;reg[31:0]rng;reg[31:0]centers[0:7];
 wire[27:0]block_addr={address[27:6],6'b0};
 // Verbatim original relational expressions deliberately retain Verilog's
 // unsigned 32-bit parameter-addition/comparison context, including >28bit end.
 wire original_source=((block_addr>=SB0&&block_addr+28'd63<SB0+WORDS)||(block_addr>=SB1&&block_addr+28'd63<SB1+WORDS));
 wire original_result=((block_addr>=RB0&&block_addr+28'd63<RB0+RWORDS)||(block_addr>=RB1&&block_addr+28'd63<RB1+RWORDS));
 ddr_word_engine_result_burst #(.SOURCE_WORDS(WORDS),.RESULT_WORDS(RWORDS),.SOURCE_BASE0(SB0),.SOURCE_BASE1(SB1),.RESULT_BASE0(RB0),.RESULT_BASE1(RB1),.READ_AHEAD_ENABLE(1),.SOURCE_PREFETCH_ENABLE(1)) dut(
 .cmd_ready(),.rsp_valid(),.rsp_write(),.rsp_rdata(),.rsp_source_block(),.fault(),.fault_reason(),.axi_awaddr(),.axi_awuser_ap(),.axi_awuser_id(),.axi_awlen(),.axi_awvalid(),.axi_wdata(),.axi_wstrb(),.axi_araddr(),.axi_aruser_ap(),.axi_aruser_id(),.axi_arlen(),.axi_arvalid(),
 .clk(1'b0),.rst_n(1'b0),.init_done(1'b0),.cmd_valid(1'b0),.cmd_write(wr),.cmd_source_block(sb),.cmd_result_block(1'b0),.result_block_data(2048'd0),.cmd_addr(address),.cmd_wdata(256'd0),.cmd_wstrb(32'd0),.capture_burst_data(2048'd0),
 .axi_awready(1'b0),.axi_wready(1'b0),.axi_wusero_id(4'd0),.axi_wusero_last(1'b0),.axi_arready(1'b0),.axi_rdata(256'd0),.axi_rid(4'd0),.axi_rlast(1'b0),.axi_rvalid(1'b0));
 task check(input[27:0]a);
 begin address=a;
  for(integer flag=0;flag<4;flag=flag+1)begin wr=flag[0];sb=flag[1];#1;
   if(dut.source_block_safe!==original_source||dut.result_block_safe!==original_result||dut.result_read!==(!sb&&!wr&&original_result))
    $fatal(1,"BLOCK_REGION_EQUIVALENCE C=%0d words=%0d addr=%h flags=%0d oldsource=%b newsource=%b oldresult=%b newresult=%b",C,WORDS,address,flag,original_source,dut.source_block_safe,original_result,dut.result_block_safe);
   checked=checked+1;
  end
 end endtask
 initial begin
  centers[0]=SB0;centers[1]=SB1;centers[2]=RB0;centers[3]=RB1;
  centers[4]=SB0+WORDS;centers[5]=SB1+WORDS;centers[6]=RB0+RWORDS;centers[7]=RB1+RWORDS;
  for(integer center=0;center<8;center=center+1)
   for(integer delta=-129;delta<=129;delta=delta+1)check(28'(centers[center]+delta));
  rng=32'h12345678+C*17;
  for(integer k=0;k<4096;k=k+1)begin rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);check(rng[27:0]);end
  done=1;
 end
endmodule
module tb_block_region_decode;
 wire[11:0]done;wire[31:0]checks[0:11];integer total=0;
 for(genvar c=0;c<12;c=c+1)begin:cases block_region_case #(.C(c)) test_case(done[c],checks[c]);end
 initial begin wait(&done);for(integer c=0;c<12;c=c+1)total=total+checks[c];
  $display("PASS BLOCK_REGION_EQUIVALENCE cases=12 checks=%0d unaligned_BASE_WORDS=1 empty_short=1 near28bit_end=1 crossing28bit=1 max_positive_integer_WORDS=1 write_source_flags=1",total);$finish;end
 initial begin #100000;$fatal(1,"region equivalence timeout");end
endmodule
