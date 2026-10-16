`timescale 1ns/1ps
module tb_quad_tile;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,req_valid=0,req_inside=1,req_nearest=0,rsp_ready=1;
 reg[27:0]req_base=0;reg[31:0]req_generation=1;reg[11:0]req_x=0,req_y=0;reg[23:0]req_tag=0;reg[7:0]req_fx=0,req_fy=0;
 wire req_ready,rsp_valid,rsp_inside;wire[23:0]rsp_p00,rsp_p10,rsp_p01,rsp_p11,rsp_tag;wire[7:0]rsp_fx,rsp_fy;wire[31:0]rsp_generation;
 wire cmd_valid,cmd_block,fault;wire[27:0]cmd_addr;reg cmd_ready=1,mem_valid=0,mem_write=0;reg[2047:0]mem_data=0;
`ifdef DEFAULT_LINES
 localparam CACHE_LINES=64;
`else
 localparam CACHE_LINES=8;
`endif
 ddr_quad_tile_cache #(.SRC_W(128),.SRC_H(48),.LINES(CACHE_LINES),.WATCHDOG_CYCLES(128)) dut(.*,.rsp_block(mem_data),.mem_rsp_valid(mem_valid),.mem_rsp_write(mem_write));
 integer cyc=0,accepted=0,returned=0,commands=0,delay_count=0,mem_epoch=0;reg pending=0,hang=0;reg[27:0]saved_addr;
 reg random_stalls=0;integer serial=0;integer expected_tag[0:4095];reg[31:0]expected_gen[0:4095];reg[7:0]expected_fx[0:4095],expected_fy[0:4095];reg expected_inside[0:4095];reg[23:0]expected[0:4095][0:3];
 function automatic[23:0]pixel(input integer word_address,input integer epoch);
  pixel=((word_address*32'h012345)+epoch*32'h543211)^32'h70a53c;
 endfunction
 reg stalled_rsp=0;reg[168:0]held_rsp;
 always @(posedge clk)begin
  if(rst_n&&stalled_rsp&&{rsp_generation,rsp_inside,rsp_p00,rsp_p10,rsp_p01,rsp_p11,rsp_tag,rsp_fx,rsp_fy}!==held_rsp)$fatal(1,"response changed while stalled");
  stalled_rsp<=rst_n&&rsp_valid&&!rsp_ready;
  held_rsp<={rsp_generation,rsp_inside,rsp_p00,rsp_p10,rsp_p01,rsp_p11,rsp_tag,rsp_fx,rsp_fy};
  cyc<=cyc+1;mem_valid<=0;
  if(!rst_n)begin pending<=0;delay_count<=0;end
  else begin
   if(cmd_valid&&cmd_ready)begin
    if(pending||!cmd_block||cmd_addr[5:0]!=0)$fatal(1,"command protocol/alignment");
    commands<=commands+1;pending<=1;saved_addr<=cmd_addr;delay_count<=3+(commands%7);
   end
   if(pending&&!hang)begin
    if(delay_count>0)delay_count<=delay_count-1;
    else begin
     for(integer w=0;w<64;w=w+1)mem_data[w*32+:32]<={8'h0,pixel(saved_addr+w,mem_epoch)};
     mem_valid<=1;pending<=0;
    end
   end
   if(req_valid&&req_ready)begin
    expected_tag[accepted]=req_tag;expected_gen[accepted]=req_generation;expected_fx[accepted]=req_fx;expected_fy[accepted]=req_fy;expected_inside[accepted]=req_inside;
    for(integer p=0;p<4;p=p+1)begin
     automatic integer xx,yy;
     xx=req_x+((p%2)&&!req_nearest&&req_x<127);yy=req_y+((p/2)&&!req_nearest&&req_y<47);
     expected[accepted][p]=req_inside?pixel(req_base+yy*128+xx,mem_epoch):0;
    end
    accepted=accepted+1;
   end
   if(rsp_valid&&rsp_ready)begin
    if(returned>=accepted)$fatal(1,"unowned response");
    if(rsp_tag!==expected_tag[returned]||rsp_generation!==expected_gen[returned]||rsp_fx!==expected_fx[returned]||rsp_fy!==expected_fy[returned]||rsp_inside!==expected_inside[returned])$fatal(1,"metadata mismatch at %0d",returned);
    if(rsp_p00!==expected[returned][0]||rsp_p10!==expected[returned][1]||rsp_p01!==expected[returned][2]||rsp_p11!==expected[returned][3])$fatal(1,"RGB mismatch %0d got %h/%h/%h/%h expected %h/%h/%h/%h",returned,rsp_p00,rsp_p10,rsp_p01,rsp_p11,expected[returned][0],expected[returned][1],expected[returned][2],expected[returned][3]);
    returned=returned+1;
   end
  end
 end
 always @(negedge clk)if(random_stalls)begin rsp_ready=($urandom_range(0,4)!=0);cmd_ready=($urandom_range(0,3)!=0);end
 task send(input integer x,input integer y,input bit inside_v,input bit nn);
  begin
   @(negedge clk);req_valid=1;req_x=x;req_y=y;req_inside=inside_v;req_nearest=nn;req_tag=serial;req_fx=serial*13;req_fy=serial*29;serial=serial+1;
   do @(posedge clk);while(!req_ready);
   @(negedge clk);req_valid=0;
  end
 endtask
 task drain;
  begin while(returned<accepted)@(negedge clk);repeat(3)@(negedge clk);end
 endtask
 task burst64;
  begin
   @(negedge clk);req_valid=1;req_x=8;req_y=2;req_inside=1;req_nearest=0;
   for(integer n=0;n<64;n=n+1)begin
    req_tag=serial;req_fx=serial*13;req_fy=serial*29;serial=serial+1;
    do @(posedge clk);while(!req_ready);
    @(negedge clk);
   end
   req_valid=0;
  end
 endtask
 integer start_c,before_commands;
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  send(8,2,1,0);drain();start_c=cyc;burst64();drain();
  $display("NEW warm 64 quads cycles=%0d",cyc-start_c);
  if(cyc-start_c>100)$fatal(1,"warm throughput budget");
  // All combinations of DDR-word, tile and row boundaries, including four tiles.
  random_stalls=1;
  for(integer y=0;y<48;y=y+3)for(integer x=0;x<128;x=x+7)send(x,y,1,0);
  send(63,3,1,0);send(127,47,1,0);send(63,3,1,1);drain();
  before_commands=commands;
  for(integer n=0;n<20;n=n+1)send(4095,4095,0,0);
  drain();if(commands!=before_commands)$fatal(1,"outside requested memory");
  // Same bank, newly captured generation must not reuse old source pixels.
  mem_epoch=1;req_generation=2;send(63,3,1,0);send(8,2,1,0);drain();
  // Bank included in tag, even if generation is unchanged.
  req_base=8192;send(63,3,1,0);drain();
  req_base=0;send(8,2,1,0);drain();
  random_stalls=0;cmd_ready=1;rsp_ready=0;
  fork send(7,4,1,0);begin repeat(90)@(negedge clk);rsp_ready=1;end join
  drain();
  // Frame keys may change while preceding RAM/response stages still drain.
  for(integer n=0;n<16;n=n+1)begin
   req_generation=20+n;req_base=(n%2)*8192;send(7+n%3,3+n%4,1,0);
  end
  drain();req_base=0;
  if(fault)$fatal(1,"unexpected cache fault");
  $display("PASS quad tile RGB metadata/backpressure/eviction/generation/bank/edges %0d packets %0d commands",returned,commands);
  // No response must latch watchdog, then hard reset permits recovery.
  hang=1;req_generation=3;send(63,7,1,0);
  repeat(160)@(negedge clk);if(!fault)$fatal(1,"missing watchdog fault");
  rst_n=0;req_valid=0;repeat(5)@(negedge clk);accepted=0;returned=0;hang=0;rst_n=1;
  send(127,47,1,1);drain();if(fault)$fatal(1,"reset failed");
  $display("PASS watchdog and common reset recovery");
  // A write response cannot be mistaken for a completed source block.
  mem_write=1;req_generation=4;send(63,7,1,0);wait(fault);
  rst_n=0;repeat(5)@(negedge clk);accepted=0;returned=0;mem_write=0;rst_n=1;
  send(128,0,1,0);@(negedge clk);if(!fault)$fatal(1,"invalid coordinate accepted");
  $display("PASS invalid address and wrong response hard faults");$finish;
 end
 initial begin #10000000;$display("DEBUG a=%0d r=%0d fault=%b fs=%d sv=%b mv=%b rv=%b pending=%b hang=%b rst=%b",accepted,returned,fault,dut.fill_state,dut.s_valid,dut.m_valid,rsp_valid,pending,hang,rst_n);$fatal(1,"test timeout");end
endmodule
