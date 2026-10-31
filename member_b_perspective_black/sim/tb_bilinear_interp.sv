`timescale 1ns/1ps
module tb_bilinear_interp;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,iv=0,is_inside=0;
 reg [23:0] pix[0:3];reg [7:0] fx=0,fy=0;reg [23:0] tag=0;
 wire ov;wire [23:0] rgb,otag;
 bilinear_interp dut(clk,rst_n,iv,is_inside,pix[0],pix[1],pix[2],pix[3],fx,fy,tag,ov,rgb,otag);
 reg [23:0] expected[0:9999],value;
 integer accepted[0:9999];integer cycle=0,seen=0,sent=0,f,n,gap,logf;
 reg test_passed=0;
 always @(posedge clk)begin
  cycle=cycle+1;if(rst_n&&iv)accepted[tag]=cycle;
  #1;
  if(rst_n&&ov)begin
   if(rgb!==expected[otag])$fatal(1,"INTERP mismatch tag=%0d actual=%h expected=%h",otag,rgb,expected[otag]);
   if(cycle-accepted[otag]!=2)$fatal(1,"INTERP latency");
   $fdisplay(logf,"%0d,%06h",otag,rgb);seen=seen+1;
  end
 end
 initial begin
  f=$fopen("vectors/interp.txt","r");logf=$fopen("results/rtl_interp.csv","w");if(!f||!logf)$fatal(1,"INTERP files");
  repeat(3)@(negedge clk);rst_n=1;
  while(!$feof(f))begin
   @(negedge clk);iv=0;
   n=$fscanf(f,"%d %d %d %d %d %h %h %h %h %h\n",gap,tag,is_inside,fx,fy,pix[0],pix[1],pix[2],pix[3],value);
   if(n==10)begin expected[tag]=value;repeat(gap)@(negedge clk);iv=1;sent=sent+1;end
   else if(n!=-1&&n!=0)$fatal(1,"INTERP malformed");
  end
  @(negedge clk);iv=0;repeat(6)@(negedge clk);
  if(seen!=sent)$fatal(1,"INTERP count");
  test_passed=1;$display("INTERP_PASS %0d",seen);$fclose(f);$fclose(logf);$finish;
 end
 initial begin #200000;$fatal(1,"INTERP timeout");end
endmodule
