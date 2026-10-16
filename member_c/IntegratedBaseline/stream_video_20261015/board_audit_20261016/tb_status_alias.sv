`timescale 1ns/1ps
module tb_status_alias;
reg ui_clk=0;always #4 ui_clk=~ui_clk;wire pix_clk=ui_clk;
reg ui_rst=0;wire scan_reset_n=ui_rst;
reg engine_fault=0,phy_fail=0,align_error=0,self_fail=0;
reg[3:0]engine_reason=0,reason_q2=0,phase_q2=0;reg image_valid=0,preview_valid=0;
 reg[4:0]memory_detail;
 always @(posedge ui_clk or negedge ui_rst)begin
  if(!ui_rst)memory_detail<=0;
  else if(memory_detail==0)begin
   if(engine_fault)memory_detail<=5'd16+{1'b0,engine_reason};
   else if(phy_fail)memory_detail<=5'd25;
   else if(align_error)memory_detail<=5'd26;
   else if(self_fail)memory_detail<=5'd27;
  end
 end
 (* ASYNC_REG="TRUE" *)reg[4:0]detail_q0,detail_q1,detail_q2;
 always @(posedge pix_clk or negedge scan_reset_n)begin
  if(!scan_reset_n)begin detail_q0<=0;detail_q1<=0;detail_q2<=0;end
  else begin detail_q0<=memory_detail;detail_q1<=detail_q0;detail_q2<=detail_q1;end
 end
 wire[4:0]screen_status=(reason_q2==7&&detail_q2!=0)?detail_q2:(reason_q2!=0)?{1'b0,reason_q2}:image_valid?5'd9:
  (phase_q2==4||phase_q2==5)?4'd8:preview_valid?4'd10:4'd0;

initial begin
 repeat(4)@(negedge ui_clk);ui_rst=1;
 repeat(5)@(negedge ui_clk);if(memory_detail!==0)$fatal(1,"reset history");
 align_error=1;@(negedge ui_clk);align_error=0;
 repeat(6)@(negedge ui_clk);reason_q2=7;#1;
 if(memory_detail!==26||screen_status!==26||engine_fault||phy_fail||align_error||self_fail)$fatal(1,"alias not reproduced");
 $display("PASS DIAGNOSTIC_ALIAS historical_align=26 current_raw_memory_fault=0 generic_reason7_status=26");
 reason_q2=4;#1;if(screen_status!==4)$fatal(1,"nonmemory reason priority");
 ui_rst=0;repeat(4)@(negedge ui_clk);ui_rst=1;reason_q2=7;
 repeat(6)@(negedge ui_clk);if(screen_status!==7)$fatal(1,"history reset");
 $display("PASS HARD_RESET_CLEARS_HISTORY; no board/PHY root-cause claim");$finish;
end
initial begin #5000;$fatal(1,"timeout");end
endmodule
