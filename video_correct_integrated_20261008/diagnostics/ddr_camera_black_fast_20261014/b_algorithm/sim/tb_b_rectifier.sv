`timescale 1ns/1ps
module tb_b_rectifier;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,sv=0,sfs=0,sfe=0,dv=0,dfs=0,nn=0;
 reg [11:0] sx=0,sy=0,dx=0,dy=0;reg [23:0] srgb=0;
 wire cv,mreject,mdrop,sreject,geom,pending;
 wire [15:0] stale;wire [11:0] x0,y0,x1,y1,x2,y2,x3,y3;
 wire rv,ri,re;wire [23:0] rt,a00,a10,a01,a11;wire [7:0] fx,fy;
 reg pv=0,pi=0;reg [23:0] pt=0,p00=0,p10=0,p01=0,p11=0;reg [7:0] pfx=0,pfy=0;
 wire ov;wire [23:0] rgb,ot;
 reg [23:0] mem[0:3071],expected[0:767];
 integer phase=-1,seen=0,requests=0,colors_seen=0,rejects_seen=0,logf,qfile;
 integer et,ei,ee,ea00,ea10,ea01,ea11,efx,efy,scanned;
 reg test_passed=0;
 b_rectifier #(.SRC_W(64),.SRC_H(48),.OUT_W(32),.OUT_H(24),.UPDATE_EVERY(1)) dut(
 .clk(clk),.rst_n(rst_n),.src_valid(sv),.src_frame_start(sfs),.src_frame_end(sfe),.src_x(sx),.src_y(sy),.src_rgb(srgb),
 .dst_valid(dv),.dst_frame_start(dfs),.nearest(nn),.dst_x(dx),.dst_y(dy),
 .corners_valid(cv),.marker_reject(mreject),.marker_dropped(mdrop),.solver_reject(sreject),
 .x0(x0),.y0(y0),.x1(x1),.y1(y1),.x2(x2),.y2(y2),.x3(x3),.y3(y3),
 .geometry_valid(geom),.params_pending(pending),.stale_frames(stale),
 .req_valid(rv),.req_inside(ri),.req_error(re),.req_tag(rt),.addr00(a00),.addr10(a10),.addr01(a01),.addr11(a11),.req_fx(fx),.req_fy(fy),
 .rsp_valid(pv),.rsp_inside(pi),.rsp_tag(pt),.p00(p00),.p10(p10),.p01(p01),.p11(p11),.rsp_fx(pfx),.rsp_fy(pfy),
 .out_valid(ov),.out_rgb(rgb),.out_tag(ot));
 // Simulation-only four-read-port cache, one registered response stage.
 // This model is NOT a synthesizable replacement for A's DDR controller.
 always @(posedge clk)begin
  if(!rst_n)begin pv<=0;pi<=0;pt<=0;pfx<=0;pfy<=0;p00<=0;p10<=0;p01<=0;p11<=0;end
  else begin
   pv<=rv;pi<=ri;pt<=rt;pfx<=fx;pfy<=fy;
   if(rv&&ri)begin
    if(a00>=3072||a10>=3072||a01>=3072||a11>=3072)$fatal(1,"unsafe cache address");
    p00<=mem[a00];p10<=mem[a10];p01<=mem[a01];p11<=mem[a11];
   end else begin p00<=0;p10<=0;p01<=0;p11<=0;end
  end
  #1;
  if(rst_n&&cv)begin
   if(colors_seen==0&&{x0,y0,x1,y1,x2,y2,x3,y3}!=={12'd10,12'd8,12'd52,12'd13,12'd56,12'd40,12'd7,12'd38})$fatal(1,"first marker corners");
   if(colors_seen==1&&{x0,y0,x1,y1,x2,y2,x3,y3}!=={12'd14,12'd7,12'd49,12'd10,12'd54,12'd37,12'd10,12'd41})$fatal(1,"second marker corners");
   colors_seen=colors_seen+1;
  end
  if(rst_n&&mreject)rejects_seen=rejects_seen+1;
  if(rst_n&&(mdrop||sreject))$fatal(1,"unexpected marker drop/solver error");
  if(rst_n&&rv)begin
   scanned=$fscanf(qfile,"%d %d %d %d %d %d %d %d %d\n",et,ei,ee,ea00,ea10,ea01,ea11,efx,efy);
   if(scanned!=9)$fatal(1,"request vector missing phase=%0d",phase);
   if(rt!==et[23:0]||ri!==ei[0]||re!==ee[0]||a00!==ea00[23:0]||a10!==ea10[23:0]||a01!==ea01[23:0]||a11!==ea11[23:0]||fx!==efx[7:0]||fy!==efy[7:0])
    $fatal(1,"request mismatch phase=%0d index=%0d tag=%0d inside=%0d addrs=%0d,%0d,%0d,%0d",phase,requests,rt,ri,a00,a10,a01,a11);
   requests=requests+1;
  end
  if(rst_n&&ov)begin
   if(ot!=={12'(seen/32),12'(seen%32)})$fatal(1,"pixel tag mismatch phase=%0d index=%0d",phase,seen);
   if(rgb!==expected[seen])$fatal(1,"pixel mismatch phase=%0d index=%0d got=%h expected=%h",phase,seen,rgb,expected[seen]);
   $fdisplay(logf,"%0d,%0d,%0d,%06h",phase,seen,ot,rgb);seen=seen+1;
  end
 end
 task source_frame(input integer index);
  begin
   case(index)
    0:$readmemh("vectors/source0.hex",mem);
    1:$readmemh("vectors/source1.hex",mem);
    2:$readmemh("vectors/source2.hex",mem);
   endcase
   for(integer i=0;i<3072;i=i+1)begin
    @(negedge clk);sv=1;sfs=(i==0);sfe=(i==3071);sx=i%64;sy=i/64;srgb=mem[i];
   end
   @(negedge clk);sv=0;sfs=0;sfe=0;
  end
 endtask
 task wait_pending;
  integer n;
  begin n=0;while(!pending&&n<1300)begin @(negedge clk);n=n+1;end
   if(!pending)$fatal(1,"H did not become pending");
  end
 endtask
 task display_frame(input integer ph,input integer num,input integer commit,input integer method);
  begin
   phase=ph;seen=0;requests=0;
   case(ph)
    -1,4:begin for(integer k=0;k<768;k=k+1)expected[k]=0;qfile=$fopen("vectors/bootstrap_req.txt","r");end
    0:begin $readmemh("vectors/expected0.hex",expected);qfile=$fopen("vectors/frame0_req.txt","r");end
    1:begin $readmemh("vectors/precommit.hex",expected);qfile=$fopen("vectors/precommit_req.txt","r");end
    2:begin $readmemh("vectors/expected1.hex",expected);qfile=$fopen("vectors/frame1_req.txt","r");end
    3:begin $readmemh("vectors/hold.hex",expected);qfile=$fopen("vectors/hold_req.txt","r");end
   endcase
   if(!qfile)$fatal(1,"request file missing");
   for(integer i=0;i<num;i=i+1)begin
    @(negedge clk);dv=1;dfs=(i==0&&commit);nn=method;dx=i%32;dy=i/32;
    if(i%11==10)begin @(negedge clk);dv=0;dfs=0;end
   end
   @(negedge clk);dv=0;dfs=0;repeat(40)@(negedge clk);
   if(seen!=num||requests!=num)$fatal(1,"frame counts phase=%0d seen=%0d requests=%0d",phase,seen,requests);
   $fclose(qfile);
  end
 endtask
 initial begin
  logf=$fopen("results/rtl_video.csv","w");
  if($test$plusargs("wave"))begin $dumpfile("results/b_rectifier.vcd");$dumpvars(0,tb_b_rectifier);end
  repeat(3)@(negedge clk);rst_n=1;
  display_frame(-1,16,0,0);
  source_frame(0);wait_pending;
  if(geom)$fatal(1,"geometry enabled before frame commit");
  display_frame(0,768,1,0);if(!geom||pending)$fatal(1,"first commit failed");
  source_frame(1);wait_pending;
  display_frame(1,8,0,0);if(!pending)$fatal(1,"mid-frame H unexpectedly committed");
  display_frame(2,768,1,1);if(pending)$fatal(1,"second commit failed");
  source_frame(2);repeat(1000)@(negedge clk);
  if(colors_seen!=2||rejects_seen!=1||pending||!geom||stale==0)$fatal(1,"missing-marker hold policy");
  display_frame(3,768,1,1);
  @(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;
  if(geom||pending)$fatal(1,"geometry survived reset");
  display_frame(4,16,0,0);
  test_passed=1;$display("VIDEO_PASS pixels=2344 corners=2 rejected=1");$fclose(logf);$finish;
 end
 initial begin #500000;$fatal(1,"VIDEO timeout");end
endmodule
