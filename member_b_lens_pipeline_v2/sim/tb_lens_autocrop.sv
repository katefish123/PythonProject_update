`timescale 1ns/1ps
`include "examples/r50_18mm_viewport.vh"
module tb_lens_autocrop;
 localparam MAXN=30000;
 localparam BOUNDARY_N=2*`SAFE_DST_W+2*`SAFE_DST_H-4;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,iv=0,nearest=0;
 reg [11:0] dx=0,dy=0;
 wire rv,ri,re;wire [23:0] tag,a00,a10,a01,a11;wire [7:0] fx,fy;
 reg pv=0,pi=0;reg [23:0] pt=0,p00=0,p10=0,p01=0,p11=0;reg [7:0] pfx=0,pfy=0;
 wire ov;wire [23:0] rgb,ot;
 lens_autocrop_instance dut(
  .clk(clk),.rst_n(rst_n),.in_valid(iv),.nearest(nearest),.dst_x(dx),.dst_y(dy),
  .req_valid(rv),.req_inside(ri),.req_error(re),.req_tag(tag),
  .addr00(a00),.addr10(a10),.addr01(a01),.addr11(a11),.req_fx(fx),.req_fy(fy),
  .rsp_valid(pv),.rsp_inside(pi),.rsp_tag(pt),.p00(p00),.p10(p10),.p01(p01),.p11(p11),
  .rsp_fx(pfx),.rsp_fy(pfy),.out_valid(ov),.out_rgb(rgb),.out_tag(ot));
 integer xx[0:MAXN-1],yy[0:MAXN-1],nn[0:MAXN-1];
 integer e00[0:MAXN-1],e10[0:MAXN-1],e01[0:MAXN-1],e11[0:MAXN-1];
 integer exf[0:MAXN-1],eyf[0:MAXN-1],ergb[0:MAXN-1];
 integer fd,n=0,got,i,k,reqs=0,resps=0,outs=0,outside=0;
 integer tx,ty,tn,t00,t10,t01,t11,tfx,tfy,trgb;
 integer boundary_index,boundary_seen[0:2*BOUNDARY_N-1];
 integer interior_rows[0:1];
 integer nearest_rows=0,bilinear_rows=0;
 reg checking=0;reg test_passed=0;
 function automatic [23:0] source_pixel(input integer a);
  integer r,g,b;
  begin
   r=(a*17+3)&255;g=(a>>3)&255;b=((a*11)>>7)&255;
   source_pixel={r[7:0],g[7:0],b[7:0]};
  end
 endfunction
 always @(posedge clk)begin
  if(!rst_n)begin
   pv<=0;pi<=0;pt<=0;p00<=0;p10<=0;p01<=0;p11<=0;pfx<=0;pfy<=0;
   reqs=0;resps=0;outs=0;outside=0;
   #1;
   if(rv!==1'b0||ov!==1'b0||pv!==1'b0)$fatal(1,"autocrop valid not cleared during reset");
  end else begin
   // A request sampled here is returned for the core's next rising edge.
   // Return the actual request metadata, so the cache cannot hide a DUT error.
   pv<=rv;
   if(rv)begin
    pi<=ri;pt<=tag;pfx<=fx;pfy<=fy;
    p00<=ri?source_pixel(a00):0;p10<=ri?source_pixel(a10):0;
    p01<=ri?source_pixel(a01):0;p11<=ri?source_pixel(a11):0;
   end
   if(checking&&pv)resps=resps+1;
   if(checking&&rv)begin
    if(reqs>=n)$fatal(1,"extra autocrop request");
    if(ri!==1'b1)outside=outside+1;
    if(tag!==((yy[reqs]<<12)|xx[reqs])||ri!==1'b1||re!==1'b0||
       a00!==e00[reqs]||a10!==e10[reqs]||a01!==e01[reqs]||a11!==e11[reqs]||
       fx!==exf[reqs][7:0]||fy!==eyf[reqs][7:0])
     $fatal(1,"autocrop request %0d tag=%0d inside=%0d error=%0d addr=%0d,%0d,%0d,%0d weights=%0d,%0d",reqs,tag,ri,re,a00,a10,a01,a11,fx,fy);
    if(a00>=`SAFE_SRC_W*`SAFE_SRC_H||a10>=`SAFE_SRC_W*`SAFE_SRC_H||
       a01>=`SAFE_SRC_W*`SAFE_SRC_H||a11>=`SAFE_SRC_W*`SAFE_SRC_H)
     $fatal(1,"unsafe autocrop cache address");
    reqs=reqs+1;
   end
   #1;
   if(checking&&ov)begin
    if(outs>=n||ot!==((yy[outs]<<12)|xx[outs])||rgb!==ergb[outs][23:0])
     $fatal(1,"autocrop RGB %0d tag=%0d value=%h expected=%h",outs,ot,rgb,ergb[outs][23:0]);
    outs=outs+1;
   end
  end
 end
 initial begin
  for(i=0;i<2*BOUNDARY_N;i=i+1)boundary_seen[i]=0;
  interior_rows[0]=0;interior_rows[1]=0;
  fd=$fopen("vectors/lens_autocrop.txt","r");if(!fd)$fatal(1,"missing autocrop vectors");
  while(!$feof(fd))begin
   got=$fscanf(fd,"%d %d %d %d %d %d %d %d %d %d\n",tx,ty,tn,t00,t10,t01,t11,tfx,tfy,trgb);
   if(got==10)begin
    if(n>=MAXN)$fatal(1,"too many autocrop vectors");
    if(tx<0||tx>=`SAFE_DST_W||ty<0||ty>=`SAFE_DST_H||(tn!=0&&tn!=1)||
       tfx<0||tfx>255||tfy<0||tfy>255||trgb<0||trgb>16777215)
     $fatal(1,"invalid autocrop vector row %0d",n);
    xx[n]=tx;yy[n]=ty;nn[n]=tn;e00[n]=t00;e10[n]=t10;e01[n]=t01;e11[n]=t11;
    exf[n]=tfx;eyf[n]=tfy;ergb[n]=trgb;n=n+1;
    if(tn)nearest_rows=nearest_rows+1;else bilinear_rows=bilinear_rows+1;
    boundary_index=-1;
    if(ty==0)boundary_index=tx;
    else if(ty==`SAFE_DST_H-1)boundary_index=`SAFE_DST_W+tx;
    else if(tx==0)boundary_index=2*`SAFE_DST_W+ty-1;
    else if(tx==`SAFE_DST_W-1)boundary_index=2*`SAFE_DST_W+`SAFE_DST_H-2+ty-1;
    if(boundary_index>=0)boundary_seen[tn*BOUNDARY_N+boundary_index]=1;
    else interior_rows[tn]=interior_rows[tn]+1;
   end else if(got!=-1)$fatal(1,"bad autocrop vector row");
  end
  $fclose(fd);
  if(n<100||nearest_rows==0||bilinear_rows==0)$fatal(1,"insufficient autocrop vector coverage");
  for(i=0;i<2*BOUNDARY_N;i=i+1)
   if(!boundary_seen[i])$fatal(1,"missing autocrop boundary coordinate index=%0d mode=%0d",i%BOUNDARY_N,i/BOUNDARY_N);
  if(interior_rows[0]==0||interior_rows[1]==0)$fatal(1,"missing autocrop interior coverage");
  repeat(3)@(negedge clk);rst_n=1;
  // Fill coordinate, lens, cache and interpolation stages, then cancel them.
  for(i=0;i<45;i=i+1)begin
   @(negedge clk);iv=1;k=i%n;dx=xx[k];dy=yy[k];nearest=nn[k];
  end
  @(negedge clk);iv=0;rst_n=0;
  repeat(3)@(negedge clk);rst_n=1;
  repeat(64)begin @(negedge clk);if(rv||ov||pv)$fatal(1,"old autocrop transaction survived reset");end
  checking=1;
  // Long consecutive runs exercise one accepted destination per clock; the
  // deterministic gaps check valid propagation without changing vector order.
  for(i=0;i<n;i=i+1)begin
   @(negedge clk);iv=1;dx=xx[i];dy=yy[i];nearest=nn[i];
   if(i%11==3)begin @(negedge clk);iv=0;end
  end
  @(negedge clk);iv=0;
  i=0;while(outs<n&&i<256)begin @(negedge clk);i=i+1;end
  if(outs!=n||reqs!=n||resps!=n||outside!=0)
   $fatal(1,"autocrop counts requests=%0d responses=%0d outputs=%0d expected=%0d outside=%0d",reqs,resps,outs,n,outside);
  repeat(64)@(negedge clk);
  if(rv||ov||pv||reqs!=n||outs!=n||resps!=n)$fatal(1,"trailing autocrop transaction");
  test_passed=1;
  $display("AUTOCROP_PASS transactions=%0d outside=%0d mixed_modes=yes reset_flush=yes",n,outside);$finish;
 end
 initial begin #5000000;$fatal(1,"autocrop timeout");end
endmodule
