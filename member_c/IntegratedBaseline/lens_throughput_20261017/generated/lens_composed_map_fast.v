`timescale 1ns/1ps
`default_nettype none
// Destination -> IDEAL-plane H -> Brown forward distortion -> raw source.
// H must be fitted using undistorted corners. No image sampling in this unit.
module lens_composed_map_fast(input wire clk,rst_n,frame_start,profile_valid,
 input wire[511:0]profile_params,input wire[575:0]profile_h,
 input wire[12:0]width,height,input wire[31:0]profile_version,profile_hframe,
 input wire req_valid,output wire req_ready,input wire[11:0]dst_u,dst_v,
 input wire[31:0]req_tag,req_hframe,
 output reg rsp_valid,input wire rsp_ready,output reg rsp_inside,rsp_invalid,
 output reg signed[63:0]source_x,source_y,output reg[31:0]rsp_tag,rsp_version,rsp_hframe);
 localparam IDLE=0,ISSUE=1,WAIT=2,HANDOFF=3,LENS_WAIT=4,RESPONSE=5;
 reg[2:0]state;reg[4:0]pc;
 reg signed[63:0]h[0:8],u,v,tmp0,tmp1,nu,nv,den,iu,iv;
 reg[511:0]captured_params;reg[12:0]captured_width,captured_height;
 reg alu_start;reg[1:0]alu_op;reg signed[63:0]alu_a,alu_b;
 wire alu_ready,alu_done,alu_error;wire signed[63:0]alu_value;
 q30_alu_fast arithmetic(.clk(clk),.rst_n(rst_n),.start(alu_start),.op(alu_op),.a(alu_a),.b(alu_b),.ready(alu_ready),.done(alu_done),.error(alu_error),.value(alu_value));
 wire lens_ready,lens_valid,lens_inside,lens_invalid;
 wire signed[63:0]lens_x,lens_y;wire[31:0]lens_tag,lens_version,lens_hframe;
 lens_map_fast lens(.clk(clk),.rst_n(rst_n),.frame_start(1'b0),.profile_valid(1'b1),.profile_params(captured_params),
 .width(captured_width),.height(captured_height),.profile_version(rsp_version),.profile_hframe(rsp_hframe),
 .req_valid(state==HANDOFF),.req_ready(lens_ready),.ideal_u(iu),.ideal_v(iv),.req_tag(rsp_tag),.req_hframe(rsp_hframe),
 .rsp_valid(lens_valid),.rsp_ready(state==LENS_WAIT),.rsp_inside(lens_inside),.rsp_invalid(lens_invalid),
 .source_x(lens_x),.source_y(lens_y),.rsp_tag(lens_tag),.rsp_version(lens_version),.rsp_hframe(lens_hframe));
 assign req_ready=state==IDLE&&profile_valid&&!frame_start;
 task reject;begin source_x<=0;source_y<=0;rsp_invalid<=1;rsp_inside<=0;rsp_valid<=1;state<=RESPONSE;end endtask
 always @*begin
 alu_op=0;alu_a=0;alu_b=0;
 case(pc)
 0:begin alu_op=1;alu_a=h[0];alu_b=u;end
 1:begin alu_op=1;alu_a=h[1];alu_b=v;end
 2:begin alu_a=tmp0;alu_b=tmp1;end
 3:begin alu_a=tmp0;alu_b=h[2];end
 4:begin alu_op=1;alu_a=h[3];alu_b=u;end
 5:begin alu_op=1;alu_a=h[4];alu_b=v;end
 6:begin alu_a=tmp0;alu_b=tmp1;end
 7:begin alu_a=tmp0;alu_b=h[5];end
 8:begin alu_op=1;alu_a=h[6];alu_b=u;end
 9:begin alu_op=1;alu_a=h[7];alu_b=v;end
 10:begin alu_a=tmp0;alu_b=tmp1;end
 11:begin alu_a=tmp0;alu_b=h[8];end
 13:begin alu_op=2;alu_a=nu;alu_b=den;end
 14:begin alu_op=2;alu_a=nv;alu_b=den;end
 default:begin end
 endcase end
 integer i;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 state<=IDLE;pc<=0;alu_start<=0;u<=0;v<=0;tmp0<=0;tmp1<=0;nu<=0;nv<=0;den<=0;iu<=0;iv<=0;
 captured_params<=0;captured_width<=0;captured_height<=0;
 rsp_valid<=0;rsp_inside<=0;rsp_invalid<=0;source_x<=0;source_y<=0;rsp_tag<=0;rsp_version<=0;rsp_hframe<=0;
 for(i=0;i<9;i=i+1)h[i]<=0;end
 else begin
 alu_start<=0;
 case(state)
 IDLE:if(req_valid&&req_ready)begin
 for(i=0;i<9;i=i+1)h[i]<=profile_h[i*64+:64];
 u<={22'd0,dst_u,30'd0};v<={22'd0,dst_v,30'd0};
 captured_params<=profile_params;captured_width<=width;captured_height<=height;
 rsp_tag<=req_tag;rsp_version<=profile_version;rsp_hframe<=profile_hframe;
 pc<=0;if(req_hframe!=profile_hframe)reject();else state<=ISSUE;end
 ISSUE:if(pc==12)begin if(den<64'sd67108864)reject();else pc<=13;end
 else if(pc==15)state<=HANDOFF;
 else if(alu_ready)begin alu_start<=1;state<=WAIT;end
 WAIT:if(alu_done)begin
 if(alu_error)reject();else begin
 case(pc)
 0,2,4,6,8,10:tmp0<=alu_value;
 1,5,9:tmp1<=alu_value;
 3:nu<=alu_value;7:nv<=alu_value;11:den<=alu_value;13:iu<=alu_value;14:iv<=alu_value;
 default:begin end
 endcase
 pc<=pc+1'b1;state<=ISSUE;end end
 HANDOFF:if(lens_ready)state<=LENS_WAIT;
 LENS_WAIT:if(lens_valid)begin
 source_x<=lens_x;source_y<=lens_y;rsp_inside<=lens_inside;rsp_invalid<=lens_invalid;
 rsp_tag<=lens_tag;rsp_version<=lens_version;rsp_hframe<=lens_hframe;rsp_valid<=1;state<=RESPONSE;end
 RESPONSE:if(rsp_ready&&rsp_valid)begin rsp_valid<=0;state<=IDLE;end
 default:begin state<=IDLE;rsp_valid<=0;end
 endcase end end
endmodule
`default_nettype wire
