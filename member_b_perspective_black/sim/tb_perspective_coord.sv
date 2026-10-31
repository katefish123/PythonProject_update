`timescale 1ns/1ps
module tb_perspective_coord;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,in_valid=0;
 reg [11:0] x=0,y=0;reg [24:0] tag=0;
 reg signed [39:0] h[0:8];
 wire valid,error;wire [19:0] sx,sy;wire [24:0] otag;
 perspective_coord dut(clk,rst_n,in_valid,x,y,tag,h[0],h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8],valid,error,sx,sy,otag);
 integer ex[0:9999],ey[0:9999],ee[0:9999],accepted[0:9999];
 integer cycle=0,seen=0,sent=0,f,logf,n,gap,qx,qy,err;
 reg test_passed=0;
 always @(posedge clk) begin
  cycle=cycle+1;
  if(rst_n&&in_valid) accepted[tag]=cycle;
  #1;
  if(rst_n&&valid) begin
   if(error!==ee[otag][0]||sx!==ex[otag][19:0]||sy!==ey[otag][19:0])
    $fatal(1,"COORD mismatch tag=%0d actual=%0d,%0d,%0d expected=%0d,%0d,%0d",otag,sx,sy,error,ex[otag],ey[otag],ee[otag]);
   if(cycle-accepted[otag]!=22) $fatal(1,"COORD latency %0d",cycle-accepted[otag]);
   $fdisplay(logf,"%0d,%0d,%0d,%0d",otag,sx,sy,error);seen=seen+1;
  end
 end
 initial begin
  f=$fopen("vectors/coord.txt","r");logf=$fopen("results/rtl_coord.csv","w");
  if(!f||!logf)$fatal(1,"missing vector/output file");
  for(integer i=0;i<9;i=i+1)h[i]=0;
  repeat(3)@(negedge clk);rst_n=1;
  while(!$feof(f))begin
   @(negedge clk);in_valid=0;
   n=$fscanf(f,"%d %d %d %d %h %h %h %h %h %h %h %h %h %d %d %d\n",gap,x,y,tag,h[0],h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8],qx,qy,err);
   if(n==16)begin
    ex[tag]=qx;ey[tag]=qy;ee[tag]=err;
    repeat(gap)@(negedge clk);
    in_valid=1;sent=sent+1;
   end else if(n!=-1&&n!=0)$fatal(1,"malformed coordinate vector: %0d",n);
  end
  @(negedge clk);in_valid=0;repeat(30)@(negedge clk);
  if(seen!=sent||sent<1000)$fatal(1,"COORD count seen=%0d sent=%0d",seen,sent);
  // Reset while requests are in flight: no stale valid may survive.
  in_valid=1;repeat(5)@(negedge clk);rst_n=0;in_valid=0;
  repeat(3)@(negedge clk);rst_n=1;
  repeat(25)begin @(negedge clk);if(valid)$fatal(1,"stale coordinate after reset");end
  test_passed=1;$display("COORD_PASS %0d",seen);$fclose(f);$fclose(logf);$finish;
 end
 initial begin #2000000;$fatal(1,"COORD timeout");end
endmodule
