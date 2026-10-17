`timescale 1ns/1ps
`default_nettype none
// Isolated single-outstanding executor, not a real-time board integration.
// Reset must cancel/drain the external memory producer before new requests.
module region_sample(input wire clk,rst_n,in_valid,output wire in_ready,
 input wire[1:0]in_route,input wire in_scene_valid,in_markers_enabled,in_bank,
 input wire[11:0]in_x,in_y,in_u,in_v,input wire[23:0]in_rgb,in_background,
 input wire[31:0]in_tag,in_frame_id,in_version,
 input wire profile_valid,input wire[511:0]profile_params,input wire[575:0]profile_h,
 input wire[31:0]profile_version,profile_frame_id,input wire[12:0]width,height,
 output wire busy,q_valid,input wire q_ready,
 output wire[11:0]q_x0,q_y0,q_x1,q_y1,output wire[31:0]q_tag,q_frame_id,q_version,output wire q_bank,
 input wire r_valid,output wire r_ready,input wire[95:0]r_pixels,
 input wire[31:0]r_tag,r_frame_id,r_version,input wire r_bank,r_mask_valid,
 input wire[31:0]r_mask_frame_id,r_mask_version,input wire[3:0]r_marker_hit,
 output wire out_valid,input wire out_ready,output reg[23:0]out_rgb,
 output reg out_scene_valid,out_error,output wire out_bank,
 output wire[11:0]out_x,out_y,output wire[31:0]out_tag,out_frame_id,out_version);
 localparam IDLE=0,MAP_ISSUE=1,MAP_WAIT=2,MEM_ISSUE=3,MEM_WAIT=4,CLEAN_WAIT=5,INTERP_WAIT=6,OUTPUT=7;
 reg[2:0]state;
 reg[511:0]cp;reg[575:0]ch;reg[12:0]cw,cheight;
 reg[11:0]cx,cy,cu,cv,sx0,sy0,sx1,sy1;reg[7:0]fx,fy;
 reg[31:0]ct,cf,cversion;reg cb,cm;reg[23:0]background;
 assign in_ready=state==IDLE;assign busy=state!=IDLE;assign out_valid=state==OUTPUT;
 assign out_x=cx;assign out_y=cy;assign out_tag=ct;assign out_frame_id=cf;assign out_version=cversion;assign out_bank=cb;
 assign q_valid=state==MEM_ISSUE;assign q_x0=sx0;assign q_y0=sy0;assign q_x1=sx1;assign q_y1=sy1;
 assign q_tag=ct;assign q_frame_id=cf;assign q_version=cversion;assign q_bank=cb;
 assign r_ready=state==MEM_WAIT;
 wire response_match=r_tag==ct&&r_frame_id==cf&&r_version==cversion&&r_bank==cb;
 wire map_ready,map_valid,map_inside,map_invalid;wire signed[63:0]mx,my;wire[31:0]mt,mv,mf;
 lens_composed_map_fast mapper(.clk(clk),.rst_n(rst_n),.frame_start(1'b0),.profile_valid(1'b1),
 .profile_params(cp),.profile_h(ch),.width(cw),.height(cheight),.profile_version(cversion),.profile_hframe(cf),
 .req_valid(state==MAP_ISSUE),.req_ready(map_ready),.dst_u(cu),.dst_v(cv),.req_tag(ct),.req_hframe(cf),
 .rsp_valid(map_valid),.rsp_ready(state==MAP_WAIT),.rsp_inside(map_inside),.rsp_invalid(map_invalid),
 .source_x(mx),.source_y(my),.rsp_tag(mt),.rsp_version(mv),.rsp_hframe(mf));
 wire clean_ready,clean_valid,clean_error;wire[95:0]clean_pixels;wire[31:0]clean_tag,clean_frame,clean_version;
 source_marker_clean cleaner(.clk(clk),.rst_n(rst_n),.in_valid(r_valid&&r_ready&&response_match),.in_ready(clean_ready),
 .markers_enabled(cm),.mask_valid(r_mask_valid),.frame_id(cf),.version(cversion),
 .mask_frame_id(r_mask_frame_id),.mask_version(r_mask_version),.in_tag(ct),.marker_hit(r_marker_hit),
 .background(background),.pixels(r_pixels),.out_valid(clean_valid),.out_ready(state==CLEAN_WAIT),.out_error(clean_error),
 .out_pixels(clean_pixels),.out_tag(clean_tag),.out_frame_id(clean_frame),.out_version(clean_version));
 wire interp_valid;wire[23:0]interp_rgb;wire[31:0]interp_tag;
 bilinear_interp #(.TAG_W(32)) original_b(.clk(clk),.rst_n(rst_n),
 .in_valid(state==CLEAN_WAIT&&clean_valid&&!clean_error),.in_inside(1'b1),
 .p00(clean_pixels[23:0]),.p10(clean_pixels[47:24]),.p01(clean_pixels[71:48]),.p11(clean_pixels[95:72]),
 .fx(fx),.fy(fy),.in_tag(clean_tag),.out_valid(interp_valid),.rgb(interp_rgb),.out_tag(interp_tag));
 wire coordinate_inside=mx>=0&&my>=0&&mx<=(($signed({51'd0,cw})-64'sd1)<<<30)
 &&my<=(($signed({51'd0,cheight})-64'sd1)<<<30);
 task fail;begin out_rgb<=background;out_scene_valid<=0;out_error<=1;state<=OUTPUT;end endtask
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 state<=IDLE;cp<=0;ch<=0;cw<=0;cheight<=0;cx<=0;cy<=0;cu<=0;cv<=0;sx0<=0;sy0<=0;sx1<=0;sy1<=0;fx<=0;fy<=0;
 ct<=0;cf<=0;cversion<=0;cb<=0;cm<=0;background<=0;out_rgb<=0;out_scene_valid<=0;out_error<=0;
 end else case(state)
 IDLE:if(in_valid)begin
 cx<=in_x;cy<=in_y;cu<=in_u;cv<=in_v;ct<=in_tag;cf<=in_frame_id;cversion<=in_version;cb<=in_bank;cm<=in_markers_enabled;
 background<=in_background;cp<=profile_params;ch<=profile_h;cw<=width;cheight<=height;
 out_scene_valid<=in_scene_valid;out_error<=0;
 if(!in_scene_valid||in_route==0)begin out_rgb<=in_rgb;state<=OUTPUT;end
 else if(in_route==1)begin out_rgb<=in_background;state<=OUTPUT;end
 else if(in_route!=2||!profile_valid||profile_version!=in_version||profile_frame_id!=in_frame_id
 ||in_frame_id==0||in_version==0||width<2||width>4096||height<2||height>4096||in_x>=width||in_y>=height)begin
 out_rgb<=in_background;out_scene_valid<=0;out_error<=1;state<=OUTPUT;end
 else state<=MAP_ISSUE;
 end
 MAP_ISSUE:if(map_ready)state<=MAP_WAIT;
 MAP_WAIT:if(map_valid)begin
 if(map_invalid||mt!=ct||mv!=cversion||mf!=cf)fail();
 else if(!map_inside||!coordinate_inside)begin out_rgb<=background;state<=OUTPUT;end
 else begin
 sx0<=mx[41:30];sy0<=my[41:30];
 sx1<=({1'b0,mx[41:30]}+13'd1<cw)?mx[41:30]+12'd1:mx[41:30];
 sy1<=({1'b0,my[41:30]}+13'd1<cheight)?my[41:30]+12'd1:my[41:30];
 fx<=mx[29:22];fy<=my[29:22];state<=MEM_ISSUE;
 end end
 MEM_ISSUE:if(q_ready)state<=MEM_WAIT;
 MEM_WAIT:if(r_valid)begin if(!response_match||!clean_ready)fail();else state<=CLEAN_WAIT;end
 CLEAN_WAIT:if(clean_valid)begin
 if(clean_error||clean_tag!=ct||clean_frame!=cf||clean_version!=cversion)fail();else state<=INTERP_WAIT;
 end
 INTERP_WAIT:if(interp_valid)begin
 if(interp_tag!=ct)fail();else begin out_rgb<=interp_rgb;state<=OUTPUT;end
 end
 OUTPUT:if(out_ready)state<=IDLE;
 default:state<=IDLE;
 endcase end
endmodule
`default_nettype wire
