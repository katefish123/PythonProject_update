`timescale 1ns/1ps
`default_nettype none
// Complete-frame processor. The owner holds the selected source frame immutable
// from start until done/error. Memory addresses are RGB888 PIXEL indices.
// Coordinate lookahead reserves credits before B's 22-cycle pipe. Pixel
// Source reads remain single-outstanding. Interpolation and result writes run
// independently of the next pixel's sampling, bounded by the same credits.
// mem_rsp_valid must correspond to the single accepted read, never an old reset.
module frame_processor #(
 parameter SRC_W=64,SRC_H=48,OUT_W=32,OUT_H=24,
 parameter FIXED_IDENTITY=0,MIN_PIXELS=16,MAX_PIXELS=4096,MAX_SPAN=128,
 parameter TIMEOUT_CYCLES=1000000,COORD_QUEUE_BITS=4,ROI_SCAN_ONLY=1,
 parameter BLACK_RMIN=0,BLACK_RMAX=64,BLACK_GMIN=0,BLACK_GMAX=64,BLACK_BMIN=0,BLACK_BMAX=64,P0_XMIN=0,P0_XMAX=SRC_W/2-1,P0_YMIN=0,P0_YMAX=SRC_H/2-1,P1_XMIN=SRC_W/2,P1_XMAX=SRC_W-1,P1_YMIN=0,P1_YMAX=SRC_H/2-1,P2_XMIN=SRC_W/2,P2_XMAX=SRC_W-1,P2_YMIN=SRC_H/2,P2_YMAX=SRC_H-1,P3_XMIN=0,P3_XMAX=SRC_W/2-1,P3_YMIN=SRC_H/2,P3_YMAX=SRC_H-1
)(
 input wire clk,rst_n,start,nearest,
 output wire busy, output reg done,error,
 output wire mem_valid, input wire mem_ready,
 output wire [23:0] mem_addr,
 input wire mem_rsp_valid, input wire [23:0] mem_rgb,
 output wire write_valid, input wire write_ready,
 output wire [23:0] write_addr,write_rgb,
 output reg [31:0] cycles,completed_pixels,
 output wire geometry_valid
);
 localparam IDLE=0,SCAN_SEND=1,SCAN_WAIT=2,SOLVE=3,COMMIT=4,
            ISSUE=5,WAIT_REQ=6,READ_SEND=7,READ_WAIT=8,RESPOND=9,
            WAIT_RGB=10,WRITE=11;
 reg [3:0] state;
 reg mode,fault;
 reg [11:0] scan_x,scan_y,dx,dy;
 reg [23:0] scan_addr,dst_addr;
 reg [1:0] scan_corner;
 reg scan_first;
 wire [11:0] roi_xmin=scan_corner==0?P0_XMIN:scan_corner==1?P1_XMIN:scan_corner==2?P2_XMIN:P3_XMIN;
 wire [11:0] roi_xmax=scan_corner==0?P0_XMAX:scan_corner==1?P1_XMAX:scan_corner==2?P2_XMAX:P3_XMAX;
 wire [11:0] roi_ymax=scan_corner==0?P0_YMAX:scan_corner==1?P1_YMAX:scan_corner==2?P2_YMAX:P3_YMAX;
 wire [11:0] next_xmin=scan_corner==0?P1_XMIN:scan_corner==1?P2_XMIN:P3_XMIN;
 wire [11:0] next_ymin=scan_corner==0?P1_YMIN:scan_corner==1?P2_YMIN:P3_YMIN;
 // Each ROI is static. Select precomputed 24-bit strides instead of building
 // a widened run-time subtraction chain in the Pango carry mapper.
 wire [23:0] roi_row_step=scan_corner==0?SRC_W-(P0_XMAX-P0_XMIN):
                         scan_corner==1?SRC_W-(P1_XMAX-P1_XMIN):
                         scan_corner==2?SRC_W-(P2_XMAX-P2_XMIN):SRC_W-(P3_XMAX-P3_XMIN);
 wire [23:0] next_start_addr=scan_corner==0?P1_YMIN*SRC_W+P1_XMIN:
                           scan_corner==1?P2_YMIN*SRC_W+P2_XMIN:P3_YMIN*SRC_W+P3_XMIN;
 wire scan_last=ROI_SCAN_ONLY?(scan_corner==3&&scan_x==P3_XMAX&&scan_y==P3_YMAX):(scan_addr==SRC_W*SRC_H-1);
 reg [31:0] watchdog;
 reg [1:0] sample;
 reg [23:0] a[0:3],p[0:3];
 reg inside_saved;
 reg [23:0] tag_saved;
 reg [7:0] fx_saved,fy_saved;
 localparam COORD_DEPTH=1<<COORD_QUEUE_BITS;
 reg [COORD_QUEUE_BITS-1:0] coord_wptr,coord_rptr;
 reg [COORD_QUEUE_BITS:0] coord_count,coord_reserved;
 reg [95:0] coord_addresses[0:COORD_DEPTH-1];
 reg [23:0] coord_tags[0:COORD_DEPTH-1];
 reg [15:0] coord_fractions[0:COORD_DEPTH-1];
 reg coord_inside[0:COORD_DEPTH-1];
 reg [23:0] coordinates_issued;
 reg [11:0] issue_x,issue_y;
 reg [COORD_QUEUE_BITS-1:0] rgb_wptr,rgb_rptr;
 reg [COORD_QUEUE_BITS:0] rgb_count;
 reg [23:0] rgb_fifo[0:COORD_DEPTH-1];
 wire compute_phase=(state>=ISSUE && state<=WRITE);
 wire coord_pop=(state==WAIT_REQ && coord_count!=0);
 wire req_valid,req_inside,req_error,out_valid,pending,reject_marker,reject_solver;
 wire [23:0] req_tag,a00,a10,a01,a11,out_rgb,out_tag;
 wire [7:0] fx,fy;
 wire src_valid=(state==SCAN_WAIT)&&mem_rsp_valid;
 wire dst_valid=compute_phase && coordinates_issued<OUT_W*OUT_H && coord_reserved<COORD_DEPTH;
 wire coord_push=compute_phase && req_valid && (coord_count<COORD_DEPTH || coord_pop);
 wire coord_overflow=compute_phase && req_valid && coord_count==COORD_DEPTH && !coord_pop;
 wire rsp_valid=(state==RESPOND);
 wire rgb_pop=write_valid&&write_ready;
 wire rgb_push=compute_phase&&out_valid;
 wire rgb_overflow=rgb_push&&rgb_count==COORD_DEPTH&&!rgb_pop;
 wire rgb_tag_error=rgb_push&&out_tag!={dy,dx};
 assign busy=(state!=IDLE);
 assign mem_valid=(state==SCAN_SEND)||(state==READ_SEND);
 assign mem_addr=(state==SCAN_SEND)?scan_addr:a[sample];
 assign write_valid=compute_phase&&rgb_count!=0;
 assign write_addr=dst_addr;
 assign write_rgb=rgb_fifo[rgb_rptr];
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
 end else begin: auto_geometry
  b_rectifier #(.SRC_W(SRC_W),.SRC_H(SRC_H),.OUT_W(OUT_W),.OUT_H(OUT_H),
   .UPDATE_EVERY(1),.MIN_PIXELS(MIN_PIXELS),.MAX_PIXELS(MAX_PIXELS),.MAX_SPAN(MAX_SPAN),
  .BLACK_RMIN(BLACK_RMIN),.BLACK_RMAX(BLACK_RMAX),.BLACK_GMIN(BLACK_GMIN),.BLACK_GMAX(BLACK_GMAX),.BLACK_BMIN(BLACK_BMIN),.BLACK_BMAX(BLACK_BMAX),.P0_XMIN(P0_XMIN),.P0_XMAX(P0_XMAX),.P0_YMIN(P0_YMIN),.P0_YMAX(P0_YMAX),.P1_XMIN(P1_XMIN),.P1_XMAX(P1_XMAX),.P1_YMIN(P1_YMIN),.P1_YMAX(P1_YMAX),.P2_XMIN(P2_XMIN),.P2_XMAX(P2_XMAX),.P2_YMIN(P2_YMIN),.P2_YMAX(P2_YMAX),.P3_XMIN(P3_XMIN),.P3_XMAX(P3_XMAX),.P3_YMIN(P3_YMIN),.P3_YMAX(P3_YMAX)) algorithm(
   .clk(clk),.rst_n(rst_n),.src_valid(src_valid),
   .src_frame_start(src_valid&&scan_first),.src_frame_end(src_valid&&scan_last),
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
 integer i;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;done<=0;error<=0;mode<=0;fault<=0;scan_x<=0;scan_y<=0;scan_addr<=0;
   dx<=0;dy<=0;dst_addr<=0;watchdog<=0;sample<=0;inside_saved<=0;
   tag_saved<=0;fx_saved<=0;fy_saved<=0;cycles<=0;completed_pixels<=0;
   scan_corner<=0;scan_first<=1;
   rgb_wptr<=0;rgb_rptr<=0;rgb_count<=0;
   coord_wptr<=0;coord_rptr<=0;coord_count<=0;coord_reserved<=0;
   coordinates_issued<=0;issue_x<=0;issue_y<=0;
   for(i=0;i<4;i=i+1)begin a[i]<=0;p[i]<=0;end
  end else begin
   done<=0;error<=fault;
   // Credits cover coordinates inside the pipeline, queued requests and the
   // actively sampled pixel. Returning a credit requires a real writer accept.
   if(compute_phase)begin
    if(dst_valid)begin
     coordinates_issued<=coordinates_issued+1'b1;
     if(issue_x==OUT_W-1)begin issue_x<=0;issue_y<=issue_y+1'b1;end
     else issue_x<=issue_x+1'b1;
    end
    case({dst_valid,write_valid&&write_ready})
     2'b10:coord_reserved<=coord_reserved+1'b1;
     2'b01:coord_reserved<=coord_reserved-1'b1;
     default:begin end
    endcase
    if(coord_push)begin
     coord_addresses[coord_wptr]<={a11,a01,a10,a00};
     coord_tags[coord_wptr]<=req_tag;
     coord_fractions[coord_wptr]<={fy,fx};
     coord_inside[coord_wptr]<=req_inside;
     coord_wptr<=coord_wptr+1'b1;
    end
    if(coord_pop)coord_rptr<=coord_rptr+1'b1;
    case({coord_push,coord_pop})
     2'b10:coord_count<=coord_count+1'b1;
     2'b01:coord_count<=coord_count-1'b1;
     default:begin end
    endcase
    if(rgb_push&&!rgb_overflow)begin
     rgb_fifo[rgb_wptr]<=out_rgb;rgb_wptr<=rgb_wptr+1'b1;
     if(dx==OUT_W-1)begin dx<=0;dy<=dy+1'b1;end else dx<=dx+1'b1;
    end
    if(rgb_pop)begin
     rgb_rptr<=rgb_rptr+1'b1;completed_pixels<=completed_pixels+1'b1;
     if(dst_addr==OUT_W*OUT_H-1)begin done<=1;state<=IDLE;end
     else dst_addr<=dst_addr+1'b1;
    end
    case({rgb_push,rgb_pop})
     2'b10:rgb_count<=rgb_count+1'b1;
     2'b01:rgb_count<=rgb_count-1'b1;
     default:begin end
    endcase
   end

   if(busy)cycles<=cycles+1;
   // Timeout is per transaction/stage, reset whenever forward progress occurs.
   if(state==IDLE||state==COMMIT||state==ISSUE||state==RESPOND||
      (mem_valid&&mem_ready)||mem_rsp_valid||coord_pop||out_valid||
      (write_valid&&write_ready)||(state==SOLVE&&pending)) watchdog<=0;
   else watchdog<=watchdog+1;
   case(state)
    IDLE: if(start&&!fault)begin
     scan_x<=0;scan_y<=0;scan_addr<=0;dx<=0;dy<=0;dst_addr<=0;
     scan_corner<=0;scan_first<=1;
     rgb_wptr<=0;rgb_rptr<=0;rgb_count<=0;
     mode<=nearest;cycles<=0;completed_pixels<=0;
     coord_wptr<=0;coord_rptr<=0;coord_count<=0;coord_reserved<=0;
     coordinates_issued<=0;issue_x<=0;issue_y<=0;
     if(FIXED_IDENTITY)state<=COMMIT;
     else begin
      if(ROI_SCAN_ONLY)begin scan_x<=P0_XMIN;scan_y<=P0_YMIN;scan_addr<=P0_YMIN*SRC_W+P0_XMIN;end
      state<=SCAN_SEND;
     end
    end
    SCAN_SEND: if(mem_ready)state<=SCAN_WAIT;
    SCAN_WAIT: if(mem_rsp_valid)begin
     scan_first<=0;
     if(scan_last)state<=SOLVE;
     else begin
      if(ROI_SCAN_ONLY)begin
       if(scan_x==roi_xmax&&scan_y==roi_ymax)begin
        scan_corner<=scan_corner+1'b1;scan_x<=next_xmin;scan_y<=next_ymin;
        scan_addr<=next_start_addr;
       end else if(scan_x==roi_xmax)begin
        scan_x<=roi_xmin;scan_y<=scan_y+1'b1;
        scan_addr<=scan_addr+roi_row_step;
       end else begin scan_x<=scan_x+1'b1;scan_addr<=scan_addr+1'b1;end
      end else begin
       scan_addr<=scan_addr+1'b1;
       if(scan_x==SRC_W-1)begin scan_x<=0;scan_y<=scan_y+1'b1;end else scan_x<=scan_x+1'b1;
      end
      state<=SCAN_SEND;
     end
    end
    SOLVE: if(pending)state<=COMMIT;
    COMMIT: state<=ISSUE;
    ISSUE: state<=WAIT_REQ;
    WAIT_REQ: if(coord_pop)begin
     a[0]<=coord_addresses[coord_rptr][23:0];
     a[1]<=coord_addresses[coord_rptr][47:24];
     a[2]<=coord_addresses[coord_rptr][71:48];
     a[3]<=coord_addresses[coord_rptr][95:72];sample<=0;
     inside_saved<=coord_inside[coord_rptr];tag_saved<=coord_tags[coord_rptr];
     fx_saved<=coord_fractions[coord_rptr][7:0];fy_saved<=coord_fractions[coord_rptr][15:8];
     for(i=0;i<4;i=i+1)p[i]<=0;
     if(coord_inside[coord_rptr])state<=READ_SEND;else state<=RESPOND;
    end
    READ_SEND: if(mem_ready)state<=READ_WAIT;
    READ_WAIT: if(mem_rsp_valid)begin
     p[sample]<=mem_rgb;
     if(mode)begin for(i=0;i<4;i=i+1)p[i]<=mem_rgb;state<=RESPOND;end
     else if(sample==3)state<=RESPOND;
     else begin sample<=sample+1;state<=READ_SEND;end
    end
    // The interpolation pipeline captures p[] at this edge. The next request
    // can be popped while this result advances toward the independently drained FIFO.
    RESPOND: state<=WAIT_REQ;
    default:begin state<=IDLE;error<=1;end
   endcase
   // Reject a captured frame; keep the prior displayed complete frame.
   if(busy&&(reject_marker||reject_solver||coord_overflow||rgb_overflow||rgb_tag_error||watchdog==TIMEOUT_CYCLES-1))begin
    state<=IDLE;error<=1;
    coord_count<=0;coord_reserved<=0;coord_wptr<=0;coord_rptr<=0;
    rgb_count<=0;rgb_wptr<=0;rgb_rptr<=0;
    if(coord_overflow||rgb_overflow||rgb_tag_error||watchdog==TIMEOUT_CYCLES-1)fault<=1; // outstanding memory must be reset by owner
   end
  end
 end
endmodule
`default_nettype wire
