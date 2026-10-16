`timescale 1ns/1ps
module tb_quad_pipeline;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,req_valid=0,req_inside=1,req_nearest=0,rsp_ready=1;
 reg[27:0]req_base=0;reg[31:0]req_generation=1;reg[11:0]req_x=0,req_y=0;reg[23:0]req_tag=0;reg[7:0]req_fx=0,req_fy=0;
 wire req_ready,rsp_valid,rsp_inside;wire[23:0]rsp_p00,rsp_p10,rsp_p01,rsp_p11,rsp_tag;wire[7:0]rsp_fx,rsp_fy;wire[31:0]rsp_generation;
 wire cmd_valid,cmd_block,fault;wire[27:0]cmd_addr;reg cmd_ready=1,mem_valid=0,mem_write=0;reg[2047:0]mem_data=0;
`ifdef DEFAULT_LINES
 localparam CACHE_LINES=64;
`else
 localparam CACHE_LINES=64;
`endif
 ddr_quad_tile_cache #(.SRC_W(1920),.SRC_H(1080),.LINES(CACHE_LINES),.WATCHDOG_CYCLES(128)) dut(.*,.rsp_block(mem_data),.mem_rsp_valid(mem_valid),.mem_rsp_write(mem_write));
 integer cyc=0,accepted=0,returned=0,commands=0,delay_count=0,mem_epoch=0;reg pending=0,hang=0;reg[27:0]saved_addr;
 reg random_stalls=0;integer serial=0;integer expected_tag[0:16383];reg[31:0]expected_gen[0:16383];reg[7:0]expected_fx[0:16383],expected_fy[0:16383];reg expected_inside[0:16383];reg[23:0]expected[0:16383][0:3];
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
     xx=req_x+((p%2)&&!req_nearest&&req_x<1919);yy=req_y+((p/2)&&!req_nearest&&req_y<1079);
     expected[accepted][p]=req_inside?pixel(req_base+yy*1920+xx,mem_epoch):0;
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
 // Perturb only the combinational lookup, between clock edges. A registered
 // issue stage must isolate both acceptance capacity and RAM enable from it.
 task isolate_lookup;
  reg saved_ready,saved_read;reg[CACHE_LINES-1:0]saved_valid;
  begin
   @(negedge clk);req_valid=1;req_x=8;req_y=2;req_inside=1;req_nearest=0;req_tag=serial;serial=serial+1;
   do @(posedge clk);while(!req_ready);
   #1;saved_ready=req_ready;saved_read=dut.read_en;saved_valid=dut.line_valid;
   force dut.line_valid=0;
   #1;
   if(req_ready!==saved_ready||dut.read_en!==saved_read)$fatal(1,"LOOKUP_ISOLATION_REQUIRED current tags reach acceptance/RAM enable");
   release dut.line_valid;dut.line_valid=saved_valid;
   @(negedge clk);req_valid=0;drain();
  end
 endtask
 task warm512;
  begin
   @(negedge clk);req_valid=1;req_inside=1;req_nearest=0;
   for(integer n=0;n<512;n=n+1)begin
    req_x=8+n%7;req_y=n%3;req_tag=serial;req_fx=serial*13;req_fy=serial*29;serial=serial+1;
    @(posedge clk);if(!req_ready)$fatal(1,"warm hit acceptance bubble");
    @(negedge clk);
   end
   req_valid=0;drain();
  end
 endtask
