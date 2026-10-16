`timescale 1ns/1ps
module tb_capture_writer_timing;
 reg clk=0,rst_n=0;always #4 clk=~clk;
 reg packet_valid=0;wire packet_ready;reg[319:0]packet_data=0;
 wire cmd_valid,cmd_write;reg cmd_ready=0;wire[27:0]cmd_addr;wire[255:0]cmd_wdata;
 wire[31:0]cmd_wstrb;wire[2047:0]cmd_burst_data;
 reg rsp_valid=0,rsp_write=1;wire terminal_valid;reg terminal_ready=0;wire[37:0]terminal_data;wire fault;
 continuous_capture_writer #(.SRC_W(128),.SRC_H(1)) dut(.*);
 integer commands=0,terminals=0,acks=0,stalled_packets=0;
 integer cycles=0,previous_accept_cycle=-10,adjacent_data_end=0;reg[1:0]previous_kind=0;
 integer frame_commands=0;reg eb=0;reg[31:0]eg=0;
 reg held_command=0,held_terminal=0;reg[2075:0]held_cmd;reg[37:0]held_term;
 function[31:0]pixel_word(input reg b,input[31:0]g,input integer a);
  pixel_word=(g*131+a*17+b*19)&32'h00ffffff;
 endfunction
 function[319:0]record(input[1:0]kind,input reg b,input[31:0]g,input integer a,input reg ok,input[3:0]why);
  reg[255:0]data;begin
  for(integer k=0;k<8;k=k+1)data[k*32+:32]=pixel_word(b,g,a+k);
  record={kind,b,g,24'(a),ok,why,data};end
 endfunction
 always @(posedge clk)begin
  cycles=cycles+1;
  if(!rst_n)begin held_command<=0;held_terminal<=0;end
  else begin
   if(packet_valid&&!packet_ready)stalled_packets=stalled_packets+1;
   if(packet_valid&&packet_ready)begin
    if(packet_data[319:318]==2&&previous_kind==1&&cycles==previous_accept_cycle+1)adjacent_data_end=adjacent_data_end+1;
    previous_kind=packet_data[319:318];previous_accept_cycle=cycles;
   end
   if(held_command&&(!cmd_valid||{cmd_addr,cmd_burst_data}!==held_cmd))$fatal(1,"owned command changed under backpressure");
   if(held_terminal&&(!terminal_valid||terminal_data!==held_term))$fatal(1,"terminal identity changed under backpressure");
   held_command<=cmd_valid&&!cmd_ready;held_cmd<={cmd_addr,cmd_burst_data};
   held_terminal<=terminal_valid&&!terminal_ready;held_term<=terminal_data;
   if(cmd_valid&&cmd_ready)begin
    if(!cmd_write||cmd_wstrb!==32'hffffffff||cmd_addr!==(eb?28'h0800000:28'd0)+frame_commands*64)$fatal(1,"burst bank/address/strobe mismatch");
    for(integer k=0;k<64;k=k+1)
     if(cmd_burst_data[k*32+:32]!==pixel_word(eb,eg,frame_commands*64+k))$fatal(1,"burst payload mismatch lane=%0d gen=%0d",k,eg);
    if(cmd_wdata!==cmd_burst_data[255:0])$fatal(1,"first beat mismatch");
    commands=commands+1;frame_commands=frame_commands+1;
   end
   if(rsp_valid)acks=acks+1;
   if(terminal_valid&&terminal_ready)terminals=terminals+1;
  end
 end
 task tick;begin @(posedge clk);#0.2;end endtask
 task send(input[319:0]p);
  integer timeout;begin
   @(negedge clk);packet_valid=1;packet_data=p;timeout=0;
   begin:wait_accept
    forever begin @(posedge clk);if(packet_ready)begin #0.2;disable wait_accept;end
     timeout=timeout+1;if(timeout>500)$fatal(1,"packet blocked too long");end
   end
   packet_valid=0;
  end
 endtask
 task begin_frame(input reg b,input[31:0]g);
  begin eb=b;eg=g;frame_commands=0;send(record(0,b,g,0,1,0));end
 endtask
 task consume_command(input integer delay_ack,input reg same_edge);
  begin
   wait(cmd_valid);repeat(5)tick();@(negedge clk);cmd_ready=1;
   if(same_edge)begin rsp_valid=1;rsp_write=1;end
   tick();@(negedge clk);cmd_ready=0;rsp_valid=0;
   if(!same_edge)begin
    repeat(delay_ack)begin tick();if(terminal_valid)$fatal(1,"terminal before owned ACK");end
    @(negedge clk);rsp_valid=1;rsp_write=1;tick();@(negedge clk);rsp_valid=0;
   end
  end
 endtask
 task terminal(input reg ok,input[3:0]why,input integer expected_commands);
  begin
   wait(terminal_valid);#0.2;
   if(terminal_data!=={eb,eg,ok,why}||frame_commands!=expected_commands)$fatal(1,"terminal mismatch got=%h expected=%h commands=%0d",terminal_data,{eb,eg,ok,why},frame_commands);
   repeat(9)tick();@(negedge clk);terminal_ready=1;tick();@(negedge clk);terminal_ready=0;
  end
 endtask
 task hard_reset;
  begin
   @(negedge clk);rst_n=0;packet_valid=0;cmd_ready=0;rsp_valid=0;terminal_ready=0;
   repeat(3)tick();@(negedge clk);rst_n=1;repeat(3)tick();
   if(cmd_valid||terminal_valid||fault||!packet_ready)$fatal(1,"hard reset failed to flush all stages");
  end
 endtask
 task good_frame(input reg b,input[31:0]g,input reg same_edge);
  begin
   begin_frame(b,g);
   fork
    begin for(integer n=0;n<16;n=n+1)send(record(1,b,g,n*8,1,0));send(record(2,b,g,0,1,0));end
    begin consume_command(13,same_edge);consume_command(17,same_edge);terminal(1,0,2);end
   join
  end
 endtask
 initial begin
  hard_reset();begin_frame(0,11);
  for(integer n=0;n<8;n=n+1)send(record(1,0,11,n*8,1,0));
  repeat(3)tick();
  if(!cmd_valid||!packet_ready)$fatal(1,"ELASTIC_PACKET_CAPACITY_REQUIRED blocked burst must retain one next record");
  send(record(1,0,11,64,1,0));repeat(3)tick();
  if(packet_ready)$fatal(1,"elastic stage accepted beyond its credit");
  fork
   begin for(integer n=9;n<16;n=n+1)send(record(1,0,11,n*8,1,0));send(record(2,0,11,0,1,0));end
   begin consume_command(21,0);consume_command(31,0);terminal(1,0,2);end
  join
  if(stalled_packets==0)$fatal(1,"packet queue-full backpressure was not exercised");
  $display("PASS elastic full, immutable command, delayed ACK, last DATA followed by END and terminal backpressure");
  begin_frame(1,29);
  for(integer n=0;n<3;n=n+1)send(record(1,1,29,n*8,1,0));send(record(2,1,29,0,0,12));terminal(0,12,0);
  $display("PASS partial rejected frame cannot emit incomplete native burst");
  begin_frame(0,43);
  fork
   begin
    for(integer n=0;n<8;n=n+1)send(record(1,0,43,n*8,1,0));
    send(record(1,0,44,64,1,0));
    for(integer n=9;n<16;n=n+1)send(record(1,0,43,n*8,1,0));send(record(2,0,43,0,1,0));
   end
   begin consume_command(35,0);terminal(0,14,1);end
  join
  if(!fault)$fatal(1,"wrong generation did not flag fault");
  $display("PASS generation mismatch cannot change owned burst or publish before late ACK");
  hard_reset();begin_frame(1,57);
  for(integer n=0;n<8;n=n+1)send(record(1,1,57,n*8,1,0));
  wait(cmd_valid);send(record(2,1,57,0,0,12));hard_reset();
  if(cmd_valid||terminal_valid)$fatal(1,"SEND reset retained owned/staged packet");
  good_frame(0,61,1);
  begin_frame(1,73);
  for(integer n=0;n<8;n=n+1)send(record(1,1,73,n*8,1,0));
  wait(cmd_valid);@(negedge clk);cmd_ready=1;tick();@(negedge clk);cmd_ready=0;
  send(record(2,1,73,0,0,12));hard_reset();
  good_frame(1,89,0);
  $display("PASS common reset during SEND and WAIT_ACK flushes stage then bank/generation recovery");
  if(adjacent_data_end==0)$fatal(1,"END did not immediately follow DATA on consecutive accepted cycles");
  $display("PASS CAPTURE_WRITER_TIMING commands=%0d acks=%0d terminals=%0d stalled_packets=%0d adjacent_data_end=%0d",commands,acks,terminals,stalled_packets,adjacent_data_end);$finish;
 end
 initial begin #200000;$fatal(1,"writer test timeout state=%0d",dut.state);end
endmodule
