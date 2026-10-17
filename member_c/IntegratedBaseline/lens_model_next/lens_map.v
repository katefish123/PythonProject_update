`timescale 1ns/1ps
`default_nettype none
// Sequential synthetic numeric baseline. Input is already in the undistorted
// camera plane. This module does not detect corners, fit H or access DDR.
module lens_map(input wire clk,rst_n,frame_start,profile_valid,
 input wire[511:0]profile_params,input wire[12:0]width,height,
 input wire[31:0]profile_version,profile_hframe,
 input wire req_valid,output wire req_ready,
 input wire signed[63:0]ideal_u,ideal_v,input wire[31:0]req_tag,req_hframe,
 output reg rsp_valid,input wire rsp_ready,output reg rsp_inside,rsp_invalid,
 output reg signed[63:0]source_x,source_y,output reg[31:0]rsp_tag,rsp_version,rsp_hframe);
 localparam IDLE=0,ISSUE=1,WAIT=2,RESPONSE=3;
 reg[1:0]state;reg[5:0]pc;reg signed[63:0]r[0:23];
 reg[12:0]captured_width,captured_height;
 reg alu_start;reg[1:0]alu_op;reg signed[63:0]alu_a,alu_b;reg[4:0]destination;
 wire alu_ready,alu_done,alu_error;wire signed[63:0]alu_value;
 q30_alu arithmetic(.clk(clk),.rst_n(rst_n),.start(alu_start),.op(alu_op),.a(alu_a),.b(alu_b),
 .ready(alu_ready),.done(alu_done),.error(alu_error),.value(alu_value));
 assign req_ready=state==IDLE&&profile_valid&&!frame_start;
 task respond(input signed[63:0]x,y,input bad);
 begin
 source_x<=bad?64'sd0:x;source_y<=bad?64'sd0:y;rsp_invalid<=bad;
 rsp_inside<=!bad&&x>=0&&y>=0
 &&x<=((($signed({51'd0,captured_width}))-64'sd1)<<<30)
 &&y<=((($signed({51'd0,captured_height}))-64'sd1)<<<30);
 rsp_valid<=1;state<=RESPONSE;
 end endtask
 always @*begin
 alu_op=0;alu_a=0;alu_b=0;destination=0;
 case(pc)
 0:begin alu_a=r[8];alu_b=-r[2];destination=20;end
 1:begin alu_op=2;alu_a=r[20];alu_b=r[0];destination=10;end
 2:begin alu_a=r[9];alu_b=-r[3];destination=20;end
 3:begin alu_op=2;alu_a=r[20];alu_b=r[1];destination=11;end
 5:begin alu_op=1;alu_a=r[10];alu_b=r[10];destination=12;end
 6:begin alu_op=1;alu_a=r[11];alu_b=r[11];destination=13;end
 7:begin alu_op=1;alu_a=r[10];alu_b=r[11];destination=14;end
 8:begin alu_a=r[12];alu_b=r[13];destination=15;end
 9:begin alu_op=1;alu_a=r[15];alu_b=r[15];destination=16;end
 10:begin alu_op=1;alu_a=r[4];alu_b=r[15];destination=20;end
 11:begin alu_op=1;alu_a=r[5];alu_b=r[16];destination=21;end
 12:begin alu_a=64'sd1073741824;alu_b=r[20];destination=17;end
 13:begin alu_a=r[17];alu_b=r[21];destination=17;end
 14:begin alu_op=1;alu_a=r[10];alu_b=r[17];destination=18;end
 15:begin alu_op=1;alu_a=r[6]<<<1;alu_b=r[14];destination=20;end
 16:begin alu_a=r[18];alu_b=r[20];destination=18;end
 17:begin alu_a=r[12];alu_b=r[12];destination=21;end
 18:begin alu_a=r[15];alu_b=r[21];destination=21;end
 19:begin alu_op=1;alu_a=r[7];alu_b=r[21];destination=20;end
 20:begin alu_a=r[18];alu_b=r[20];destination=18;end
 21:begin alu_op=1;alu_a=r[11];alu_b=r[17];destination=19;end
 22:begin alu_a=r[13];alu_b=r[13];destination=21;end
 23:begin alu_a=r[15];alu_b=r[21];destination=21;end
 24:begin alu_op=1;alu_a=r[6];alu_b=r[21];destination=20;end
 25:begin alu_a=r[19];alu_b=r[20];destination=19;end
 26:begin alu_op=1;alu_a=r[7]<<<1;alu_b=r[14];destination=20;end
 27:begin alu_a=r[19];alu_b=r[20];destination=19;end
 28:begin alu_op=1;alu_a=r[0];alu_b=r[18];destination=20;end
 29:begin alu_a=r[20];alu_b=r[2];destination=22;end
 30:begin alu_op=1;alu_a=r[1];alu_b=r[19];destination=20;end
 31:begin alu_a=r[20];alu_b=r[3];destination=23;end
 default:begin end
 endcase end
 integer i;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin state<=IDLE;pc<=0;alu_start<=0;captured_width<=0;captured_height<=0;
 rsp_valid<=0;rsp_inside<=0;rsp_invalid<=0;source_x<=0;source_y<=0;rsp_tag<=0;rsp_version<=0;rsp_hframe<=0;
 for(i=0;i<24;i=i+1)r[i]<=0;end
 else begin
 alu_start<=0;
 case(state)
 IDLE:if(req_valid&&req_ready)begin
 for(i=0;i<8;i=i+1)r[i]<=profile_params[i*64+:64];r[8]<=ideal_u;r[9]<=ideal_v;
 captured_width<=width;captured_height<=height;rsp_tag<=req_tag;rsp_version<=profile_version;rsp_hframe<=profile_hframe;
 pc<=0;if(req_hframe!=profile_hframe)respond(0,0,1);else state<=ISSUE;
 end
 ISSUE:if(pc==4)begin
 if(r[10]<-64'sd4294967296||r[10]>64'sd4294967296||r[11]<-64'sd4294967296||r[11]>64'sd4294967296)respond(0,0,1);
 else if(r[4]==0&&r[5]==0&&r[6]==0&&r[7]==0)respond(r[8],r[9],0);
 else pc<=5;
 end else if(pc==32)respond(r[22],r[23],0);
 else if(alu_ready)begin alu_start<=1;state<=WAIT;end
 WAIT:if(alu_done)begin
 if(alu_error)respond(0,0,1);else begin r[destination]<=alu_value;pc<=pc+1'b1;state<=ISSUE;end end
 RESPONSE:if(rsp_valid&&rsp_ready)begin rsp_valid<=0;state<=IDLE;end
 default:begin state<=IDLE;rsp_valid<=0;end
 endcase end end
endmodule
`default_nettype wire