`ifdef PIPELINE_CHECKS
 integer old_frame_with_future_s=0,fill_relookups=0,simultaneous_moves=0;
 always @(posedge clk)if(rst_n&&!fault)begin
  if(dut.l_valid&&dut.l_missing&&dut.s_valid&&{dut.s_generation,dut.s_base}!={dut.l_generation,dut.l_base})begin
   old_frame_with_future_s=old_frame_with_future_s+1;
   if(dut.frame_key!=={dut.l_generation,dut.l_base})$fatal(1,"future S invalidated current L miss frame");
  end
  if(dut.l_relookup)fill_relookups=fill_relookups+1;
  if(dut.s_advance&&dut.l_advance&&dut.m_complete)simultaneous_moves=simultaneous_moves+1;
 end
`endif
 integer start_c,before_commands;
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  send(8,2,1,0);drain();isolate_lookup();start_c=cyc;warm512();if(cyc-start_c>530)$fatal(1,"warm512 throughput budget");start_c=cyc;burst64();drain();
  $display("NEW warm 64 quads cycles=%0d",cyc-start_c);
  if(cyc-start_c>100)$fatal(1,"warm throughput budget");
  // All combinations of DDR-word, tile and row boundaries, including four tiles.
  random_stalls=1;
  for(integer y=0;y<48;y=y+3)for(integer x=0;x<128;x=x+7)send(x,y,1,0);
  send(63,3,1,0);send(1919,1079,1,0);send(63,3,1,1);drain();
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
  // Fill all64 ways, then evict/relookup four-corner quads under random stalls.
  random_stalls=1;
  for(integer n=0;n<96;n=n+1)send((n%30)*64+63,((n/30)%3)*4+3,1,0);
  drain();random_stalls=0;cmd_ready=1;rsp_ready=1;
  // Keep a cold old-frame miss in L while a future frame waits in S.
  req_generation=100;req_base=0;
  send(1918,1078,1,0);req_generation=101;req_base=28'h0800000;send(63,3,1,0);drain();
  // Old-frame last hit read must complete before new frame invalidation/fill.
  req_generation=102;req_base=0;send(8,2,1,0);drain();rsp_ready=0;
  fork begin send(8,2,1,0);send(9,2,1,0);send(10,2,1,0);req_generation=103;req_base=28'h0800000;send(63,3,1,0);end
   begin repeat(100)@(negedge clk);rsp_ready=1;end join
  drain();
  // Frame keys may change while preceding RAM/response stages still drain.
  for(integer n=0;n<16;n=n+1)begin
   req_generation=20+n;req_base=(n%2)*28'h0800000;send(7+n%3,3+n%4,1,0);
  end
  drain();req_base=0;
  if(fault)$fatal(1,"unexpected cache fault");
  `ifdef PIPELINE_CHECKS
  if(old_frame_with_future_s==0||fill_relookups==0||simultaneous_moves<100)$fatal(1,"pipeline coverage missing old/future=%0d relookup=%0d moves=%0d",old_frame_with_future_s,fill_relookups,simultaneous_moves);
  $display("PASS registered lookup old-frame/future-S=%0d fill-relookups=%0d simultaneous-S/L/M=%0d",old_frame_with_future_s,fill_relookups,simultaneous_moves);
`endif
  $display("PASS quad pipeline64 native dimensions RGB/metadata/protection/eviction/generation/bank/edges %0d packets %0d commands",returned,commands);
  // No response must latch watchdog, then hard reset permits recovery.
  hang=1;req_generation=3;send(63,7,1,0);
  repeat(160)@(negedge clk);if(!fault)$fatal(1,"missing watchdog fault");
  rst_n=0;req_valid=0;repeat(5)@(negedge clk);accepted=0;returned=0;hang=0;rst_n=1;
  send(127,47,1,1);drain();if(fault)$fatal(1,"reset failed");
  $display("PASS watchdog and common reset recovery");
  // A write response cannot be mistaken for a completed source block.
  mem_write=1;req_generation=4;send(63,7,1,0);wait(fault);
  rst_n=0;repeat(5)@(negedge clk);accepted=0;returned=0;mem_write=0;rst_n=1;
  send(1920,0,1,0);@(negedge clk);if(!fault)$fatal(1,"invalid coordinate accepted");
  $display("PASS invalid address and wrong response hard faults");$finish;
 end
 initial begin #10000000;$display("DEBUG a=%0d r=%0d fault=%b fs=%d sv=%b mv=%b rv=%b pending=%b hang=%b rst=%b",accepted,returned,fault,dut.fill_state,dut.s_valid,dut.m_valid,rsp_valid,pending,hang,rst_n);$fatal(1,"test timeout");end
endmodule
