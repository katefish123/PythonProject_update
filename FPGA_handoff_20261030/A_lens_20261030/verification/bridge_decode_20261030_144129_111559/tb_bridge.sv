`timescale 1ns/1ps
module bridge_lane #(parameter REF=0,W=1920,H=1080,OW=1920,OH=1080,N=5000)(
 input wire proc_clk,ui_clk,rst_n,output reg[31:0]sent=0,received=0,output wire fault);
 reg[197:0]vectors[0:N-1];reg[125:0]expected[0:N-1];integer ptick=0,utick=0,qstalls=0,rstalls=0;
 wire q_valid=rst_n&&sent<N&&ptick%9>=2,q_ready;
 wire[27:0]q_base;wire[31:0]q_generation;wire[23:0]q_addr00,q_addr10,q_addr01,q_addr11,q_tag;wire[7:0]q_fx,q_fy;wire q_inside,q_nearest;
 assign {q_base,q_generation,q_addr00,q_addr10,q_addr01,q_addr11,q_tag,q_fx,q_fy,q_inside,q_nearest}=vectors[sent];
 wire req_valid,req_ready=rst_n&&utick%37>=20;wire[27:0]req_base;wire[31:0]req_generation;wire[11:0]req_x,req_y;
 wire req_nearest,req_inside;wire[23:0]req_tag;wire[7:0]req_fx,req_fy;
 wire[125:0]actual={req_base,req_generation,req_x,req_y,req_nearest,req_inside,req_tag,req_fx,req_fy};
 wire rsp_ready,r_valid,r_inside;wire[23:0]r_p00,r_p10,r_p01,r_p11,r_tag;wire[7:0]r_fx,r_fy;wire[31:0]r_generation;
 generate if(REF)begin: reference
 quad_packet_bridge_reference #(.SRC_W(W),.SRC_H(H),.OUT_W(OW),.OUT_H(OH),.FIFO_ADDR_BITS(3)) dut(
 .proc_clk(proc_clk),.ui_clk(ui_clk),.rst_n(rst_n),.q_valid(q_valid),.q_ready(q_ready),.q_inside(q_inside),.q_nearest(q_nearest),.q_addr00(q_addr00),.q_addr10(q_addr10),.q_addr01(q_addr01),.q_addr11(q_addr11),.q_tag(q_tag),.q_fx(q_fx),.q_fy(q_fy),.q_generation(q_generation),.q_base(q_base),.fault(fault),.req_valid(req_valid),.req_ready(req_ready),.req_base(req_base),.req_generation(req_generation),.req_x(req_x),.req_y(req_y),.req_nearest(req_nearest),.req_inside(req_inside),.req_tag(req_tag),.req_fx(req_fx),.req_fy(req_fy),.rsp_ready(rsp_ready),.r_valid(r_valid),.r_inside(r_inside),.r_p00(r_p00),.r_p10(r_p10),.r_p01(r_p01),.r_p11(r_p11),.r_tag(r_tag),.r_fx(r_fx),.r_fy(r_fy),.r_generation(r_generation),.rsp_valid(1'b0),.rsp_inside(1'b0),.rsp_p00(24'd0),.rsp_p10(24'd0),.rsp_p01(24'd0),.rsp_p11(24'd0),.rsp_tag(24'd0),.rsp_fx(8'd0),.rsp_fy(8'd0),.rsp_generation(32'd0),.r_ready(1'b1)
 );
 end else begin: candidate
 quad_packet_bridge #(.SRC_W(W),.SRC_H(H),.OUT_W(OW),.OUT_H(OH),.FIFO_ADDR_BITS(3)) dut(
 .proc_clk(proc_clk),.ui_clk(ui_clk),.rst_n(rst_n),.q_valid(q_valid),.q_ready(q_ready),.q_inside(q_inside),.q_nearest(q_nearest),.q_addr00(q_addr00),.q_addr10(q_addr10),.q_addr01(q_addr01),.q_addr11(q_addr11),.q_tag(q_tag),.q_fx(q_fx),.q_fy(q_fy),.q_generation(q_generation),.q_base(q_base),.fault(fault),.req_valid(req_valid),.req_ready(req_ready),.req_base(req_base),.req_generation(req_generation),.req_x(req_x),.req_y(req_y),.req_nearest(req_nearest),.req_inside(req_inside),.req_tag(req_tag),.req_fx(req_fx),.req_fy(req_fy),.rsp_ready(rsp_ready),.r_valid(r_valid),.r_inside(r_inside),.r_p00(r_p00),.r_p10(r_p10),.r_p01(r_p01),.r_p11(r_p11),.r_tag(r_tag),.r_fx(r_fx),.r_fy(r_fy),.r_generation(r_generation),.rsp_valid(1'b0),.rsp_inside(1'b0),.rsp_p00(24'd0),.rsp_p10(24'd0),.rsp_p01(24'd0),.rsp_p11(24'd0),.rsp_tag(24'd0),.rsp_fx(8'd0),.rsp_fy(8'd0),.rsp_generation(32'd0),.r_ready(1'b1)
 );end endgenerate
 always @(posedge proc_clk)begin
  ptick<=ptick+1;
  if(!rst_n)sent<=0;
  else if(q_valid&&q_ready)sent<=sent+1;
  else if(q_valid&&!q_ready)qstalls++;
 end
 reg held=0;reg[125:0]held_payload;
 always @(posedge ui_clk)begin
  utick<=utick+1;
  if(!rst_n)begin received<=0;held<=0;end
  else begin
   if(held&&(!req_valid||actual!==held_payload))$fatal(1,"BRIDGE_UNSTABLE ref=%0d W=%0d",REF,W);
   held<=req_valid&&!req_ready;held_payload<=actual;
   if(req_valid&&!req_ready)rstalls++;
   if(req_valid&&req_ready)begin
    if(received>=N||actual!==expected[received])$fatal(1,"BRIDGE_PACKET_MISMATCH ref=%0d W=%0d index=%0d actual=%h expected=%h",REF,W,received,actual,expected[received]);
    received<=received+1;
   end
  end
 end
 initial begin
  if(W==1920)begin $readmemh("large_input.hex",vectors);$readmemh("large_expected.hex",expected);end
  else begin $readmemh("small_input.hex",vectors);$readmemh("small_expected.hex",expected);end
 end
endmodule
module bridge_case #(parameter W=1920,H=1080,OW=1920,OH=1080)(output reg finished=0);
 reg proc_clk=0,ui_clk=0,rst_n=0;always #5.387205 proc_clk=~proc_clk;initial begin #1.733;forever #4 ui_clk=~ui_clk;end
 wire[31:0]a_sent,b_sent,a_received,b_received;wire a_fault,b_fault;
 bridge_lane #(.REF(0),.W(W),.H(H),.OW(OW),.OH(OH)) newer(proc_clk,ui_clk,rst_n,a_sent,a_received,a_fault);
 bridge_lane #(.REF(1),.W(W),.H(H),.OW(OW),.OH(OH)) original(proc_clk,ui_clk,rst_n,b_sent,b_received,b_fault);
 initial begin
  repeat(10)@(negedge proc_clk);rst_n=1;
  wait(a_sent>=300&&b_sent>=300);
  if(a_fault||b_fault)$fatal(1,"LEGAL_BRIDGE_PACKET_REJECTED W=%0d",W);
  @(negedge proc_clk);rst_n=0;repeat(20)@(negedge proc_clk);
  if(a_fault||b_fault)$fatal(1,"BRIDGE_FAULT_NOT_RESET");
  rst_n=1;wait(a_received==5000&&b_received==5000);repeat(200)@(negedge ui_clk);
  if(a_received!=5000||b_received!=5000||!a_fault||!b_fault||newer.qstalls==0||newer.rstalls==0)$fatal(1,"BRIDGE_COVERAGE W=%0d",W);
  $display("REQUEST_BRIDGE_PASS width=%0d packets_per_lane=5000 actual_and_original=2 legal_prefix=300 reset_cancel=1 malformed_tag_address=1 outside=1 qstalls=%0d rstalls=%0d",W,newer.qstalls,newer.rstalls);finished=1;
 end
endmodule
module tb_bridge;
 wire a,b;bridge_case large(a);bridge_case #(.W(128),.H(16),.OW(64),.OH(16)) fallback(b);
 initial begin wait(a&&b);$display("BRIDGE_DECODE_EQUIVALENCE_PASS");$finish;end
 initial begin #10000000;$fatal(1,"BRIDGE_TIMEOUT");end
endmodule
