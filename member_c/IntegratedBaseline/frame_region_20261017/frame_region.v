`timescale 1ns/1ps
`default_nettype none
// Same-canvas routing only. WARP emits local destination coordinates, not a
// corrected RGB result. Boundary/mask detection and DDR sampling are external.
module frame_region(input wire clk,rst_n,cfg_valid,output wire cfg_ready,
 input wire frame_start,downstream_idle,input wire[95:0]cfg_quad,
 input wire[11:0]cfg_target_x,cfg_target_y,input wire[12:0]cfg_target_w,cfg_target_h,cfg_width,cfg_height,
 input wire[15:0]cfg_aspect_num,cfg_aspect_den,input wire[1:0]cfg_provenance,
 input wire[23:0]cfg_background,input wire cfg_markers_enabled,cfg_bank,
 input wire[31:0]cfg_frame_id,cfg_version,cfg_mode,
 input wire[12:0]expected_width,expected_height,input wire[31:0]expected_mode,
 output reg cfg_error,cfg_committed,cfg_deferred,pending_valid,output wire active_valid,
 output wire[31:0]active_frame_id,active_version,
 input wire in_valid,output wire in_ready,input wire[11:0]in_x,in_y,input wire[23:0]in_rgb,
 input wire[31:0]in_tag,in_frame_id,in_version,in_mask_frame_id,in_mask_version,
 input wire in_bank,in_mask_valid,in_marker_hit,
 output reg out_valid,input wire out_ready,output reg[1:0]out_route,output reg out_scene_valid,out_markers_enabled,out_bank,
 output reg[11:0]out_x,out_y,out_u,out_v,output reg[23:0]out_rgb,out_background,
 output reg[31:0]out_tag,out_frame_id,out_version);
 function[12:0]qx(input[95:0]q,input integer i);begin qx={1'b0,q[95-(i%4)*24-:12]};end endfunction
 function[12:0]qy(input[95:0]q,input integer i);begin qy={1'b0,q[83-(i%4)*24-:12]};end endfunction
 function signed[63:0]oriented_area(input integer ax,ay,bx,by,px,py);
 reg signed[63:0]dx,dy,xx,yy;begin dx=bx-ax;dy=by-ay;xx=px-ax;yy=py-ay;oriented_area=dx*yy-dy*xx;end endfunction
 function signed[31:0]constant_c(input[95:0]q,input integer i);
 reg signed[63:0]ax,ay,bx,by;begin ax=qx(q,i);ay=qy(q,i);bx=qx(q,i+1);by=qy(q,i+1);constant_c=(by-ay)*ax-(bx-ax)*ay;end endfunction
 reg[95:0]pq;reg[11:0]px,py;reg[12:0]pw,ph,psw,psh;reg[15:0]pnum,pden;reg[1:0]provenance;
 reg[23:0]pbg;reg pm,bank_p;reg[31:0]pf,pv,mode_p;
 reg[1:0]validation;reg[3:0]check_index;reg basic;
 wire[13:0]right_p={2'd0,px}+{1'b0,pw}-14'd1,bottom_p={2'd0,py}+{1'b0,ph}-14'd1;
 reg signed[63:0]ratio_delta,validation_cross;reg[63:0]ratio_abs;
 reg[12:0]test_x,test_y;integer n,edge_index;
 always @*begin
 ratio_delta=$signed({1'b0,pw})*$signed({1'b0,pden})-$signed({1'b0,ph})*$signed({1'b0,pnum});
 ratio_abs=ratio_delta<0?-ratio_delta:ratio_delta;
 basic=psw>=2&&psw<=4096&&psh>=2&&psh<=4096&&psw==expected_width&&psh==expected_height&&mode_p==expected_mode
 &&pw>=2&&ph>=2&&right_p<psw&&bottom_p<psh&&pnum!=0&&pden!=0&&pf!=0&&pv!=0&&provenance==1
 &&(ratio_abs<<1)<=({48'd0,pnum}+{48'd0,pden});
 for(n=0;n<4;n=n+1)basic=basic&&qx(pq,n)<psw&&qy(pq,n)<psh;
 edge_index=check_index[1:0];test_x=px;test_y=py;
 case(check_index[3:2])
 1:begin test_x=right_p[12:0];end
 2:begin test_x=right_p[12:0];test_y=bottom_p[12:0];end
 3:begin test_y=bottom_p[12:0];end
 default:begin end
 endcase
 validation_cross=validation==2?oriented_area(qx(pq,edge_index),qy(pq,edge_index),qx(pq,edge_index+1),qy(pq,edge_index+1),qx(pq,edge_index+2),qy(pq,edge_index+2)):
 oriented_area(qx(pq,edge_index),qy(pq,edge_index),qx(pq,edge_index+1),qy(pq,edge_index+1),test_x,test_y);
 end
 reg installed;reg[11:0]ax,ay;reg[12:0]aw,ah,asw,ash;reg[23:0]abg;
 reg am,abank;reg[31:0]af,av,amode;
 reg signed[12:0]ea[0:3],eb[0:3];reg signed[31:0]ec[0:3];
 assign active_valid=installed&&asw==expected_width&&ash==expected_height&&amode==expected_mode;
 assign active_frame_id=af;assign active_version=av;
 assign cfg_ready=!pending_valid&&validation==0;
 reg s1_valid,s1_match,s1_marker,s1_target,s1_markers,s1_bank;
 reg[11:0]s1_x,s1_y,s1_u,s1_v;reg[23:0]s1_rgb,s1_bg;reg[31:0]s1_tag,s1_frame,s1_version;
 reg signed[31:0]s1_edge[0:3];
 wire out_free=!out_valid||out_ready,s1_ready=!s1_valid||out_free;
 assign in_ready=s1_ready&&!frame_start;
 wire matched=active_valid&&in_frame_id==af&&in_version==av&&in_bank==abank&&in_x<asw&&in_y<ash
 &&(!am||(in_mask_valid&&in_mask_frame_id==in_frame_id&&in_mask_version==in_version));
 wire target_hit={1'b0,in_x}>={1'b0,ax}&&{1'b0,in_x}<({1'b0,ax}+aw)&&{1'b0,in_y}>={1'b0,ay}&&{1'b0,in_y}<({1'b0,ay}+ah);
 wire inside_s1=s1_edge[0]>=0&&s1_edge[1]>=0&&s1_edge[2]>=0&&s1_edge[3]>=0;
 wire[1:0]route_s1=!s1_match?2'd0:s1_marker?2'd1:inside_s1?(s1_target?2'd2:2'd1):2'd0;
 integer ci,si;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 cfg_error<=0;cfg_committed<=0;cfg_deferred<=0;pending_valid<=0;validation<=0;check_index<=0;
 pq<=0;px<=0;py<=0;pw<=0;ph<=0;psw<=0;psh<=0;pnum<=0;pden<=0;provenance<=0;pbg<=0;pm<=0;bank_p<=0;pf<=0;pv<=0;mode_p<=0;
 installed<=0;ax<=0;ay<=0;aw<=0;ah<=0;asw<=0;ash<=0;abg<=0;am<=0;abank<=0;af<=0;av<=0;amode<=0;
 for(ci=0;ci<4;ci=ci+1)begin ea[ci]<=0;eb[ci]<=0;ec[ci]<=0;end
 end else begin
 cfg_error<=0;cfg_committed<=0;cfg_deferred<=0;
 if(cfg_valid&&cfg_ready)begin
 pq<=cfg_quad;px<=cfg_target_x;py<=cfg_target_y;pw<=cfg_target_w;ph<=cfg_target_h;psw<=cfg_width;psh<=cfg_height;
 pnum<=cfg_aspect_num;pden<=cfg_aspect_den;provenance<=cfg_provenance;pbg<=cfg_background;pm<=cfg_markers_enabled;
 bank_p<=cfg_bank;pf<=cfg_frame_id;pv<=cfg_version;mode_p<=cfg_mode;validation<=1;check_index<=0;
 end else if(validation==1)begin
 if(!basic)begin cfg_error<=1;validation<=0;end else begin validation<=2;check_index<=0;end
 end else if(validation==2)begin
 if(validation_cross<=0)begin cfg_error<=1;validation<=0;end
 else if(check_index==3)begin validation<=3;check_index<=0;end else check_index<=check_index+1'b1;
 end else if(validation==3)begin
 if(validation_cross<0)begin cfg_error<=1;validation<=0;end
 else if(check_index==15)begin validation<=0;pending_valid<=1;end else check_index<=check_index+1'b1;
 end
 if(frame_start&&pending_valid)begin
 if(psw!=expected_width||psh!=expected_height||mode_p!=expected_mode)begin cfg_error<=1;pending_valid<=0;end
 else if(!s1_valid&&!out_valid&&downstream_idle)begin
 ax<=px;ay<=py;aw<=pw;ah<=ph;asw<=psw;ash<=psh;abg<=pbg;am<=pm;abank<=bank_p;af<=pf;av<=pv;amode<=mode_p;installed<=1;
 for(ci=0;ci<4;ci=ci+1)begin ea[ci]<=$signed({1'b0,qy(pq,ci)})-$signed({1'b0,qy(pq,ci+1)});
 eb[ci]<=$signed({1'b0,qx(pq,ci+1)})-$signed({1'b0,qx(pq,ci)});ec[ci]<=constant_c(pq,ci);end
 pending_valid<=0;cfg_committed<=1;
 end else cfg_deferred<=1;
 end end end
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 s1_valid<=0;s1_match<=0;s1_marker<=0;s1_target<=0;s1_markers<=0;s1_bank<=0;
 s1_x<=0;s1_y<=0;s1_u<=0;s1_v<=0;s1_rgb<=0;s1_bg<=0;s1_tag<=0;s1_frame<=0;s1_version<=0;
 for(si=0;si<4;si=si+1)s1_edge[si]<=0;
 out_valid<=0;out_route<=0;out_scene_valid<=0;out_markers_enabled<=0;out_bank<=0;out_x<=0;out_y<=0;out_u<=0;out_v<=0;out_rgb<=0;out_background<=0;out_tag<=0;out_frame_id<=0;out_version<=0;
 end else begin
 if(s1_ready)begin
 s1_valid<=in_valid&&in_ready;
 if(in_valid&&in_ready)begin
 s1_match<=matched;s1_marker<=am&&in_marker_hit;s1_target<=target_hit;s1_markers<=am;s1_bank<=in_bank;
 s1_x<=in_x;s1_y<=in_y;s1_u<=target_hit?in_x-ax:12'd0;s1_v<=target_hit?in_y-ay:12'd0;
 s1_rgb<=in_rgb;s1_bg<=abg;s1_tag<=in_tag;s1_frame<=in_frame_id;s1_version<=in_version;
 for(si=0;si<4;si=si+1)s1_edge[si]<=ea[si]*$signed({1'b0,in_x})+eb[si]*$signed({1'b0,in_y})+ec[si];
 end end
 if(out_free)begin
 out_valid<=s1_valid;
 if(s1_valid)begin out_route<=route_s1;out_scene_valid<=s1_match;out_markers_enabled<=s1_match&&s1_markers;out_bank<=s1_bank;
 out_x<=s1_x;out_y<=s1_y;out_u<=route_s1==2?s1_u:12'd0;out_v<=route_s1==2?s1_v:12'd0;
 out_rgb<=route_s1==1?s1_bg:s1_rgb;out_background<=s1_bg;out_tag<=s1_tag;out_frame_id<=s1_frame;out_version<=s1_version;
 end end end end
endmodule
`default_nettype wire
