`timescale 1ns/1ps
module tb_ddr_capture;
 localparam IN_W=101,IN_H=35,SRC_W=32,SRC_H=16,WORDS=SRC_W*SRC_H/8;
 reg proc_clk=0,ui_clk=0,rx_clk=0;
 always #18.5 proc_clk=~proc_clk;
 always #4.0 ui_clk=~ui_clk;
 always #3.367 rx_clk=~rx_clk;
 reg rst_n=0,request_toggle=0,rx_vs=0,rx_de=0,manual_stall=0;
 reg [23:0] rx_rgb=0;
 wire fifo_full,fifo_empty,fifo_wr_en,fifo_rd_en,fifo_rd_valid;
 wire [284:0] fifo_wr_data,fifo_rd_data;
 wire rx_complete_toggle,rx_capture_ok,complete_toggle,capture_ok;
 wire cmd_valid,cmd_ready,cmd_write;
 wire [27:0] cmd_addr;
 wire [255:0] cmd_wdata;
 wire [31:0] cmd_wstrb;
 reg rsp_valid=0,rsp_write=0;
 reg [255:0] source_memory[0:WORDS-1];
 reg [255:0] accepted_memory[0:WORDS-1];
 reg [31:0] ui_tick=0;
 reg resp_pending=0;
 integer resp_delay=0;
 integer expected_seed=0,writes=0,reads=0,accepted_packets=0;
 integer x,y,j,txn;
 reg test_passed=0;
 wire ddr_ready=!manual_stall&&(ui_tick%7!=2)&&(ui_tick%11!=6);
 async_packet_fifo #(.DATA_WIDTH(285),.ADDR_BITS(5)) fifo(
  .wr_clk(rx_clk),.rd_clk(ui_clk),.rst_n(rst_n),.wr_en(fifo_wr_en),.wr_data(fifo_wr_data),.full(fifo_full),
  .rd_en(fifo_rd_en),.rd_data(fifo_rd_data),.rd_valid(fifo_rd_valid),.empty(fifo_empty));
 ddr_snapshot_capture #(.IN_W(IN_W),.IN_H(IN_H),.SRC_W(SRC_W),.SRC_H(SRC_H)) snapshot(
  .rx_clk(rx_clk),.rx_rst_n(rst_n),.rx_vs(rx_vs),.rx_de(rx_de),.rx_rgb(rx_rgb),
  .request_toggle(request_toggle),.rx_complete_toggle(rx_complete_toggle),.capture_ok(rx_capture_ok),
  .fifo_wr_en(fifo_wr_en),.fifo_wr_data(fifo_wr_data),.fifo_full(fifo_full));
 ddr_capture_writer #(.SRC_W(SRC_W),.SRC_H(SRC_H),.EMPTY_QUIET_CYCLES(4)) writer(
  .ui_clk(ui_clk),.ui_rst_n(rst_n),.request_toggle(request_toggle),.rx_complete_toggle(rx_complete_toggle),
  .rx_capture_ok(rx_capture_ok),.fifo_rd_en(fifo_rd_en),.fifo_empty(fifo_empty),.fifo_rd_data(fifo_rd_data),
  .fifo_rd_valid(fifo_rd_valid),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_write(cmd_write),
  .cmd_addr(cmd_addr),.cmd_wdata(cmd_wdata),.cmd_wstrb(cmd_wstrb),.rsp_valid(rsp_valid),.rsp_write(rsp_write),
  .complete_toggle(complete_toggle),.capture_ok(capture_ok));
 assign cmd_ready=ddr_ready;
 function [23:0] pixel_value(input integer seed,input integer px,input integer py);
  reg [7:0] r,g,b;
  begin
   r=seed*31+px*3+py;g=seed*17+py*5+px;b=seed*13+px+py*7;
   pixel_value={r,g,b};
  end
 endfunction
 function [255:0] expected_word(input integer seed,input integer word_index);
  integer q,sx,sy,b;
  reg [255:0] value;
  begin
   value=0;
   for(b=0;b<8;b=b+1)begin
    q=word_index*8+b;sx=(q%SRC_W)*IN_W/SRC_W;sy=(q/SRC_W)*IN_H/SRC_H;
    value[b*32 +:32]={8'd0,pixel_value(seed,sx,sy)};
   end
   expected_word=value;
  end
 endfunction
 always @(posedge rx_clk)if(rst_n&&fifo_wr_en&&!fifo_full)accepted_packets=accepted_packets+1;
 always @(posedge ui_clk)begin
  if(!rst_n)begin
   ui_tick<=0;rsp_valid<=0;rsp_write<=0;resp_pending<=0;resp_delay<=0;writes=0;reads=0;
  end else begin
   ui_tick<=ui_tick+1'b1;rsp_valid<=0;
   if(resp_pending)begin
    if(resp_delay==0)begin rsp_valid<=1;rsp_write<=1;resp_pending<=0;end
    else resp_delay<=resp_delay-1;
   end
   if(fifo_rd_en&&!fifo_empty)reads=reads+1;
   if(cmd_valid&&cmd_ready)begin
    if(resp_pending)$fatal(1,"writer issued a second DDR command before response");
    if(!cmd_write||cmd_wstrb!==32'hffffffff)$fatal(1,"invalid DDR write controls");
    if(writes>=WORDS)$fatal(1,"DDR write address overflow");
    if(cmd_addr!==28'(writes*8))$fatal(1,"DDR word address order mismatch got=%0d expected=%0d",cmd_addr,writes*8);
    if(cmd_wdata!==expected_word(expected_seed,writes))
     $fatal(1,"sample/pack mismatch seed=%0d word=%0d got=%h expected=%h",expected_seed,writes,cmd_wdata,expected_word(expected_seed,writes));
    source_memory[writes]<=cmd_wdata;accepted_memory[writes]<=cmd_wdata;writes=writes+1;
    resp_pending<=1;resp_delay<=1+(ui_tick%5);
   end
  end
 end
 task pulse_vs;
  begin
   @(negedge rx_clk);rx_de=0;rx_vs=1;
   @(negedge rx_clk);rx_vs=0;repeat(2)@(negedge rx_clk);
  end
 endtask
 task send_rows(input integer seed,input integer line_count,input integer short_line,input integer stall_last);
  integer width;
  begin
   pulse_vs();
   for(y=0;y<line_count;y=y+1)begin
    if(stall_last&&y==IN_H-3)manual_stall=1;
    width=(short_line&&y==5)?IN_W-1:IN_W;
    @(negedge rx_clk);rx_de=1;
    for(x=0;x<width;x=x+1)begin
     rx_rgb=pixel_value(seed,x,y);@(negedge rx_clk);
    end
    rx_de=0;rx_rgb=0;repeat(2)@(negedge rx_clk);
   end
  end
 endtask
 task close_frame;
  begin pulse_vs();end
 endtask
 task begin_transaction(input integer seed);
  begin
   expected_seed=seed;writes=0;reads=0;accepted_packets=0;
   @(negedge proc_clk);request_toggle=~request_toggle;
   repeat(6)@(negedge rx_clk);
  end
 endtask
 task wait_result(input integer want_ok);
  begin
   wait(complete_toggle==request_toggle);#1;
   if(capture_ok!==want_ok[0])$fatal(1,"capture status got=%b expected=%0d",capture_ok,want_ok);
   repeat(3)@(negedge ui_clk);
   if(!fifo_empty||fifo_rd_valid||resp_pending)$fatal(1,"acknowledged transaction left pending FIFO/DDR data");
  end
 endtask
 task run_good(input integer seed);
  integer pushes_before;
  begin
   manual_stall=0;begin_transaction(seed);
   send_rows(seed,IN_H,0,1);close_frame();
   wait(rx_complete_toggle==request_toggle);
   if(complete_toggle==request_toggle)$fatal(1,"writer completed before FIFO drain test");
   pushes_before=accepted_packets;
   // New unrelated RX data arrives while the first source remains owned by the writer.
   pulse_vs();
   @(negedge rx_clk);rx_de=1;rx_rgb=pixel_value(seed+77,0,0);
   repeat(IN_W)@(negedge rx_clk);
   rx_de=0;rx_rgb=0;
   if(accepted_packets!=pushes_before)$fatal(1,"unrequested next-frame pixels entered FIFO");
   if(complete_toggle==request_toggle)$fatal(1,"writer did not remain pending during source-stability check");
   manual_stall=0;wait_result(1);
   if(writes!=WORDS||reads!=WORDS)$fatal(1,"good counts writes=%0d reads=%0d expected=%0d",writes,reads,WORDS);
   $display("DDR_GOOD_PASS seed=%0d packets=%0d sampling=floor-nearest",seed,writes);
  end
 endtask
 task run_bad(input integer seed,input integer lines,input integer short_line,input integer overflow_case);
  integer before_toggle;
  begin
   manual_stall=overflow_case;before_toggle=complete_toggle;begin_transaction(seed);
   send_rows(seed,lines,short_line,0);close_frame();
   wait(rx_complete_toggle==request_toggle);
   if(overflow_case)repeat(20)@(negedge ui_clk);
   manual_stall=0;wait_result(0);
   if(complete_toggle!=request_toggle||complete_toggle==before_toggle&&request_toggle==before_toggle)
    $fatal(1,"failed capture did not acknowledge its request token");
   if((lines<IN_H||overflow_case)&&writes>=WORDS)$fatal(1,"failed scenario unexpectedly wrote a complete source");
   if(short_line&&!overflow_case&&lines==IN_H&&writes!=WORDS)$fatal(1,"short-line drain did not write all queued packets");
   $display("DDR_REJECT_PASS seed=%0d lines=%0d short_line=%0d overflow=%0d packets_written=%0d",seed,lines,short_line,overflow_case,writes);
  end
 endtask
 initial begin
  repeat(5)@(negedge proc_clk);rst_n=1;
  run_good(1);
  run_bad(2,IN_H,1,0);
  run_bad(3,10,0,0);
  run_bad(4,IN_H,0,1);
  // Reset while a capture and FIFO transaction are in flight; stale packets must vanish.
  manual_stall=1;begin_transaction(6);send_rows(6,8,0,0);
  rst_n=0;request_toggle=0;rx_vs=0;rx_de=0;rx_rgb=0;
  repeat(5)@(negedge proc_clk);rst_n=1;manual_stall=0;
  run_good(5);
  test_passed=1;$display("DDR_CAPTURE_PASS full_frame=1 short_line=1 short_frame=1 overflow=1 reset_recovery=1");$finish;
 end
 initial begin #100000000;$fatal(1,"DDR capture test timeout");end
endmodule



