`timescale 1ns/1ps
module tb_legacy_serial;
 reg clk=0; always #4 clk=~clk;
 reg rst_n=0,valid=0; reg[23:0]addr=0; wire ready,rv;wire[23:0]rgb;
 wire cv;wire[27:0]ca; reg cr=0;reg[255:0]data=0;
 ddr_pixel_cache dut(.clk(clk),.rst_n(rst_n),.invalidate(1'b0),.mem_valid(valid),.mem_ready(ready),.mem_addr(addr),.mem_rsp_valid(rv),.mem_rgb(rgb),.base_word_addr(28'd0),.cmd_valid(cv),.cmd_ready(1'b1),.cmd_write(),.cmd_addr(ca),.cmd_wdata(),.cmd_wstrb(),.rsp_valid(cr),.rsp_write(1'b0),.rsp_rdata(data));
 integer cycle=0,i,j,start_cycle;reg[23:0]a;
 always @(posedge clk) begin
  cycle<=cycle+1;cr<=cv;
  if(cv)for(integer k=0;k<8;k=k+1)data[k*32+:32]<=ca+k;
 end
 task pixel(input[23:0]v);
  begin @(negedge clk);valid=1;addr=v;
   do @(posedge clk);while(!ready);
   @(negedge clk);valid=0;
   while(!rv)@(negedge clk);
   if(rgb!==v)$fatal(1,"legacy pixel incorrect %h %h",v,rgb);
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;
  // Two cache-line quad stays hot; this isolates serial per-texel overhead.
  for(j=0;j<2;j=j+1)begin pixel(8);pixel(9);pixel(72);pixel(73);end
  start_cycle=cycle;
  for(i=0;i<64;i=i+1)begin pixel(8);pixel(9);pixel(72);pixel(73);end
  $display("LEGACY functional PASS quads=64 cycles=%0d",cycle-start_cycle);
  if(cycle-start_cycle>100)$fatal(1,"THROUGHPUT_REQUIRED 64 warm quads in <=100 UI cycles; serial DDR cache is insufficient");
  $finish;
 end
endmodule
