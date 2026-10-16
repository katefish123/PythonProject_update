`timescale 1ns/1ps
module tb_fault_diagnostics #(parameter TB=48);
 reg proc_clk=0,ui_clk=0,rst_n=0,ui_run=1;
 always #7 proc_clk=~proc_clk;
 always #4 if(ui_run)ui_clk=~ui_clk;else ui_clk=0;
 reg ui_engine_fault=0,ui_phy_fail=0,ui_align_error=0,ui_self_fail=0;
 reg[3:0]ui_engine_reason=0,ui_stage=0,ui_dqs_valid=0,proc_source_fault=0;
 wire current_fault_any,source_snapshot_valid,first_valid,source_first_valid;
 wire[4:0]current_mask,first_mask;wire[2:0]current_kind,first_kind;
 wire[3:0]current_raw_reason,current_engine_reason,current_source_fault,current_ui_stage,current_dqs_valid;
 wire[3:0]first_raw_reason,first_engine_reason,first_source_fault,first_ui_stage,first_dqs_valid,source_first_fault;
 wire[TB-1:0]current_ui_tick,current_source_proc_tick,current_source_received_ui_tick,first_ui_tick,first_source_proc_tick,source_first_proc_tick,source_first_received_ui_tick;
 fault_diagnostics_stream #(.TICK_BITS(TB)) dut(.*);
 integer ui_updates=0,proc_held_checks=0,wraps=0;
 reg[8+2*TB:0]held_before,update_payload;reg was_busy;
 always @(posedge proc_clk)if(rst_n&&dut.proc_local_rst_n)begin
  was_busy=dut.proc_request!=dut.proc_ack_sync[1];held_before=dut.mailbox_hold;
  #0.2;if(was_busy)begin
   if(dut.mailbox_hold!==held_before)$fatal(1,"mailbox payload changed before ACK");
   proc_held_checks=proc_held_checks+1;
  end
 end
 always @(posedge ui_clk)if(rst_n&&dut.ui_local_rst_n&&dut.source_update)begin
  update_payload=dut.mailbox_hold;#0.2;
  if(!source_snapshot_valid||current_source_fault!==update_payload[2*TB+5+:4]||current_source_proc_tick!==update_payload[TB+5+:TB])$fatal(1,"incoherent CDC snapshot");
  ui_updates=ui_updates+1;
 end
 task ptick;begin @(posedge proc_clk);#1;end endtask
 task utick;begin @(posedge ui_clk);#1;end endtask
 task settle;begin repeat(8)ptick();repeat(10)utick();end endtask
 task reset_diag;
  begin
   @(negedge proc_clk);rst_n=0;ui_run=1;ui_engine_fault=0;ui_phy_fail=0;ui_align_error=0;ui_self_fail=0;
   ui_engine_reason=0;ui_stage=0;ui_dqs_valid=0;proc_source_fault=0;
   repeat(3)ptick();rst_n=1;settle();
   if(current_fault_any||current_mask||first_valid||source_first_valid)$fatal(1,"reset replayed an old diagnostic event");
  end
 endtask
 task source(input[3:0]value);begin @(negedge proc_clk);proc_source_fault=value;ptick();end endtask
 task wait_source(input[3:0]value);
  begin:await_value
   for(integer n=0;n<100;n=n+1)begin
    utick();if(source_snapshot_valid&&current_source_fault===value&&current_mask[0]==(|value))disable await_value;
   end
   $fatal(1,"source snapshot did not converge value=%h actual=%h",value,current_source_fault);
  end
 endtask
 function[2*TB+28:0]history();
  history={first_valid,first_mask,first_kind,first_raw_reason,first_engine_reason,first_source_fault,first_ui_tick,first_source_proc_tick,first_ui_stage,first_dqs_valid};
 endfunction
 reg[2*TB+28:0]saved;reg[TB-1:0]expected_proc,expected_ui,previous_tick;
 initial begin
  reset_diag();@(negedge ui_clk);ui_align_error=1;ui_stage=5;ui_dqs_valid=4'ha;expected_ui=dut.ui_tick;utick();
  if(!first_valid||first_kind!=4||first_mask!=8||first_ui_tick!==expected_ui||first_ui_stage!=5||first_dqs_valid!=10)$fatal(1,"short ALIGN event lost timestamp/context");
  saved=history();@(negedge ui_clk);ui_align_error=0;utick();
  if(current_fault_any||current_kind!=0)$fatal(1,"historical ALIGN became a current fault");
  @(negedge proc_clk);proc_source_fault=7;expected_proc=dut.proc_tick;ptick();wait_source(7);
  if(current_kind!=1||current_raw_reason!=7||current_mask!=1||!current_fault_any||history()!==saved)$fatal(1,"HISTORY_OVERRIDES_CURRENT_SOURCE");
  if(!source_first_valid||source_first_fault!=7||source_first_proc_tick!==expected_proc)$fatal(1,"source first raw code/timestamp lost");
  source(0);wait_source(0);if(current_fault_any||history()!==saved)$fatal(1,"source clear confused history/current");
  $display("PASS history ALIGN clear then source-only raw7 current/source LED and immutable first UI event");
  reset_diag();@(negedge ui_clk);ui_align_error=1;ui_stage=3;ui_dqs_valid=5;utick();saved=history();
  repeat(12)utick();if(current_kind!=4||history()!==saved)$fatal(1,"sustained ALIGN event changed first record");
  @(negedge ui_clk);ui_engine_fault=1;ui_engine_reason=5;utick();
  if(current_mask!=10||current_kind!=2||current_raw_reason!=5||current_engine_reason!=5||history()!==saved)$fatal(1,"secondary engine fault replaced first ALIGN");
  @(negedge ui_clk);ui_phy_fail=1;ui_self_fail=1;utick();if(current_mask!=30)$fatal(1,"concurrent raw causes lost");
  @(negedge ui_clk);ui_engine_fault=0;utick();if(current_kind!=3)$fatal(1,"PHY current selection");
  @(negedge ui_clk);ui_phy_fail=0;utick();if(current_kind!=4)$fatal(1,"ALIGN current selection");
  @(negedge ui_clk);ui_align_error=0;utick();if(current_kind!=5)$fatal(1,"SELF current selection");
  @(negedge ui_clk);ui_self_fail=0;utick();if(current_fault_any||history()!==saved)$fatal(1,"cleared current did not retain history");
  $display("PASS sustained ALIGN, secondary engine reason5, simultaneous PHY/ALIGN/SELF masks and current clearing");
  reset_diag();source(2);wait_source(2);saved=history();
  @(negedge ui_clk);ui_engine_fault=1;ui_engine_reason=9;ui_phy_fail=1;ui_align_error=1;ui_self_fail=1;utick();
  if(current_mask!=31||current_kind!=1||current_raw_reason!=2||current_engine_reason!=9)$fatal(1,"source/engine raw codes conflated");
  @(negedge ui_clk);ui_engine_fault=0;ui_phy_fail=0;ui_align_error=0;ui_self_fail=0;
  for(integer k=0;k<10;k=k+1)begin source(4'(1+(k*7)%15));wait_source(4'(1+(k*7)%15));if(history()!==saved||source_first_fault!=2)$fatal(1,"later source code rewrote history");end
  source(0);wait_source(0);
  $display("PASS all raw source bits/multi-bit codes coherent; simultaneous source+engine retain independent raw reasons");
  reset_diag();@(negedge ui_clk);ui_run=0;repeat(8)ptick();
  if(dut.proc_request==dut.proc_ack_sync[1])$fatal(1,"mailbox stall not exercised");
  source(8);source(0);repeat(12)ptick();ui_run=1;
  begin:await_short_source
   for(integer n=0;n<100;n=n+1)begin utick();if(source_first_valid)disable await_short_source;end
   $fatal(1,"short first source event lost while mailbox busy");
  end
  if(source_first_fault!=8||!first_valid||first_kind!=1||first_raw_reason!=8||first_mask!=1)$fatal(1,"busy-mailbox first-source history mismatch");
  wait_source(0);if(current_fault_any)$fatal(1,"source history became current after pulse clear");
  $display("PASS stopped UI/backpressured CDC mailbox stable; one-proc-cycle first source pulse retained without fabricating current fault");
  @(negedge ui_clk);ui_run=0;source(4);repeat(4)ptick();rst_n=0;proc_source_fault=0;#1;
  if(first_valid||current_fault_any||source_first_valid)$fatal(1,"shared reset failed while UI clock stopped");
  repeat(3)ptick();ui_run=1;rst_n=1;settle();if(first_valid||current_fault_any||source_first_valid)$fatal(1,"reset replayed old mailbox request");
  @(negedge ui_clk);ui_align_error=1;utick();@(negedge ui_clk);ui_align_error=0;utick();saved=history();
  previous_tick=current_ui_tick;
  repeat(TB<=8?600:20)begin utick();if(current_ui_tick<previous_tick)wraps=wraps+1;previous_tick=current_ui_tick;if(history()!==saved)$fatal(1,"timestamp wrap rewrote first record");end
  if(TB<=8&&wraps<2)$fatal(1,"small counter did not wrap");
  if(ui_updates<8||proc_held_checks<20)$fatal(1,"insufficient CDC mailbox checks");
  $display("PASS FAULT_DIAGNOSTICS TICK_BITS=%0d updates=%0d held_payload_checks=%0d wraps=%0d reset=1 first_observed_UI_order=1",TB,ui_updates,proc_held_checks,wraps);$finish;
 end
 initial begin #100000;$fatal(1,"fault diagnostics timeout TB=%0d",TB);end
endmodule
