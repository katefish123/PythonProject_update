`timescale 1ns/1ps
`include "examples/r50_18mm_calibration.vh"
module tb_lens_integration;
 localparam MAXN=2048;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,iv=0,nearest=0,geometry=1;
 reg [11:0] dx=0,dy=0;reg signed [39:0] h[0:8];
 wire rv,ri,re;wire [23:0] tag,a00,a10,a01,a11;wire [7:0] fx,fy;
 reg pv=0,pi=0;reg [23:0] pt=0,p00=0,p10=0,p01=0,p11=0;reg [7:0] pfx=0,pfy=0;
 wire ov;wire [23:0] rgb,ot;
 perspective_core #(.SRC_W(1920),.SRC_H(1080),.LENS_ENABLE(1),
  .LENS_FX_Q16(`LENS_FX_Q16),.LENS_FY_Q16(`LENS_FY_Q16),.LENS_CX_Q16(`LENS_CX_Q16),.LENS_CY_Q16(`LENS_CY_Q16),
  .LENS_INV_FX_Q30(`LENS_INV_FX_Q30),.LENS_INV_FY_Q30(`LENS_INV_FY_Q30),
  .LENS_K1_Q26(`LENS_K1_Q26),.LENS_K2_Q26(`LENS_K2_Q26),.LENS_P1_Q26(`LENS_P1_Q26),.LENS_P2_Q26(`LENS_P2_Q26)) dut(
  clk,rst_n,iv,nearest,geometry,dx,dy,h[0],h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8],
  rv,ri,re,tag,a00,a10,a01,a11,fx,fy,pv,pi,pt,p00,p10,p01,p11,pfx,pfy,ov,rgb,ot);
 integer xx[0:MAXN-1],yy[0:MAXN-1],nn[0:MAXN-1],gg[0:MAXN-1];
 reg signed [39:0] hh[0:MAXN-1][0:8];
 reg signed [39:0] th0,th1,th2,th3,th4,th5,th6,th7,th8;
 integer ein[0:MAXN-1],eer[0:MAXN-1],e00[0:MAXN-1],e10[0:MAXN-1],e01[0:MAXN-1],e11[0:MAXN-1];
 integer exf[0:MAXN-1],eyf[0:MAXN-1],ergb[0:MAXN-1];
 integer ready[0:MAXN-1],q_index[0:MAXN-1];
 integer fd,n=0,got,i,k,cycle=0,reqs=0,resps=0,outs=0,qhead=0,qtail=0,last_due=0,delay_cycles,dump;
 reg checking=0;reg test_passed=0;
 function automatic [23:0] pixel(input integer a);
  integer r,g,b;begin r=(a*17+3)&255;g=(a>>3)&255;b=((a*11)>>7)&255;pixel={r[7:0],g[7:0],b[7:0]};end
 endfunction
 always @(posedge clk) begin
  if(!rst_n)begin
   pv<=0;pi<=0;pt<=0;p00<=0;p10<=0;p01<=0;p11<=0;pfx<=0;pfy<=0;
   cycle=0;reqs=0;resps=0;outs=0;qhead=0;qtail=0;last_due=0;
  end else begin
   cycle=cycle+1;pv<=0;
   if(checking&&rv)begin
    if(reqs>=n)$fatal(1,"extra lens request");
    if(tag!==((yy[reqs]<<12)|xx[reqs])||ri!==ein[reqs][0]||re!==eer[reqs][0]||
       a00!==e00[reqs]||a10!==e10[reqs]||a01!==e01[reqs]||a11!==e11[reqs]||fx!==exf[reqs][7:0]||fy!==eyf[reqs][7:0])
      $fatal(1,"lens request %0d tag=%0d inside=%0d error=%0d addr=%0d,%0d,%0d,%0d weights=%0d,%0d",reqs,tag,ri,re,a00,a10,a01,a11,fx,fy);
    if(ri&&(a00>=1920*1080||a10>=1920*1080||a01>=1920*1080||a11>=1920*1080))$fatal(1,"unsafe lens cache address");
    delay_cycles=2+(reqs%7);if(cycle+delay_cycles<=last_due)last_due=last_due+1;else last_due=cycle+delay_cycles;
    ready[qtail]=last_due;q_index[qtail]=reqs;qtail=qtail+1;reqs=reqs+1;
   end
   if(checking&&qhead<qtail&&ready[qhead]<=cycle)begin
    k=q_index[qhead];pv<=1;pi<=ein[k][0];pt<=(yy[k]<<12)|xx[k];pfx<=exf[k][7:0];pfy<=eyf[k][7:0];
    p00<=ein[k]?pixel(e00[k]):0;p10<=ein[k]?pixel(e10[k]):0;p01<=ein[k]?pixel(e01[k]):0;p11<=ein[k]?pixel(e11[k]):0;
    qhead=qhead+1;resps=resps+1;
   end
   #1;
   if(checking&&ov)begin
    if(outs>=n||ot!==((yy[outs]<<12)|xx[outs])||rgb!==ergb[outs][23:0])$fatal(1,"lens RGB %0d tag=%0d value=%h expected=%h",outs,ot,rgb,ergb[outs][23:0]);
    $fwrite(dump,"%0d,%0d,%06x\n",outs,ot,rgb);outs=outs+1;
   end
  end
 end
 initial begin
  fd=$fopen("vectors/lens_integration.txt","r");if(!fd)$fatal(1,"missing lens integration vectors");
  while(!$feof(fd))begin
   if(n>=MAXN)$fatal(1,"too many lens integration vectors");
   got=$fscanf(fd,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
    xx[n],yy[n],nn[n],gg[n],th0,th1,th2,th3,th4,th5,th6,th7,th8,
    ein[n],eer[n],e00[n],e10[n],e01[n],e11[n],exf[n],eyf[n],ergb[n]);
   if(got==22)begin
    hh[n][0]=th0;hh[n][1]=th1;hh[n][2]=th2;hh[n][3]=th3;hh[n][4]=th4;
    hh[n][5]=th5;hh[n][6]=th6;hh[n][7]=th7;hh[n][8]=th8;n=n+1;
   end else if(got!=-1)$fatal(1,"bad lens integration vector row");
  end
  $fclose(fd);if(n<100)$fatal(1,"insufficient integration vectors");
  dump=$fopen("results/rtl_lens_video.csv","w");
  for(i=0;i<9;i=i+1)h[i]=0;h[0]=16777216;h[4]=16777216;h[8]=16777216;
  repeat(3)@(negedge clk);rst_n=1;
  // Cancel requests already in the H/lens pipeline, and clear the external cache with reset.
  for(i=0;i<27;i=i+1)begin @(negedge clk);iv=1;dx=i;dy=i;end
  @(negedge clk);iv=0;rst_n=0;repeat(3)@(negedge clk);rst_n=1;
  repeat(50)begin @(negedge clk);if(rv||ov)$fatal(1,"old request survived reset");end
  checking=1;
  for(i=0;i<n;i=i+1)begin
   @(negedge clk);iv=1;dx=xx[i];dy=yy[i];nearest=nn[i];geometry=gg[i];
   for(integer z=0;z<9;z=z+1)h[z]=hh[i][z];
   if(i%11==3)begin @(negedge clk);iv=0;end
  end
  @(negedge clk);iv=0;
  i=0;while(outs<n&&i<2000)begin @(negedge clk);i=i+1;end
  if(outs!=n||reqs!=n||resps!=n)$fatal(1,"lens integration counts %0d/%0d/%0d expected%0d",reqs,resps,outs,n);
  repeat(50)@(negedge clk);if(rv||ov)$fatal(1,"trailing lens request");
  $fclose(dump);test_passed=1;
  $display("LENS_INTEGRATION_PASS transactions=%0d mixed_modes=yes variable_cache_latency=yes reset_flush=yes",n);$finish;
 end
 initial begin #2000000;$fatal(1,"lens integration timeout");end
endmodule
