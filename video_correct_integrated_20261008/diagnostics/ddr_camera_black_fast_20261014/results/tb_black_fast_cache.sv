`timescale 1ns/1ps
module tb_black_fast_cache;
 reg clk=0,rst_n=0,invalidate=0,mem_valid=0;
 always #5 clk=~clk;
 reg [23:0] mem_addr=0;
 reg [27:0] base_word_addr=0;
 wire mem_ready,mem_rsp_valid,cmd_valid,cmd_write;
 wire [23:0] mem_rgb;
 wire [27:0] cmd_addr;
 wire [255:0] cmd_wdata;
 wire [31:0] cmd_wstrb;
 reg [31:0] rng=32'hbd927cc1;
 reg pending=0,held=0,zero_response=0,bad_response=0;
 integer delay_left=0,epoch=1,saved_epoch=1,reads=0,requests=0;
 reg [27:0] saved_addr=0,held_addr=0;
 wire cmd_ready=rst_n&&!pending&&rng[2:0]!=0;
 wire rsp_valid=rst_n&&((zero_response&&cmd_valid&&cmd_ready)||(pending&&delay_left==0));
 wire rsp_write=bad_response;
 wire [255:0] rsp_rdata=beat(pending?saved_addr:cmd_addr,pending?saved_epoch:epoch);
 reg test_passed=0;
 ddr_pixel_cache dut(.*);

 function automatic [23:0] pixel(input [27:0] a,input integer e);
  pixel={8'((a+e*17)&255),8'(((a>>8)+e*37)&255),8'(((a>>16)+e*71)&255)};
 endfunction
 function automatic [255:0] beat(input [27:0] a,input integer e);
  reg [255:0] result;
  begin
   for(integer i=0;i<8;i=i+1)result[i*32+:32]={8'ha5,pixel(a+i,e)};
   beat=result;
  end
 endfunction

 always @(posedge clk)begin
  rng<={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
  if(!rst_n)begin pending<=0;delay_left<=0;held<=0;end
  else begin
   if(held&&(!cmd_valid||cmd_addr!==held_addr))$fatal(1,"DDR command changed while stalled");
   held<=cmd_valid&&!cmd_ready;
   if(cmd_valid&&!cmd_ready)held_addr<=cmd_addr;
   if(cmd_valid&&cmd_ready)begin
    if(pending||cmd_write||cmd_addr[2:0]!=0||cmd_wdata!=0||cmd_wstrb!=0)$fatal(1,"invalid cache command");
    reads=reads+1;
    if(!zero_response)begin pending<=1;saved_addr<=cmd_addr;saved_epoch<=epoch;delay_left<=1+rng[5:3];end
   end else if(pending)begin
    if(delay_left!=0)delay_left<=delay_left-1;
    else pending<=0;
   end
  end
 end

 task automatic read_pixel(input [27:0] base,input [23:0] address,input integer expect_epoch);
  integer timeout;
  begin
   @(negedge clk);base_word_addr=base;mem_addr=address;mem_valid=1;
   do begin @(posedge clk);end while(!mem_ready);
   #1;
   @(negedge clk);mem_valid=0;
   timeout=0;
   while(!mem_rsp_valid)begin @(negedge clk);timeout=timeout+1;if(timeout>100)$fatal(1,"missing response");end
   if(mem_rgb!==pixel(base+address,expect_epoch))$fatal(1,"RGB mismatch base=%h index=%h epoch=%0d got=%h",base,address,expect_epoch,mem_rgb);
   requests=requests+1;
   @(negedge clk);
   if(mem_rsp_valid)$fatal(1,"response pulse duplicated");
  end
 endtask
 task clear_cache;
  begin @(negedge clk);invalidate=1;@(negedge clk);invalidate=0;end
 endtask
 task common_reset;
  begin @(negedge clk);rst_n=0;mem_valid=0;repeat(3)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);end
 endtask

 integer before_reads;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  read_pixel(0,0,epoch);read_pixel(0,7,epoch);read_pixel(0,8,epoch);read_pixel(0,16,epoch);
  before_reads=reads;read_pixel(0,0,epoch);
  if(reads!=before_reads)$fatal(1,"L2 failed to retain beat evicted from hot cache");
  for(integer lane=0;lane<8;lane=lane+1)read_pixel(28'h0400000,24'd64+lane,epoch);
  clear_cache();before_reads=reads;
  // Three lines map to one set; a hot-cache hit must update that set's LRU.
  read_pixel(0,0,epoch);read_pixel(0,1024,epoch);read_pixel(0,0,epoch);read_pixel(0,2048,epoch);
  read_pixel(0,0,epoch);read_pixel(0,1024,epoch);
  if(reads-before_reads!=4)$fatal(1,"set-conflict LRU/replacement read count wrong: %0d",reads-before_reads);
  // Same word index at different bases never aliases.
  read_pixel(28'h0100000,0,epoch);read_pixel(28'h0200000,0,epoch);read_pixel(28'h0100000,0,epoch);
  // A new source snapshot must invalidate both levels, even with identical addresses.
  epoch=2;clear_cache();read_pixel(0,0,epoch);
  // Invalidate an accepted miss. Return its accepted old data, then fetch new data.
  fork
   begin read_pixel(0,24'd34560,2);end
   begin wait(pending);@(negedge clk);invalidate=1;epoch=3;@(negedge clk);invalidate=0;end
  join
  before_reads=reads;read_pixel(0,24'd34560,3);
  if(reads!=before_reads+1)$fatal(1,"invalidated in-flight line was retained");
  // Invalidate before an L2 lookup can complete: the old RAM entry is unusable.
  clear_cache();read_pixel(0,1000,epoch);read_pixel(0,2000,epoch);read_pixel(0,3000,epoch);
  @(negedge clk);mem_addr=1000;mem_valid=1;
  @(posedge clk);#1;
  @(negedge clk);mem_valid=0;invalidate=1;epoch=4;
  @(negedge clk);invalidate=0;
  wait(mem_rsp_valid);#1;if(mem_rgb!==pixel(1000,4))$fatal(1,"lookup invalidate leaked old source data");
  @(negedge clk);@(negedge clk);
  // Zero-cycle DDR responses on accepted commands exercise the SEND completion path.
  zero_response=1;clear_cache();read_pixel(28'h0ffff00,24'hfffff8,epoch);zero_response=0;
  // A protocol write response returns black and must never poison a future hit.
  bad_response=1;@(negedge clk);mem_addr=123456;mem_valid=1;
  @(posedge clk);#1;@(negedge clk);mem_valid=0;
  wait(mem_rsp_valid);#1;if(mem_rgb!==0)$fatal(1,"unexpected write response did not return black");
  @(negedge clk);bad_response=0;@(negedge clk);
  before_reads=reads;read_pixel(28'h0ffff00,123456,epoch);
  if(reads!=before_reads+1)$fatal(1,"bad response line was retained");
  // Common reset cancels both cache and memory-side outstanding state.
  @(negedge clk);base_word_addr=0;mem_addr=54321;mem_valid=1;
  wait(pending);common_reset();epoch=5;read_pixel(0,54321,epoch);
  for(integer n=0;n<512;n=n+1)begin
   read_pixel((n%3)*28'h0100000,24'((n*419+7)%65536),epoch);
   read_pixel((n%3)*28'h0100000,24'((n*419+7)%65536),epoch);
  end
  $display("BLACK_FAST_CACHE_PASS requests=%0d reads=%0d epochs=%0d",requests,reads,epoch);
  test_passed=1;$finish;
 end
 initial begin #2000000;$fatal(1,"cache test timeout");end
endmodule
