`timescale 1ns/1ps
module tb_homography_solver;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,start=0;
 reg [11:0] x0,y0,x1,y1,x2,y2,x3,y3;
 wire busy,done,error;
 wire signed [39:0] h[0:8];reg signed [39:0] expected[0:8],last[0:8];
 homography_solver #(.SRC_W(4096),.SRC_H(4096),.OUT_W(320),.OUT_H(452))
  dut(clk,rst_n,start,x0,y0,x1,y1,x2,y2,x3,y3,busy,done,error,h[0],h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8]);
 integer f,n,ee,seen=0,cycles,logf;
 reg test_passed=0;
 initial begin
  f=$fopen("vectors/solver.txt","r");logf=$fopen("results/rtl_solver.csv","w");if(!f||!logf)$fatal(1,"SOLVER files");
  repeat(3)@(negedge clk);rst_n=1;
  while(!$feof(f))begin
   n=$fscanf(f,"%d %d %d %d %d %d %d %d %d %h %h %h %h %h %h %h %h %h\n",x0,y0,x1,y1,x2,y2,x3,y3,ee,expected[0],expected[1],expected[2],expected[3],expected[4],expected[5],expected[6],expected[7],expected[8]);
   if(n==18)begin
    for(integer k=0;k<9;k=k+1)last[k]=h[k];
    @(negedge clk);start=1;@(negedge clk);start=0;cycles=0;
    while(!done&&cycles<800)begin @(negedge clk);cycles=cycles+1;end
    if(!done||error!==ee[0])$fatal(1,"SOLVER status case %0d error=%0d expected=%0d",seen,error,ee);
    for(integer k=0;k<9;k=k+1)begin
     if(!ee&&h[k]!==expected[k])$fatal(1,"SOLVER coefficient case=%0d h[%0d] actual=%0d expected=%0d",seen,k,h[k],expected[k]);
     if(ee&&h[k]!==last[k])$fatal(1,"SOLVER corrupted last H on error");
    end
    $fwrite(logf,"%0d,%0d",seen,error);for(integer k=0;k<9;k=k+1)$fwrite(logf,",%0d",h[k]);$fwrite(logf,"\n");
    seen=seen+1;@(negedge clk);
   end else if(n!=-1&&n!=0)$fatal(1,"SOLVER malformed");
  end
  // A reset aborts the low-rate calculation.
  @(negedge clk);start=1;@(negedge clk);start=0;repeat(20)@(negedge clk);rst_n=0;
  repeat(3)@(negedge clk);rst_n=1;repeat(90)@(negedge clk);
  if(busy||done)$fatal(1,"SOLVER stale operation after reset");
  test_passed=1;$display("SOLVER_PASS %0d",seen);$fclose(f);$fclose(logf);$finish;
 end
 initial begin #1000000;$fatal(1,"SOLVER timeout");end
endmodule
