// C interface adapter; B solver/core math remains unmodified.
// Member B wrapper: detector -> solver -> atomic H commit -> pixel core.
// Every input/output belongs to clk; A owns clock-domain conversion and memory.
module c_corner_rectifier #(
 parameter SRC_W=640,SRC_H=480,OUT_W=320,OUT_H=452,UPDATE_EVERY=5,
 parameter MIN_PIXELS=16,MAX_PIXELS=4096,MAX_SPAN=128,
 parameter BLACK_RMIN=0,BLACK_RMAX=64,BLACK_GMIN=0,BLACK_GMAX=64,BLACK_BMIN=0,BLACK_BMAX=64,
 // Inclusive, non-overlapping windows in source coordinates; P0/P1/P2/P3 = TL/TR/BR/BL.
 // Integer division places the center column/row of an odd source in right/bottom ROIs.
 parameter P0_XMIN=0,P0_XMAX=SRC_W/2-1,P0_YMIN=0,P0_YMAX=SRC_H/2-1,
 parameter P1_XMIN=SRC_W/2,P1_XMAX=SRC_W-1,P1_YMIN=0,P1_YMAX=SRC_H/2-1,
 parameter P2_XMIN=SRC_W/2,P2_XMAX=SRC_W-1,P2_YMIN=SRC_H/2,P2_YMAX=SRC_H-1,
 parameter P3_XMIN=0,P3_XMAX=SRC_W/2-1,P3_YMIN=SRC_H/2,P3_YMAX=SRC_H-1
)(
 input wire clk,rst_n,
 input wire src_valid,src_frame_start,src_frame_end,
 input wire [11:0] src_x,src_y, input wire [23:0] src_rgb,
 input wire dst_valid,dst_frame_start,nearest,
 input wire [11:0] dst_x,dst_y,
 input wire corners_valid,output wire marker_reject,marker_dropped,solver_reject,
 input wire [11:0] x0,y0,x1,y1,x2,y2,x3,y3,
 output reg geometry_valid,params_pending, output reg [15:0] stale_frames,
 output wire req_valid,req_inside,req_error,
 output wire [23:0] req_tag,addr00,addr10,addr01,addr11,
 output wire [7:0] req_fx,req_fy,
 input wire rsp_valid,rsp_inside,
 input wire [23:0] rsp_tag,p00,p10,p01,p11,
 input wire [7:0] rsp_fx,rsp_fy,
 output wire out_valid, output wire [23:0] out_rgb,out_tag
);
 assign marker_reject=1'b0;assign marker_dropped=1'b0;
 reg solve_start;
 wire solve_busy,solve_done,solve_error;
 wire signed [39:0] solved[0:8];
 homography_solver #(.SRC_W(SRC_W),.SRC_H(SRC_H),.OUT_W(OUT_W),.OUT_H(OUT_H))
  u_solver(clk,rst_n,solve_start,x0,y0,x1,y1,x2,y2,x3,y3,solve_busy,solve_done,solve_error,
  solved[0],solved[1],solved[2],solved[3],solved[4],solved[5],solved[6],solved[7],solved[8]);
 assign solver_reject=solve_done&&solve_error;
 reg signed [39:0] active[0:8],pending[0:8];
 wire signed [39:0] selected[0:8];
 wire commit=dst_frame_start&&params_pending;
 integer updates,i;
 genvar j;
 generate for(j=0;j<9;j=j+1) begin: coefficient_mux
  // First valid pixel can coincide with commit; it must see the new H.
  assign selected[j]=commit?pending[j]:active[j];
 end endgenerate
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   solve_start<=0;updates<=UPDATE_EVERY-1;geometry_valid<=0;params_pending<=0;stale_frames<=0;
   for(i=0;i<9;i=i+1) begin active[i]<=0;pending[i]<=0;end
   active[8]<=40'sd16777216;
  end else begin
   solve_start<=0;
   if(src_frame_end&&stale_frames!=16'hffff) stale_frames<=stale_frames+1'b1;
   if(corners_valid) begin
    if(updates>=UPDATE_EVERY-1) begin
     if(!solve_busy&&!solve_start) begin solve_start<=1;updates<=0;end
    end else updates<=updates+1;
   end
   if(commit) begin
    for(i=0;i<9;i=i+1) active[i]<=pending[i];
    geometry_valid<=1;params_pending<=0;stale_frames<=0;
   end
   if(solve_done&&!solve_error) begin
    for(i=0;i<9;i=i+1) pending[i]<=solved[i];
    params_pending<=1;
   end
  end
 end
 perspective_core #(.SRC_W(SRC_W),.SRC_H(SRC_H)) u_core(
  clk,rst_n,dst_valid,nearest,(geometry_valid||commit),dst_x,dst_y,
  selected[0],selected[1],selected[2],selected[3],selected[4],selected[5],selected[6],selected[7],selected[8],
  req_valid,req_inside,req_error,req_tag,addr00,addr10,addr01,addr11,req_fx,req_fy,
  rsp_valid,rsp_inside,rsp_tag,p00,p10,p01,p11,rsp_fx,rsp_fy,out_valid,out_rgb,out_tag);
endmodule
