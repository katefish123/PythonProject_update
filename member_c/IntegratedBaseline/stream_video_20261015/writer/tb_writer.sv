`timescale 1ns/1ps
module tb_writer;
reg clk=0,ui_clk=0; reg pause_source=0; integer ud=201; integer ut; integer seed=8317; integer sd=7919; integer t;
always begin t=3+($random(sd)&3); #(t) if(!pause_source)clk=~clk; end
always begin ut=1+($random(ud)&1);#(ut)ui_clk=~ui_clk;end
reg rst_n=0,ui_rst_n=0,frame_start=0,abort_frame=0,frame_bank=0;
reg write_valid=0; wire write_ready; reg[23:0] write_addr=0,write_rgb=0;
wire drained,fault,cmd_valid,cmd_write; reg cmd_ready=0; wire[27:0] cmd_addr; wire[255:0] cmd_wdata; wire[31:0]cmd_wstrb;
reg rsp_valid=0,rsp_write=1; integer qh=0,qt=0,due[0:4095]; integer ticks=0; integer accept_count=0,ack_count=0;
reg hold_commands=0,hold_acks=0; reg[27:0] exp_addr[0:4095]; reg[255:0] exp_data[0:4095]; reg[31:0] exp_strb[0:4095]; integer eh=0,et=0;
reg[255:0] assembled=0; reg[31:0] strobes=0; integer lane=0; integer base=28'h200000; integer n; integer oldack;
ddr_result_writer_stream #(.OUT_W(32),.OUT_H(8),.FIFO_ADDR_BITS(2)) dut(.*);
task fail(input[511:0] msg); begin $display("FAIL %0s t=%0t",msg,$time); $fatal(1); end endtask
always @(posedge ui_clk) if(ui_rst_n) begin
 ticks=ticks+1;
 if(cmd_valid&&cmd_ready) begin
  if(eh==et) fail("unexpected command");
  if(cmd_addr!==exp_addr[eh]||cmd_wdata!==exp_data[eh]||cmd_wstrb!==exp_strb[eh]||cmd_write!==1) begin $display("index=%0d addr=%h expected=%h data=%h expecteddata=%h",eh,cmd_addr,exp_addr[eh],cmd_wdata,exp_data[eh]); fail("command mismatch"); end
  eh=eh+1; accept_count=accept_count+1; due[qt]=ticks+5+($random(seed)&31); qt=qt+1;
 end
 if(rsp_valid) begin qh=qh+1;ack_count=ack_count+1;end
end
always @(negedge ui_clk) begin
 if(!ui_rst_n) begin cmd_ready=0;rsp_valid=0;end
 else begin cmd_ready=!hold_commands&&(($random(seed)&3)!=0); rsp_valid=!hold_acks&&(qh<qt)&&(ticks>=due[qh]);end
end
task start(input bank); begin
 @(negedge clk); frame_bank=bank;frame_start=1;base=bank?28'h400000:28'h200000;lane=0;assembled=0;strobes=0;
 @(negedge clk);frame_start=0;
end endtask
task pixel(input integer a); integer guard; begin
 @(negedge clk);write_addr=a;write_rgb=24'h431000+a;write_valid=1;guard=0;#1;
 while(!write_ready) begin @(negedge clk);guard=guard+1;if(guard>10000)fail("source stalled");end
 assembled[lane*32+:32]={8'b0,write_rgb};strobes[lane*4+:4]=4'hf;
 if(lane==7||a==255) begin exp_addr[et]=base+(a/8)*8;exp_data[et]=assembled;exp_strb[et]=strobes;et=et+1;lane=0;assembled=0;strobes=0;end
 else lane=lane+1;
 @(posedge clk);#1;write_valid=0;
end endtask
task waitdrain; integer guard; begin guard=0;while(!drained)begin @(negedge clk);guard=guard+1;if(guard>20000)fail("drain timeout");end if(eh!=et||ack_count!=accept_count)fail("early drained");end endtask
task abortit;begin @(negedge clk);abort_frame=1;@(negedge clk);abort_frame=0;lane=0;assembled=0;strobes=0;end endtask
initial begin
 #30;rst_n=1;ui_rst_n=1;repeat(8)@(negedge clk);
 start(0);for(n=0;n<256;n=n+1)begin pixel(n);frame_bank=~frame_bank;end waitdrain();if(fault)fail("frame0 fault");
 start(1);for(n=0;n<256;n=n+1)pixel(n);waitdrain();if(fault)fail("frame1 fault");
 $display("PASS two complete frames random clocks/stalls/delayed ACKs and immutable bank");
 pixel(256);if(!fault)fail("pixel after frame end not faulted");abortit();
 rsp_write=0;start(0);for(n=0;n<8;n=n+1)pixel(n);waitdrain();if(!fault)fail("bad response type not faulted");abortit();rsp_write=1;
 hold_commands=1;start(0);for(n=0;n<40;n=n+1)pixel(n);pause_source=1;hold_commands=0;#3000;if(!dut.afull)fail("ACK credit saturation not reached");pause_source=0;waitdrain();$display("PASS ACK FIFO full with stopped source clock, no ACK loss");
 start(0);pixel(0);pixel(1);abortit();waitdrain();if(write_ready)fail("abort not sticky");
 hold_acks=1;start(1);for(n=0;n<24;n=n+1)pixel(n);repeat(20)@(negedge clk);oldack=ack_count;
 abortit();if(drained)fail("abort lost queued writes");repeat(20)@(negedge clk);if(drained)fail("early completion before late ACK");
 @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;if(!fault)fail("busy frame_start not faulted");
 abortit();if(fault)fail("abort must clear fault");hold_acks=0;waitdrain();if(ack_count==oldack)fail("late ACK lost");
 start(0);for(n=0;n<256;n=n+1)pixel(n);waitdrain();
 $display("PASS partial/queued/inflight abort, late ACK, busy start, next frame");
 start(0);@(negedge clk);write_valid=1;write_addr=1;@(posedge clk);#1;write_valid=0;if(!fault)fail("wrong order accepted");abortit();waitdrain();
 hold_acks=1;start(0);for(n=0;n<16;n=n+1)pixel(n);repeat(20)@(negedge clk);
 rst_n=0;ui_rst_n=0;write_valid=0;qh=0;qt=0;eh=0;et=0;accept_count=0;ack_count=0;#30;rst_n=1;ui_rst_n=1;hold_acks=0;repeat(10)@(negedge clk);if(!drained)fail("reset not drained");
 start(1);for(n=0;n<256;n=n+1)pixel(n);waitdrain();if(fault)fail("postreset fault");
 $display("PASS writer all tests commands=%0d acks=%0d",accept_count,ack_count);$finish;
end
initial begin #3000000; fail("watchdog");end
endmodule


