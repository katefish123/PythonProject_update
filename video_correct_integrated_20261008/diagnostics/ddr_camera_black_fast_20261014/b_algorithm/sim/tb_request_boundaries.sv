`timescale 1ns/1ps
// Sparse pixel source: verifies address units and numerical boundary behavior.
// 1080p and 4096 cases are representative regressions, not final A/C settings.
module request_boundary_case #(parameter SRC_W=640,SRC_H=480)(output reg passed=0);
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,iv=0,nearest=0,geometry=1;
 reg [11:0] dx=0,dy=0;
 reg signed [39:0] h[0:8];
 wire rv,ri,re;wire [23:0] tag,a00,a10,a01,a11;wire [7:0] fx,fy;
 reg pv=0,pi=0;reg [23:0] pt=0,p00=0,p10=0,p01=0,p11=0;reg [7:0] pfx=0,pfy=0;
 wire ov;wire [23:0] rgb,ot;
 perspective_core #(.SRC_W(SRC_W),.SRC_H(SRC_H)) dut(
  clk,rst_n,iv,nearest,geometry,dx,dy,h[0],h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8],
  rv,ri,re,tag,a00,a10,a01,a11,fx,fy,pv,pi,pt,p00,p10,p01,p11,pfx,pfy,ov,rgb,ot);
 reg solve_start=0;
 wire solve_busy,solve_done,solve_error;wire signed [39:0] solved[0:8];
 homography_solver #(.SRC_W(SRC_W),.SRC_H(SRC_H),.OUT_W(320),.OUT_H(452)) solver(
  clk,rst_n,solve_start,12'd20,12'd20,12'd639,12'd50,12'd639,12'd440,12'd20,12'd440,
  solve_busy,solve_done,solve_error,solved[0],solved[1],solved[2],solved[3],solved[4],solved[5],solved[6],solved[7],solved[8]);
 integer req_count=0,out_count=0,cycles;
 reg waiting=0,e_inside,e_error,request_seen;
 reg [23:0] e_tag,e00,e10,e01,e11,e_rgb;reg [7:0] e_fx,e_fy;

 function automatic [23:0] pixel(input [23:0] address);
  pixel={address[7:0],address[15:8],address[23:16]};
 endfunction
 function automatic [23:0] interpolate(input [23:0] q00,q10,q01,q11,input integer xf,yf);
  integer r,g,b;
  begin
   r=((q00[23:16]*(256-xf)+q10[23:16]*xf)*(256-yf)+(q01[23:16]*(256-xf)+q11[23:16]*xf)*yf)>>16;
   g=((q00[15:8]*(256-xf)+q10[15:8]*xf)*(256-yf)+(q01[15:8]*(256-xf)+q11[15:8]*xf)*yf)>>16;
   b=((q00[7:0]*(256-xf)+q10[7:0]*xf)*(256-yf)+(q01[7:0]*(256-xf)+q11[7:0]*xf)*yf)>>16;
   interpolate={r[7:0],g[7:0],b[7:0]};
  end
 endfunction
 always @(posedge clk) begin
  if(!rst_n)begin pv<=0;pi<=0;pt<=0;pfx<=0;pfy<=0;p00<=0;p10<=0;p01<=0;p11<=0;end
  else begin
   pv<=rv;pi<=ri;pt<=tag;pfx<=fx;pfy<=fy;
   if(rv&&ri)begin
    if(a00>=SRC_W*SRC_H||a10>=SRC_W*SRC_H||a01>=SRC_W*SRC_H||a11>=SRC_W*SRC_H)$fatal(1,"unsafe sparse address");
    p00<=pixel(a00);p10<=pixel(a10);p01<=pixel(a01);p11<=pixel(a11);
   end else begin p00<=0;p10<=0;p01<=0;p11<=0;end
  end
  #1;
  if(rst_n&&rv)begin
   if(!waiting||request_seen)$fatal(1,"extra request at SRC_W=%0d",SRC_W);
   if(tag!==e_tag||ri!==e_inside||re!==e_error||a00!==e00||a10!==e10||a01!==e01||a11!==e11||fx!==e_fx||fy!==e_fy)
    $fatal(1,"boundary request SRC_W=%0d tag=%0d inside=%0d error=%0d addresses=%0d,%0d,%0d,%0d",SRC_W,tag,ri,re,a00,a10,a01,a11);
   request_seen=1;req_count=req_count+1;
  end
  if(rst_n&&ov)begin
   if(!waiting||!request_seen||ot!==e_tag||rgb!==e_rgb)$fatal(1,"boundary output SRC_W=%0d tag=%0d rgb=%h expected=%h",SRC_W,ot,rgb,e_rgb);
   waiting=0;out_count=out_count+1;
  end
 end
 task identity;
  begin for(integer k=0;k<9;k=k+1)h[k]=0;h[0]=16777216;h[4]=16777216;h[8]=16777216;end
 endtask
 task probe(input integer x,y,nn,inside_value,error_value,aa,ab,ac,ad,xf,yf);
  begin
   @(negedge clk);
   e_inside=inside_value;e_error=error_value;e_tag=(y<<12)|x;
   e00=aa;e10=ab;e01=ac;e11=ad;e_fx=xf;e_fy=yf;
   e_rgb=inside_value?interpolate(pixel(aa),pixel(ab),pixel(ac),pixel(ad),xf,yf):24'd0;
   waiting=1;request_seen=0;iv=1;dx=x;dy=y;nearest=nn;
   @(negedge clk);iv=0;cycles=0;
   while(waiting&&cycles<40)begin @(negedge clk);cycles=cycles+1;end
   if(waiting)$fatal(1,"boundary response missing");
   repeat(3)@(negedge clk);
  end
 endtask
 initial begin
  identity();repeat(3)@(negedge clk);rst_n=1;
  probe(0,0,0,1,0,0,1,SRC_W,SRC_W+1,0,0);
  probe(SRC_W-1,0,0,1,0,SRC_W-1,SRC_W-1,2*SRC_W-1,2*SRC_W-1,0,0);
  probe(0,SRC_H-1,0,1,0,(SRC_H-1)*SRC_W,(SRC_H-1)*SRC_W+1,(SRC_H-1)*SRC_W,(SRC_H-1)*SRC_W+1,0,0);
  probe(SRC_W-1,SRC_H-1,0,1,0,SRC_W*SRC_H-1,SRC_W*SRC_H-1,SRC_W*SRC_H-1,SRC_W*SRC_H-1,0,0);
  probe(SRC_W-1,SRC_H-1,1,1,0,SRC_W*SRC_H-1,SRC_W*SRC_H-1,SRC_W*SRC_H-1,SRC_W*SRC_H-1,0,0);
  geometry=0;probe(1,1,0,0,0,0,0,0,0,0,0);geometry=1;
  h[2]=4194304;h[5]=8388608;
  probe(1,1,0,1,0,SRC_W+1,SRC_W+2,2*SRC_W+1,2*SRC_W+2,64,128);
  probe(1,1,1,1,0,2*SRC_W+1,2*SRC_W+1,2*SRC_W+1,2*SRC_W+1,0,0);
  probe(SRC_W-1,SRC_H-1,0,0,0,0,0,0,0,0,0);
  probe(SRC_W-1,SRC_H-1,1,0,0,0,0,0,0,0,0);
  identity();h[2]=-16777216;probe(0,0,0,0,1,0,0,0,0,0,0);
  identity();h[8]=1048576;probe(0,0,0,0,1,0,0,0,0,0,0);
  identity();h[2]=40'sd68719476736;probe(0,0,0,0,1,0,0,0,0,0,0);
  if(SRC_W<4096)begin
   identity();h[2]=SRC_W*40'sd16777216;probe(0,0,0,0,0,0,0,0,0,0,0);
  end
  if(SRC_W==640)begin
   @(negedge clk);solve_start=1;@(negedge clk);solve_start=0;cycles=0;
   while(!solve_done&&cycles<1000)begin @(negedge clk);cycles=cycles+1;end
   if(!solve_done||solve_error)$fatal(1,"edge quad solver rejected legal geometry");
   if(solved[0]!==40'sd35140317||solved[1]!==0||solved[2]!==40'sd335544320||solved[3]!==40'sd1780075||solved[4]!==40'sd15624014||solved[5]!==40'sd335544320||solved[6]!==40'sd4045||solved[7]!==0||solved[8]!==40'sd16777216)$fatal(1,"edge H characterization changed");
   for(integer k=0;k<9;k=k+1)h[k]=solved[k];
   // Quantized inverse map gives x=639+1/256 on this legal right edge.
   probe(319,0,0,0,0,0,0,0,0,0,0);
   probe(319,451,0,0,0,0,0,0,0,0,0);
  end
  if(req_count!=out_count)$fatal(1,"boundary counts");
  $display("BOUNDARY_CASE_PASS source=%0dx%0d requests=%0d outputs=%0d",SRC_W,SRC_H,req_count,out_count);
  passed=1;
 end
endmodule

module tb_request_boundaries;
 wire default_pass,hd_pass,max_pass;
 reg test_passed=0;
 request_boundary_case #(.SRC_W(640),.SRC_H(480)) defaults(default_pass);
 request_boundary_case #(.SRC_W(1920),.SRC_H(1080)) hd(hd_pass);
 request_boundary_case #(.SRC_W(4096),.SRC_H(4096)) maximum(max_pass);
 initial begin
  wait(default_pass&&hd_pass&&max_pass);test_passed=1;
  $display("BOUNDARIES_PASS sizes=640x480,1920x1080,4096x4096 sparse_addresses=yes edge_black_policy=characterized");
  $finish;
 end
 initial begin #100000;$fatal(1,"boundary timeout");end
endmodule
