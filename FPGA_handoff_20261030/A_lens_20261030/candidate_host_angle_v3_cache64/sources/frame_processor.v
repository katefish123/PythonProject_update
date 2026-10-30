`timescale 1ns/1ps
`default_nettype none
// Complete-frame processor. The owner holds the selected source frame immutable
// from start until done/error. Memory addresses are RGB888 PIXEL indices.
// One pixel memory transaction is active; eight coordinate credits hide B latency.
// mem_rsp_valid must correspond to the single accepted read, never an old reset.
module frame_processor #(
 parameter SRC_W=64,SRC_H=48,OUT_W=32,OUT_H=24,
 parameter FIXED_IDENTITY=0,MIN_PIXELS=16,MAX_PIXELS=4096,MAX_SPAN=128,
 parameter EXTERNAL_GEOMETRY=0,
 parameter BLACK_RMIN=0,BLACK_RMAX=64,BLACK_GMIN=0,BLACK_GMAX=64,BLACK_BMIN=0,BLACK_BMAX=64,P0_XMIN=0,P0_XMAX=SRC_W/2-1,P0_YMIN=0,P0_YMAX=SRC_H/2-1,P1_XMIN=SRC_W/2,P1_XMAX=SRC_W-1,P1_YMIN=0,P1_YMAX=SRC_H/2-1,P2_XMIN=SRC_W/2,P2_XMAX=SRC_W-1,P2_YMIN=SRC_H/2,P2_YMAX=SRC_H-1,P3_XMIN=0,P3_XMAX=SRC_W/2-1,P3_YMIN=SRC_H/2,P3_YMAX=SRC_H-1,
 parameter TIMEOUT_CYCLES=1000000
)(
 input wire clk,rst_n,start,nearest,
 input wire input_geometry_valid,input wire [95:0] input_corners,
 output wire busy, output reg done,error,
 output wire mem_valid, input wire mem_ready,
 output wire [23:0] mem_addr,
 input wire mem_rsp_valid, input wire [23:0] mem_rgb,
 output wire write_valid, input wire write_ready,
 output wire [23:0] write_addr,write_rgb,
 output reg [31:0] cycles,completed_pixels,
 output reg[3:0]failure_reason,output wire geometry_valid
);
 localparam IDLE=0,SCAN_SEND=1,SCAN_WAIT=2,SOLVE=3,COMMIT=4,
            ISSUE=5,WAIT_REQ=6,READ_SEND=7,READ_WAIT=8,RESPOND=9,
            WAIT_RGB=10,WRITE=11;
 reg [3:0] state;
 reg mode,fault;
 reg [11:0] scan_x,scan_y,dx,dy;
 reg [23:0] scan_addr,dst_addr;
 reg [31:0] watchdog;
 reg [1:0] sample;
 reg [23:0] a[0:3],p[0:3];
 reg inside_saved;
 reg [23:0] tag_saved,pixel_saved;
 reg [7:0] fx_saved,fy_saved;
 wire req_valid,req_inside,req_error,out_valid,pending,reject_marker,reject_solver;
 wire [23:0] req_tag,a00,a10,a01,a11,out_rgb,out_tag;
 wire [7:0] fx,fy;
 wire src_valid=(state==SCAN_WAIT)&&mem_rsp_valid;
 // Credits cover both the coordinate pipeline and returned queue entries.
 reg [136:0] descriptors[0:15];
 reg [3:0] queue_rd,queue_wr;
 reg [4:0] queue_count,reserved;
 reg [11:0] issue_x,issue_y;
 reg [31:0] issued;
 wire prefetch_active=(state>=ISSUE)&&(state<=WRITE);
 wire descriptor_pop=(state==ISSUE)&&(queue_count!=0);
 wire descriptor_push=req_valid&&prefetch_active;
 wire dst_valid=prefetch_active&&(issued<OUT_W*OUT_H)&&(reserved<16)&&!fault;
 wire chain_scan=(state==SCAN_WAIT)&&mem_rsp_valid&&(scan_addr<SRC_W*SRC_H-1);
 wire chain_read=(state==READ_WAIT)&&mem_rsp_valid&&!mode&&(sample<3);
 wire rsp_valid=(state==RESPOND);
 assign busy=(state!=IDLE);
 assign mem_valid=(state==SCAN_SEND)||(state==READ_SEND)||chain_scan||chain_read;
 assign mem_addr=(state==SCAN_SEND)?scan_addr:
                 (state==SCAN_WAIT)?scan_addr+24'd1:
                 (state==READ_WAIT)?a[sample+2'd1]:a[sample];
 assign write_valid=(state==WRITE);
 assign write_addr=dst_addr;
 assign write_rgb=pixel_saved;
 generate if(FIXED_IDENTITY) begin: fixed_geometry
  assign pending=1'b1; assign reject_marker=1'b0;assign reject_solver=1'b0;
  assign geometry_valid=1'b1;
  perspective_core #(.SRC_W(SRC_W),.SRC_H(SRC_H)) algorithm(
   .clk(clk),.rst_n(rst_n),.in_valid(dst_valid),.nearest(mode),.geometry_valid(1'b1),
   .dst_x(issue_x),.dst_y(issue_y),.h00(40'sd16777216),.h01(40'sd0),.h02(40'sd0),
   .h10(40'sd0),.h11(40'sd16777216),.h12(40'sd0),.h20(40'sd0),.h21(40'sd0),.h22(40'sd16777216),
   .req_valid(req_valid),.req_inside(req_inside),.req_error(req_error),.req_tag(req_tag),
   .addr00(a00),.addr10(a10),.addr01(a01),.addr11(a11),.req_fx(fx),.req_fy(fy),
   .rsp_valid(rsp_valid),.rsp_inside(inside_saved),.rsp_tag(tag_saved),
   .p00(p[0]),.p10(p[1]),.p01(p[2]),.p11(p[3]),.rsp_fx(fx_saved),.rsp_fy(fy_saved),
   .out_valid(out_valid),.out_rgb(out_rgb),.out_tag(out_tag));
 end else if(EXTERNAL_GEOMETRY)begin: external_geometry
  c_corner_rectifier #(.SRC_W(SRC_W),.SRC_H(SRC_H),.OUT_W(OUT_W),.OUT_H(OUT_H),
   .UPDATE_EVERY(1),.MIN_PIXELS(MIN_PIXELS),.MAX_PIXELS(MAX_PIXELS),.MAX_SPAN(MAX_SPAN)) algorithm(
   .clk(clk),.rst_n(rst_n),.src_valid(1'b0),
   .src_frame_start(1'b0),.src_frame_end(1'b0),
   .src_x(scan_x),.src_y(scan_y),.src_rgb(mem_rgb),
   .dst_valid(dst_valid),.dst_frame_start(state==COMMIT),.nearest(mode),.dst_x(issue_x),.dst_y(issue_y),
   .marker_reject(reject_marker),.solver_reject(reject_solver),.params_pending(pending),.geometry_valid(geometry_valid),
   .corners_valid(start&&input_geometry_valid),.marker_dropped(),.x0(input_corners[95-:12]),.y0(input_corners[83-:12]),.x1(input_corners[71-:12]),.y1(input_corners[59-:12]),.x2(input_corners[47-:12]),.y2(input_corners[35-:12]),.x3(input_corners[23-:12]),.y3(input_corners[11-:12]),.stale_frames(),
   .req_valid(req_valid),.req_inside(req_inside),.req_error(req_error),.req_tag(req_tag),
   .addr00(a00),.addr10(a10),.addr01(a01),.addr11(a11),.req_fx(fx),.req_fy(fy),
   .rsp_valid(rsp_valid),.rsp_inside(inside_saved),.rsp_tag(tag_saved),
   .p00(p[0]),.p10(p[1]),.p01(p[2]),.p11(p[3]),.rsp_fx(fx_saved),.rsp_fy(fy_saved),
   .out_valid(out_valid),.out_rgb(out_rgb),.out_tag(out_tag));
 end else begin: auto_geometry
  b_rectifier #(.SRC_W(SRC_W),.SRC_H(SRC_H),.OUT_W(OUT_W),.OUT_H(OUT_H),
   .UPDATE_EVERY(1),.MIN_PIXELS(MIN_PIXELS),.MAX_PIXELS(MAX_PIXELS),.MAX_SPAN(MAX_SPAN),.BLACK_RMIN(BLACK_RMIN),.BLACK_RMAX(BLACK_RMAX),.BLACK_GMIN(BLACK_GMIN),.BLACK_GMAX(BLACK_GMAX),.BLACK_BMIN(BLACK_BMIN),.BLACK_BMAX(BLACK_BMAX),.P0_XMIN(P0_XMIN),.P0_XMAX(P0_XMAX),.P0_YMIN(P0_YMIN),.P0_YMAX(P0_YMAX),.P1_XMIN(P1_XMIN),.P1_XMAX(P1_XMAX),.P1_YMIN(P1_YMIN),.P1_YMAX(P1_YMAX),.P2_XMIN(P2_XMIN),.P2_XMAX(P2_XMAX),.P2_YMIN(P2_YMIN),.P2_YMAX(P2_YMAX),.P3_XMIN(P3_XMIN),.P3_XMAX(P3_XMAX),.P3_YMIN(P3_YMIN),.P3_YMAX(P3_YMAX)) algorithm(
   .clk(clk),.rst_n(rst_n),.src_valid(src_valid),
   .src_frame_start(src_valid&&scan_addr==0),.src_frame_end(src_valid&&scan_addr==SRC_W*SRC_H-1),
   .src_x(scan_x),.src_y(scan_y),.src_rgb(mem_rgb),
   .dst_valid(dst_valid),.dst_frame_start(state==COMMIT),.nearest(mode),.dst_x(issue_x),.dst_y(issue_y),
   .marker_reject(reject_marker),.solver_reject(reject_solver),.params_pending(pending),.geometry_valid(geometry_valid),
   .corners_valid(),.marker_dropped(),.x0(),.y0(),.x1(),.y1(),.x2(),.y2(),.x3(),.y3(),.stale_frames(),
   .req_valid(req_valid),.req_inside(req_inside),.req_error(req_error),.req_tag(req_tag),
   .addr00(a00),.addr10(a10),.addr01(a01),.addr11(a11),.req_fx(fx),.req_fy(fy),
   .rsp_valid(rsp_valid),.rsp_inside(inside_saved),.rsp_tag(tag_saved),
   .p00(p[0]),.p10(p[1]),.p01(p[2]),.p11(p[3]),.rsp_fx(fx_saved),.rsp_fy(fy_saved),
   .out_valid(out_valid),.out_rgb(out_rgb),.out_tag(out_tag));
 end endgenerate
 // The owner resets this processor together with memory after an abort.
 // IDLE/COMMIT flush reservations; no descriptor storage reset is required.
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   queue_rd<=0;queue_wr<=0;queue_count<=0;reserved<=0;
   issue_x<=0;issue_y<=0;issued<=0;
  end else if(state==IDLE||state==COMMIT)begin
   queue_rd<=0;queue_wr<=0;queue_count<=0;reserved<=0;
   issue_x<=0;issue_y<=0;issued<=0;
  end else begin
   case({descriptor_push,descriptor_pop})
    2'b10:queue_count<=queue_count+1'b1;
    2'b01:queue_count<=queue_count-1'b1;
    default:begin end
   endcase
   case({dst_valid,descriptor_pop})
    2'b10:reserved<=reserved+1'b1;
    2'b01:reserved<=reserved-1'b1;
    default:begin end
   endcase
   if(descriptor_push)begin
    descriptors[queue_wr]<={req_inside,req_tag,a00,a10,a01,a11,fx,fy};
    queue_wr<=queue_wr+1'b1;
   end
   if(descriptor_pop)queue_rd<=queue_rd+1'b1;
   if(dst_valid)begin
    issued<=issued+1;
    if(issue_x==OUT_W-1)begin issue_x<=0;issue_y<=issue_y+1'b1;end
    else issue_x<=issue_x+1'b1;
   end
  end
 end
 integer i;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   failure_reason<=0;state<=IDLE;done<=0;error<=0;mode<=0;fault<=0;scan_x<=0;scan_y<=0;scan_addr<=0;
   dx<=0;dy<=0;dst_addr<=0;watchdog<=0;sample<=0;inside_saved<=0;
   tag_saved<=0;fx_saved<=0;fy_saved<=0;pixel_saved<=0;cycles<=0;completed_pixels<=0;
   for(i=0;i<4;i=i+1)begin a[i]<=0;p[i]<=0;end
  end else begin
   done<=0;error<=fault;
   if(busy)cycles<=cycles+1;
   // Timeout is per transaction/stage, reset whenever forward progress occurs.
   if(state==IDLE||state==COMMIT||dst_valid||descriptor_pop||state==RESPOND||
      (mem_valid&&mem_ready)||mem_rsp_valid||req_valid||out_valid||
      (write_valid&&write_ready)||(state==SOLVE&&pending)) watchdog<=0;
   else watchdog<=watchdog+1;
   case(state)
    IDLE: if(start&&!fault)begin
     failure_reason<=0;
     scan_x<=0;scan_y<=0;scan_addr<=0;dx<=0;dy<=0;dst_addr<=0;
     mode<=nearest;cycles<=0;completed_pixels<=0;
     if(FIXED_IDENTITY)state<=COMMIT;
     else if(EXTERNAL_GEOMETRY)begin
      if(input_geometry_valid)state<=SOLVE;
      else begin failure_reason<=3;state<=IDLE;error<=1;fault<=1;end
     end else state<=SCAN_SEND;
    end
    SCAN_SEND: if(mem_ready)state<=SCAN_WAIT;
    SCAN_WAIT: if(mem_rsp_valid)begin
     if(scan_addr==SRC_W*SRC_H-1)state<=SOLVE;
     else begin
      scan_addr<=scan_addr+1;
      if(scan_x==SRC_W-1)begin scan_x<=0;scan_y<=scan_y+1;end else scan_x<=scan_x+1;
      if(mem_ready)state<=SCAN_WAIT;else state<=SCAN_SEND;
     end
    end
    SOLVE: if(pending)state<=COMMIT;
    COMMIT: state<=ISSUE;
    ISSUE: if(descriptor_pop)begin
     {inside_saved,tag_saved,a[0],a[1],a[2],a[3],fx_saved,fy_saved}<=descriptors[queue_rd];
     sample<=0;
     for(i=0;i<4;i=i+1)p[i]<=0;
     if(descriptors[queue_rd][136])state<=READ_SEND;else state<=RESPOND;
    end
    READ_SEND: if(mem_ready)state<=READ_WAIT;
    READ_WAIT: if(mem_rsp_valid)begin
     p[sample]<=mem_rgb;
     if(mode)begin for(i=0;i<4;i=i+1)p[i]<=mem_rgb;state<=RESPOND;end
     else if(sample==3)state<=RESPOND;
     else begin sample<=sample+1;if(mem_ready)state<=READ_WAIT;else state<=READ_SEND;end
    end
    RESPOND: state<=WAIT_RGB;
    WAIT_RGB: if(out_valid)begin
     if(out_tag!={dy,dx})begin failure_reason<=11;error<=1;state<=IDLE;end
     else begin pixel_saved<=out_rgb;state<=WRITE;end
    end
    WRITE: if(write_ready)begin
     completed_pixels<=completed_pixels+1;
     if(dst_addr==OUT_W*OUT_H-1)begin done<=1;state<=IDLE;end
     else begin
      dst_addr<=dst_addr+1;
      if(dx==OUT_W-1)begin dx<=0;dy<=dy+1;end else dx<=dx+1;
      state<=ISSUE;
     end
    end
    default:begin state<=IDLE;error<=1;end
   endcase
   // Reject a captured frame; keep the prior displayed complete frame.
   if(busy&&(reject_marker||reject_solver||watchdog==TIMEOUT_CYCLES-1))begin
    failure_reason<=reject_marker?4'd3:reject_solver?4'd4:4'd5;
    state<=IDLE;error<=1;
    if(watchdog==TIMEOUT_CYCLES-1)fault<=1; // outstanding memory must be reset by owner
   end
  end
 end
endmodule
`default_nettype wire
