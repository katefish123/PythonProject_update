`timescale 1ns/1ps
// Full wrapper characterization with a queued, in-order cache contract.
// Both complete source banks are immutable after preload. Source video goes
// only to the detector; it never overwrites memory used by destination reads.
// This simulation queue makes no claim about synthesizable DDR throughput.
module tb_b_integration;
 localparam SRC_PIXELS=3072, FRAME_PIXELS=768, CAPACITY=8192, STAMPS=9;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,sv=0,sfs=0,sfe=0,dv=0,dfs=0,nn=0;
 reg [11:0] sx=0,sy=0,dx=0,dy=0; reg [23:0] srgb=0;
 wire cv,mreject,mdrop,sreject,geom,pending;
 wire [15:0] stale; wire [11:0] x0,y0,x1,y1,x2,y2,x3,y3;
 wire rv,ri,re; wire [23:0] rt,a00,a10,a01,a11; wire [7:0] fx,fy;
 reg pv=0,pi=0; reg [23:0] pt=0,p00=0,p10=0,p01=0,p11=0;
 reg [7:0] pfx=0,pfy=0;
 wire ov; wire [23:0] rgb,ot;
 reg test_passed=0;
 b_rectifier #(.SRC_W(64),.SRC_H(48),.OUT_W(32),.OUT_H(24),.UPDATE_EVERY(1)) dut(
  .clk(clk),.rst_n(rst_n),.src_valid(sv),.src_frame_start(sfs),.src_frame_end(sfe),
  .src_x(sx),.src_y(sy),.src_rgb(srgb),.dst_valid(dv),.dst_frame_start(dfs),
  .nearest(nn),.dst_x(dx),.dst_y(dy),.corners_valid(cv),.marker_reject(mreject),
  .marker_dropped(mdrop),.solver_reject(sreject),.x0(x0),.y0(y0),.x1(x1),.y1(y1),
  .x2(x2),.y2(y2),.x3(x3),.y3(y3),.geometry_valid(geom),.params_pending(pending),
  .stale_frames(stale),.req_valid(rv),.req_inside(ri),.req_error(re),.req_tag(rt),
  .addr00(a00),.addr10(a10),.addr01(a01),.addr11(a11),.req_fx(fx),.req_fy(fy),
  .rsp_valid(pv),.rsp_inside(pi),.rsp_tag(pt),.p00(p00),.p10(p10),.p01(p01),
  .p11(p11),.rsp_fx(pfx),.rsp_fy(pfy),.out_valid(ov),.out_rgb(rgb),.out_tag(ot));

 reg [23:0] source0[0:SRC_PIXELS-1],source1[0:SRC_PIXELS-1];
 // Independent generated vectors: phase 0 is H0/bilinear, phase 1 H1/nearest.
 reg [23:0] v_tag[0:2*FRAME_PIXELS-1],v_rgb[0:2*FRAME_PIXELS-1];
 reg v_inside[0:2*FRAME_PIXELS-1],v_error[0:2*FRAME_PIXELS-1];
 reg [23:0] v_a00[0:2*FRAME_PIXELS-1],v_a10[0:2*FRAME_PIXELS-1];
 reg [23:0] v_a01[0:2*FRAME_PIXELS-1],v_a11[0:2*FRAME_PIXELS-1];
 reg [7:0] v_fx[0:2*FRAME_PIXELS-1],v_fy[0:2*FRAME_PIXELS-1];
 reg signed [39:0] h0[0:8],h1[0:8],collision_old[0:8],collision_new[0:8];

 // One record per accepted destination input, not one record per raster tag.
 // Repeated tags in different frames remain distinct through FIFO position.
 integer e_phase[0:CAPACITY-1],e_bank[0:CAPACITY-1],e_stamp[0:CAPACITY-1];
 reg [23:0] e_tag[0:CAPACITY-1],e_rgb[0:CAPACITY-1];
 reg e_inside[0:CAPACITY-1],e_error[0:CAPACITY-1];
 reg [23:0] e_a00[0:CAPACITY-1],e_a10[0:CAPACITY-1];
 reg [23:0] e_a01[0:CAPACITY-1],e_a11[0:CAPACITY-1];
 reg [7:0] e_fx[0:CAPACITY-1],e_fy[0:CAPACITY-1];
 reg [23:0] e_p00[0:CAPACITY-1],e_p10[0:CAPACITY-1];
 reg [23:0] e_p01[0:CAPACITY-1],e_p11[0:CAPACITY-1];
 integer e_tail=0,e_req=0,e_rsp=0,e_out=0;

 // Cache entries preserve the actual request payload and its locked bank.
 integer q_id[0:CAPACITY-1],q_bank[0:CAPACITY-1],q_due[0:CAPACITY-1];
 integer q_arrival[0:CAPACITY-1],q_head=0,q_tail=0;
 reg q_inside[0:CAPACITY-1]; reg [23:0] q_tag[0:CAPACITY-1];
 reg [7:0] q_fx[0:CAPACITY-1],q_fy[0:CAPACITY-1];
 reg [23:0] q_p00[0:CAPACITY-1],q_p10[0:CAPACITY-1];
 reg [23:0] q_p01[0:CAPACITY-1],q_p11[0:CAPACITY-1];
 reg cache_pause=0,reset_exercise=0,reset_seen=0;
 integer response_id=0,response_arrival=0;
 integer drive_phase=-1,drive_bank=0,drive_row=0,drive_stamp=0;
 integer active_phase=-1,pending_phase=-1,solved_phase=-1;
 integer cycle=0,accepted=0,requests=0,responses=0,outputs=0;
 integer cancelled=0,cancel_coord=0,cancel_cache=0,cancel_interp=0,flushes=0;
 integer accepts_by_stamp[0:STAMPS-1],requests_by_stamp[0:STAMPS-1];
 integer responses_by_stamp[0:STAMPS-1],outputs_by_stamp[0:STAMPS-1];
 integer required_by_stamp[0:STAMPS-1];
 integer corners_seen=0,solves_seen=0,commits=0,collisions=0;
 integer source_dst_overlap=0,source_req_overlap=0,source_out_overlap=0;
 integer dst_streak=0,req_streak=0,max_dst_streak=0,max_req_streak=0;
 integer input_bubbles=0,response_bubbles=0,queue_peak=0,mixed_bank_queue=0;
 integer latency_min=1000000,latency_max=0,latency=0,pending_hold_inputs=0;
 integer boundary_with_inflight=0,ix,jx,vector_index,selected_phase,match0,match1;
 reg commit_this_edge=0,collision_this_edge=0;

 function [23:0] source_pixel(input integer bank,input integer address);
  begin
   if(address<0||address>=SRC_PIXELS)$fatal(1,"cache address out of range %0d",address);
   source_pixel=bank==0?source0[address]:source1[address];
  end
 endfunction
 function integer request_delay(input integer index);
  begin
   case(index%7)
    0:request_delay=2;1:request_delay=5;2:request_delay=29;
    3:request_delay=8;4:request_delay=43;5:request_delay=3;
    default:request_delay=17;
   endcase
  end
 endfunction
 function signed [39:0] golden_h(input integer phase,input integer coefficient);
  begin
   if(phase==0)golden_h=h0[coefficient];
   else if(phase==1)golden_h=h1[coefficient];
   else golden_h=coefficient==8?40'sd16777216:40'sd0;
  end
 endfunction
 task load_requests(input integer phase);
  integer f,row,n,t,i,e,b0,b1,b2,b3,u,v,extra;
  begin
   f=phase==0?$fopen("vectors/frame0_req.txt","r"):$fopen("vectors/frame1_req.txt","r");
   if(!f)$fatal(1,"integration request vectors missing phase=%0d",phase);
   for(row=0;row<FRAME_PIXELS;row=row+1)begin
    n=$fscanf(f,"%d %d %d %d %d %d %d %d %d\n",t,i,e,b0,b1,b2,b3,u,v);
    if(n!=9)$fatal(1,"integration vector truncated phase=%0d row=%0d",phase,row);
    n=phase*FRAME_PIXELS+row;
    v_tag[n]=t;v_inside[n]=i;v_error[n]=e;v_a00[n]=b0;v_a10[n]=b1;
    v_a01[n]=b2;v_a11[n]=b3;v_fx[n]=u;v_fy[n]=v;
    if(t!=((row/32)<<12)+(row%32))$fatal(1,"integration vector raster order");
   end
   if($fscanf(f,"%d",extra)!=-1)$fatal(1,"extra integration request vector phase=%0d",phase);
   $fclose(f);
  end
 endtask

 // Responses are driven on falling edges, accepted on rising edges. A ready
 // later entry cannot bypass an earlier entry; deliberate service gaps grow
 // the queue and carry old-bank requests across a destination frame boundary.
 always @(negedge clk or negedge rst_n)begin
  pv=0;pi=0;pt=0;pfx=0;pfy=0;p00=0;p10=0;p01=0;p11=0;
  if(!rst_n)q_head=q_tail;
  else if(!cache_pause&&q_head<q_tail&&cycle>=q_due[q_head]&&
          cycle%19!=7&&cycle%19!=8&&cycle%31!=11)begin
   pv=1;pi=q_inside[q_head];pt=q_tag[q_head];pfx=q_fx[q_head];pfy=q_fy[q_head];
   p00=q_p00[q_head];p10=q_p10[q_head];p01=q_p01[q_head];p11=q_p11[q_head];
   response_id=q_id[q_head];response_arrival=q_arrival[q_head];q_head=q_head+1;
  end
 end

 always @(posedge clk)begin
  cycle=cycle+1;commit_this_edge=0;collision_this_edge=0;
  if(!rst_n)begin
   if(!reset_seen)begin
    if(reset_exercise)begin
     cancel_coord=e_tail-e_req;cancel_cache=e_req-e_rsp;cancel_interp=e_rsp-e_out;
     cancelled=cancel_coord+cancel_cache+cancel_interp;flushes=flushes+1;
     if(cancel_coord<=0||cancel_cache<=0||cancel_interp<=0)
      $fatal(1,"reset missed in-flight stages coord=%0d cache=%0d interp=%0d",cancel_coord,cancel_cache,cancel_interp);
     $display("B_INTEGRATION_RESET coord=%0d cache=%0d interp=%0d",cancel_coord,cancel_cache,cancel_interp);
    end
    e_req=e_tail;e_rsp=e_tail;e_out=e_tail;reset_seen=1;
   end
   active_phase=-1;pending_phase=-1;solved_phase=-1;dst_streak=0;req_streak=0;
  end else begin
   reset_seen=0;
   selected_phase=(dfs&&pending)?pending_phase:active_phase;
   if(dv)begin
    if(e_tail>=CAPACITY||drive_row<0||drive_row>=FRAME_PIXELS)$fatal(1,"destination scoreboard overflow");
    if(drive_phase!=selected_phase||nn!==(drive_phase==1))
     $fatal(1,"unexpected H selection stamp=%0d expected=%0d selected=%0d",drive_stamp,drive_phase,selected_phase);
    if({dy,dx}!=={12'(drive_row/32),12'(drive_row%32)})$fatal(1,"stimulus raster mismatch");
    e_phase[e_tail]=drive_phase;e_bank[e_tail]=drive_bank;e_stamp[e_tail]=drive_stamp;
    e_tag[e_tail]={dy,dx};
    if(drive_phase<0)begin
     e_inside[e_tail]=0;e_error[e_tail]=0;e_a00[e_tail]=0;e_a10[e_tail]=0;
     e_a01[e_tail]=0;e_a11[e_tail]=0;e_fx[e_tail]=0;e_fy[e_tail]=0;e_rgb[e_tail]=0;
    end else begin
     if(drive_bank!=drive_phase)$fatal(1,"wrong locked source bank");
     vector_index=drive_phase*FRAME_PIXELS+drive_row;
     if(e_tag[e_tail]!==v_tag[vector_index])$fatal(1,"independent tag vector mismatch");
     e_inside[e_tail]=v_inside[vector_index];e_error[e_tail]=v_error[vector_index];
     e_a00[e_tail]=v_a00[vector_index];e_a10[e_tail]=v_a10[vector_index];
     e_a01[e_tail]=v_a01[vector_index];e_a11[e_tail]=v_a11[vector_index];
     e_fx[e_tail]=v_fx[vector_index];e_fy[e_tail]=v_fy[vector_index];e_rgb[e_tail]=v_rgb[vector_index];
    end
    if(e_inside[e_tail])begin
     e_p00[e_tail]=source_pixel(drive_bank,e_a00[e_tail]);e_p10[e_tail]=source_pixel(drive_bank,e_a10[e_tail]);
     e_p01[e_tail]=source_pixel(drive_bank,e_a01[e_tail]);e_p11[e_tail]=source_pixel(drive_bank,e_a11[e_tail]);
    end else begin e_p00[e_tail]=0;e_p10[e_tail]=0;e_p01[e_tail]=0;e_p11[e_tail]=0;end
    if(sv&&geom)source_dst_overlap=source_dst_overlap+1;
    if(pending&&!dfs)pending_hold_inputs=pending_hold_inputs+1;
    accepts_by_stamp[drive_stamp]=accepts_by_stamp[drive_stamp]+1;
    e_tail=e_tail+1;accepted=accepted+1;dst_streak=dst_streak+1;
    if(dst_streak>max_dst_streak)max_dst_streak=dst_streak;
   end else begin dst_streak=0;input_bubbles=input_bubbles+1;end
   if(pv)begin
    if(e_rsp>=e_req||response_id!=e_rsp)$fatal(1,"extra or reordered cache response id=%0d expected=%0d",response_id,e_rsp);
    if(pt!==e_tag[e_rsp]||pi!==e_inside[e_rsp]||pfx!==e_fx[e_rsp]||pfy!==e_fy[e_rsp]||
       p00!==e_p00[e_rsp]||p10!==e_p10[e_rsp]||p01!==e_p01[e_rsp]||p11!==e_p11[e_rsp])
     $fatal(1,"cache payload changed id=%0d phase=%0d bank=%0d stamp=%0d",e_rsp,e_phase[e_rsp],e_bank[e_rsp],e_stamp[e_rsp]);
    latency=cycle-response_arrival;
    if(latency<latency_min)latency_min=latency;if(latency>latency_max)latency_max=latency;
    responses_by_stamp[e_stamp[e_rsp]]=responses_by_stamp[e_stamp[e_rsp]]+1;
    e_rsp=e_rsp+1;responses=responses+1;
   end else if(q_head<q_tail)response_bubbles=response_bubbles+1;
   if(dfs&&pending)begin
    commit_this_edge=1;
    if(e_out<e_tail-1)boundary_with_inflight=boundary_with_inflight+1;
    active_phase=pending_phase;pending_phase=-1;commits=commits+1;
    if(dut.solve_done)begin collision_this_edge=1;collisions=collisions+1;end
   end
   // Reference the actual done pulse, never force solver or wrapper registers.
   if(dut.solve_done&&!dut.solve_error)pending_phase=solved_phase;
  end
  #1; // All wrapper outputs below are sampled after nonblocking assignments.
  if(!rst_n)begin
   if(rv!==0||ov!==0||geom!==0||pending!==0||stale!==0)$fatal(1,"wrapper reset did not clear outputs/geometry");
  end else begin
   if(geom!==(active_phase>=0)||pending!==(pending_phase>=0))$fatal(1,"geometry/pending reference mismatch");
   for(ix=0;ix<9;ix=ix+1)begin
    if(dut.active[ix]!==golden_h(active_phase,ix))$fatal(1,"active H changed outside boundary coefficient=%0d",ix);
    if(pending&&dut.pending[ix]!==golden_h(pending_phase,ix))$fatal(1,"pending H mismatch coefficient=%0d",ix);
   end
   if(commit_this_edge&&stale!==0)$fatal(1,"commit did not clear stale count");
   if(collision_this_edge)begin
    if(active_phase!=1||pending_phase!=0||!geom||!pending)$fatal(1,"collision lost old commit or new pending H");
    for(ix=0;ix<9;ix=ix+1)
     if(dut.active[ix]!==collision_old[ix]||dut.pending[ix]!==collision_new[ix])$fatal(1,"collision coefficient mismatch");
    $display("B_INTEGRATION_COLLISION old_pending=H1 active=H1 new_pending=H0");
   end
   if(cv)begin
    if(corners_seen==1)begin
     if({x0,y0,x1,y1,x2,y2,x3,y3}!=={12'd14,12'd7,12'd49,12'd10,12'd54,12'd37,12'd10,12'd41})$fatal(1,"source1 detector corners");
    end else if({x0,y0,x1,y1,x2,y2,x3,y3}!=={12'd10,12'd8,12'd52,12'd13,12'd56,12'd40,12'd7,12'd38})$fatal(1,"source0 detector corners");
    corners_seen=corners_seen+1;if(corners_seen>3)$fatal(1,"extra detector result");
   end
   if(mreject||mdrop||sreject)$fatal(1,"unexpected detector/solver rejection");
   if(dut.solve_done)begin
    match0=1;match1=1;
    for(ix=0;ix<9;ix=ix+1)begin
     if(dut.solved[ix]!==h0[ix])match0=0;if(dut.solved[ix]!==h1[ix])match1=0;
    end
    if(match0==match1)$fatal(1,"unknown solver result");
    solved_phase=match0?0:1;
    if(solved_phase!=(solves_seen==1?1:0))$fatal(1,"solver result sequence mismatch");
    solves_seen=solves_seen+1;if(solves_seen>3)$fatal(1,"extra solver result");
   end
   if(rv)begin
    if(e_req>=e_tail||q_tail>=CAPACITY)$fatal(1,"extra request or cache overflow");
    if(rt!==e_tag[e_req]||ri!==e_inside[e_req]||re!==e_error[e_req]||
       a00!==e_a00[e_req]||a10!==e_a10[e_req]||a01!==e_a01[e_req]||a11!==e_a11[e_req]||
       fx!==e_fx[e_req]||fy!==e_fy[e_req])
     $fatal(1,"request mismatch id=%0d phase=%0d bank=%0d stamp=%0d tag=%0d",e_req,e_phase[e_req],e_bank[e_req],e_stamp[e_req],rt);
    q_id[q_tail]=e_req;q_bank[q_tail]=e_bank[e_req];q_arrival[q_tail]=cycle;
    q_due[q_tail]=cycle+request_delay(requests);q_inside[q_tail]=ri;q_tag[q_tail]=rt;
    q_fx[q_tail]=fx;q_fy[q_tail]=fy;
    if(ri)begin
     q_p00[q_tail]=source_pixel(q_bank[q_tail],a00);q_p10[q_tail]=source_pixel(q_bank[q_tail],a10);
     q_p01[q_tail]=source_pixel(q_bank[q_tail],a01);q_p11[q_tail]=source_pixel(q_bank[q_tail],a11);
    end else begin q_p00[q_tail]=0;q_p10[q_tail]=0;q_p01[q_tail]=0;q_p11[q_tail]=0;end
    if(q_head<q_tail&&q_bank[q_head]!=q_bank[q_tail])mixed_bank_queue=mixed_bank_queue+1;
    q_tail=q_tail+1;if(q_tail-q_head>queue_peak)queue_peak=q_tail-q_head;
    requests_by_stamp[e_stamp[e_req]]=requests_by_stamp[e_stamp[e_req]]+1;
    e_req=e_req+1;requests=requests+1;req_streak=req_streak+1;
    if(req_streak>max_req_streak)max_req_streak=req_streak;
    if(sv&&geom)source_req_overlap=source_req_overlap+1;
   end else req_streak=0;
   if(ov)begin
    if(e_out>=e_rsp)$fatal(1,"extra or stale output tag=%0d",ot);
    if(ot!==e_tag[e_out]||rgb!==e_rgb[e_out])
     $fatal(1,"output mismatch id=%0d phase=%0d bank=%0d stamp=%0d got=%h expected=%h tag=%0d expected_tag=%0d",e_out,e_phase[e_out],e_bank[e_out],e_stamp[e_out],rgb,e_rgb[e_out],ot,e_tag[e_out]);
    outputs_by_stamp[e_stamp[e_out]]=outputs_by_stamp[e_stamp[e_out]]+1;
    e_out=e_out+1;outputs=outputs+1;if(sv&&geom)source_out_overlap=source_out_overlap+1;
   end
  end
 end

 task source_frame(input integer bank);
  integer row;
  begin
   for(row=0;row<SRC_PIXELS;row=row+1)begin
    @(negedge clk);sv=1;sfs=row==0;sfe=row==SRC_PIXELS-1;
    sx=row%64;sy=row/64;srgb=source_pixel(bank,row);
   end
   @(negedge clk);sv=0;sfs=0;sfe=0;
  end
 endtask
 task drive_pixel(input integer phase,input integer bank,input integer row,input integer boundary,input integer stamp);
  begin
   dv=1;dfs=boundary;nn=phase==1;dx=row%32;dy=row/32;
   drive_phase=phase;drive_bank=bank;drive_row=row;drive_stamp=stamp;
  end
 endtask
 task display_pixels(input integer phase,input integer bank,input integer first,input integer count,input integer boundary,input integer stamp);
  integer row,gap;
  begin
   for(row=0;row<count;row=row+1)begin
    @(negedge clk);drive_pixel(phase,bank,first+row,row==0&&boundary,stamp);
    // At least 70 consecutive valid inputs before each explicit bubble.
    if(row%71==70)begin
     @(negedge clk);dv=0;dfs=0;
     for(gap=0;gap<(row/71)%3;gap=gap+1)@(negedge clk);
    end
   end
   @(negedge clk);dv=0;dfs=0;
  end
 endtask
 task wait_pending;
  integer n;
  begin
   n=0;while(!pending&&n<1300)begin @(negedge clk);n=n+1;end
   if(!pending)$fatal(1,"integration solver did not become pending");
  end
 endtask
 task drain_all;
  integer n;
  begin
   n=0;
   while((e_req!=e_tail||e_rsp!=e_tail||e_out!=e_tail||q_head!=q_tail||pv)&&n<6000)begin @(negedge clk);n=n+1;end
   if(e_req!=e_tail||e_rsp!=e_tail||e_out!=e_tail||q_head!=q_tail||pv)
    $fatal(1,"integration missing events accepted=%0d requests=%0d responses=%0d outputs=%0d",accepted,requests,responses,outputs);
   repeat(40)@(negedge clk);
  end
 endtask
 task collide_and_display;
  integer n,different;
  begin
   n=0;while(!dut.solve_done&&n<1300)begin @(negedge clk);n=n+1;end
   if(!dut.solve_done||dut.solve_error||!pending||active_phase!=0||pending_phase!=1)$fatal(1,"collision was not armed by real source solutions");
   different=0;
   for(n=0;n<9;n=n+1)begin
    collision_old[n]=dut.pending[n];collision_new[n]=dut.solved[n];
    if(collision_old[n]!==collision_new[n])different=1;
   end
   if(!different)$fatal(1,"collision solutions must differ");
   drive_pixel(1,1,0,1,4);
   @(posedge clk);#2;
   if(collisions!=1||active_phase!=1||pending_phase!=0)$fatal(1,"real solve_done/frame-start collision missing");
   display_pixels(1,1,1,FRAME_PIXELS-1,0,4);
  end
 endtask
 task reset_with_work_inflight;
  integer row,n,old_responses;
  begin
   cache_pause=1;
   // A partial source frame, coordinate pipeline and queued reads all overlap.
   for(row=0;row<96;row=row+1)begin
    @(negedge clk);drive_pixel(0,0,row,0,7);
    sv=1;sfs=row==0;sfe=0;sx=row%64;sy=row/64;srgb=source_pixel(1,row);
   end
   old_responses=responses;n=0;
   while(responses<old_responses+2&&n<12)begin
    @(negedge clk);cache_pause=0;drive_pixel(0,0,96+n,0,7);
    sfs=0;sx=(96+n)%64;sy=(96+n)/64;srgb=source_pixel(1,96+n);n=n+1;
   end
   if(responses<old_responses+2)$fatal(1,"could not prime interpolation before reset");
   // Still on a falling edge: the last driven input is cancelled by reset.
   reset_exercise=1;rst_n=0;dv=0;dfs=0;sv=0;sfs=0;sfe=0;
   #1;
   if(geom!==0||pending!==0||rv!==0||ov!==0)$fatal(1,"asynchronous reset did not clear wrapper");
   repeat(4)@(negedge clk);
   if(q_head!=q_tail||pv!==0)$fatal(1,"external cache queue did not flush on reset");
   for(row=0;row<9;row=row+1)begin
    if(dut.active[row]!==golden_h(-1,row)||dut.pending[row]!==40'sd0)$fatal(1,"reset retained geometry coefficients");
   end
   if({x0,y0,x1,y1,x2,y2,x3,y3}!==96'd0)$fatal(1,"reset retained detector corners");
   rst_n=1;cache_pause=0;
   // Longer than coordinate latency and the largest configured memory delay.
   repeat(80)@(negedge clk);
   if(geom||pending||q_head!=q_tail)$fatal(1,"stale geometry/cache work survived reset");
  end
 endtask

 initial begin
  $readmemh("vectors/source0.hex",source0);$readmemh("vectors/source1.hex",source1);
  $readmemh("vectors/expected0.hex",v_rgb,0,FRAME_PIXELS-1);
  $readmemh("vectors/expected1.hex",v_rgb,FRAME_PIXELS,2*FRAME_PIXELS-1);
  load_requests(0);load_requests(1);
  // These manifest coefficients are used only to observe atomic H state.
  h0[0]=40'sd26175995;h0[1]=-40'sd2968810;h0[2]=40'sd167772160;
  h0[3]=40'sd3567396;h0[4]=40'sd17646447;h0[5]=40'sd134217728;
  h0[6]=40'sd66261;h0[7]=-40'sd111496;h0[8]=40'sd16777216;
  h1[0]=40'sd24913143;h1[1]=-40'sd4596464;h1[2]=40'sd234881024;
  h1[3]=40'sd2842198;h1[4]=40'sd17918483;h1[5]=40'sd117440512;
  h1[6]=40'sd121859;h1[7]=-40'sd167868;h1[8]=40'sd16777216;
  for(jx=0;jx<STAMPS;jx=jx+1)begin
   accepts_by_stamp[jx]=0;requests_by_stamp[jx]=0;responses_by_stamp[jx]=0;outputs_by_stamp[jx]=0;
   required_by_stamp[jx]=64;
  end
  required_by_stamp[1]=FRAME_PIXELS;required_by_stamp[3]=FRAME_PIXELS;
  required_by_stamp[4]=FRAME_PIXELS;required_by_stamp[6]=FRAME_PIXELS;required_by_stamp[7]=-1;
  repeat(3)@(negedge clk);rst_n=1;
  fork source_frame(0);display_pixels(-1,0,0,64,0,0);join
  wait_pending;if(geom||pending_phase!=0)$fatal(1,"H0 became active before boundary");
  // H0 reads bank0 while the detector sees bank1, with no memory overwrite.
  fork source_frame(1);display_pixels(0,0,0,FRAME_PIXELS,1,1);join
  wait_pending;if(active_phase!=0||pending_phase!=1)$fatal(1,"H1 changed H0 without a boundary");
  display_pixels(0,0,0,64,0,2);
  // Older H1 stays pending as source0 produces a new, real H0 solution.
  fork source_frame(0);display_pixels(0,0,0,FRAME_PIXELS,0,3);join
  collide_and_display;
  display_pixels(1,1,0,64,0,5);
  if(!pending||pending_phase!=0||active_phase!=1||e_out>=e_tail)$fatal(1,"new H0 was not held with H1 work in flight");
  display_pixels(0,0,0,FRAME_PIXELS,1,6);drain_all;
  if(commits!=3||collisions!=1||corners_seen!=3||solves_seen!=3)$fatal(1,"geometry scenario counts");
  reset_with_work_inflight;
  // A fresh frame boundary cannot resurrect geometry; every response is black.
  display_pixels(-1,0,0,64,1,8);drain_all;
  if(geom||pending||flushes!=1||corners_seen!=3||solves_seen!=3)$fatal(1,"post-reset bootstrap state");
  for(jx=0;jx<STAMPS;jx=jx+1)if(jx!=7)begin
   if(accepts_by_stamp[jx]!=required_by_stamp[jx]||requests_by_stamp[jx]!=required_by_stamp[jx]||
      responses_by_stamp[jx]!=required_by_stamp[jx]||outputs_by_stamp[jx]!=required_by_stamp[jx])
    $fatal(1,"missing/extra frame events stamp=%0d accepted=%0d req=%0d rsp=%0d out=%0d",jx,accepts_by_stamp[jx],requests_by_stamp[jx],responses_by_stamp[jx],outputs_by_stamp[jx]);
  end
  if(accepted-requests!=cancel_coord||requests-responses!=cancel_cache||responses-outputs!=cancel_interp||accepted-outputs!=cancelled)
   $fatal(1,"reset cancellation accounting mismatch");
  if(max_dst_streak<=22||max_req_streak<=22||queue_peak<=22||latency_min>=latency_max||
     input_bubbles==0||response_bubbles==0||mixed_bank_queue==0||boundary_with_inflight==0||
     source_dst_overlap==0||source_req_overlap==0||source_out_overlap==0||pending_hold_inputs==0)
   $fatal(1,"integration coverage missing burst=%0d reqburst=%0d queue=%0d latency=%0d..%0d mixed=%0d",max_dst_streak,max_req_streak,queue_peak,latency_min,latency_max,mixed_bank_queue);
  test_passed=1;
  $display("B_INTEGRATION_PASS accepted=%0d requests=%0d responses=%0d outputs=%0d cancelled=%0d commits=%0d collision=%0d corners=%0d solves=%0d",accepted,requests,responses,outputs,cancelled,commits,collisions,corners_seen,solves_seen);
  $display("B_INTEGRATION_COVERAGE input_burst=%0d request_burst=%0d queue_peak=%0d response_latency=%0d..%0d source_overlap=%0d/%0d/%0d mixed_banks=%0d",max_dst_streak,max_req_streak,queue_peak,latency_min,latency_max,source_dst_overlap,source_req_overlap,source_out_overlap,mixed_bank_queue);
  $finish;
 end
 initial begin #2500000;$fatal(1,"B_INTEGRATION timeout");end
endmodule
