`timescale 1ns/1ps
`default_nettype none
// All addresses count RGB888 pixels. Responses must preserve accepted request order.
// Generation is reset only by the public hard reset, never by abort or a frame fault.
module frame_processor_stream #(
 parameter SRC_W=1920,SRC_H=1080,OUT_W=768,OUT_H=1080,
 parameter ACTIVE_W=765,ACTIVE_X=1,FIXED_IDENTITY=0,TILED_ORDER=0,RUNTIME_AFFINE=0,
 parameter TIMEOUT_CYCLES=300000000
)(
 output reg[359:0]debug_h,input wire clk,rst_n,start,abort,nearest,input_geometry_valid,
 input wire[95:0]input_corners,
 output wire busy,output reg done,error,output reg[3:0]failure_reason,
 output reg[31:0]cycles,completed_pixels,output wire geometry_valid,
 output wire q_valid,input wire q_ready,output wire q_inside,q_nearest,
 output wire[23:0]q_addr00,q_addr10,q_addr01,q_addr11,q_tag,
 output wire[7:0]q_fx,q_fy,output wire[31:0]q_generation,
 input wire r_valid,output wire r_ready,input wire r_inside,
 input wire[23:0]r_p00,r_p10,r_p01,r_p11,r_tag,
 input wire[7:0]r_fx,r_fy,input wire[31:0]r_generation,
 output wire write_valid,input wire write_ready,
 output wire[23:0]write_addr,write_rgb,
 input wire cfg_valid,output wire cfg_ready,input wire[239:0]cfg_affine,
 input wire[15:0]cfg_sequence,output reg commit_valid,output reg[15:0]commit_sequence
);
 wire[359:0]math_debug_h;
 localparam IDLE=0,PREP=1,SOLVE=2,COMMIT=3,RUN=4;
 reg[2:0]state;reg mode;reg[95:0]corners;reg[31:0]generation;
 reg[11:0]ix,iy,cx,cy,rx,ry,ox,oy,wx,wy;
 reg[23:0]o_addr,w_addr;
 localparam[239:0]DEFAULT_AFFINE={40'sh0006000000,40'sh0000fe56d6,40'sh0000000000,
                               40'sh0008b988e6,40'sh0000000000,40'sh0000fe56d6};
 reg[239:0]active_affine;
 // Every pipeline boundary advances its own cursor only on its own transfer.
 // Tile order retains64 contiguous pixels per result burst, visiting8 rows
 // before advancing to the next64-column tile. Raster order is unchanged.
 function[23:0]next_xy;
 input[11:0]x,y;reg[11:0]nx,ny;
 begin
  nx=x+1'b1;ny=y;
  if(TILED_ORDER&&x[5:0]==63)begin
   if(y[2:0]!=7)begin nx=x-12'd63;ny=y+1'b1;end
   else if(x==OUT_W-1)begin nx=0;ny=y+1'b1;end
   else begin nx=x+1'b1;ny=y-12'd7;end
  end else if(!TILED_ORDER&&x==OUT_W-1)begin nx=0;ny=y+1'b1;end
  next_xy={ny,nx};
 end endfunction
 function[23:0]next_address;
 input[23:0]address;input[11:0]x,y;
 begin
  if(!TILED_ORDER||x[5:0]!=63)next_address=address+24'd1;
  else if(y[2:0]!=7)next_address=address+(OUT_W-63);
  else if(x==OUT_W-1)next_address=address+24'd1;
  else next_address=address+24'd1-7*OUT_W;
 end endfunction
 reg[31:0]issued,accepted,responded,produced;
 reg[8:0]coord_reserved,descriptor_count;
 reg[6:0]output_reserved,pixel_count;
 reg[7:0]dr,dw;reg[5:0]pr,pw;
 reg[136:0]descriptors[0:255];reg[47:0]pixels[0:63];
 wire running=state==RUN&&!abort;
 wire math_reset_n=rst_n&&!abort&&state!=IDLE;
 wire[11:0]logical_x=ix<ACTIVE_X ? 12'd0 : ix>=ACTIVE_X+ACTIVE_W ? ACTIVE_W-1 : ix-ACTIVE_X;
 wire[11:0]expected_logical_x=cx<ACTIVE_X ? 12'd0 : cx>=ACTIVE_X+ACTIVE_W ? ACTIVE_W-1 : cx-ACTIVE_X;
 wire issue=running&&issued<OUT_W*OUT_H&&coord_reserved<256;
 wire req_valid,req_inside,req_error,out_valid,pending,solver_reject;
 wire[23:0]req_tag,a00,a10,a01,a11,out_rgb,out_tag;
 wire[7:0]fx,fy;
 wire descriptor_push=running&&req_valid;
 wire descriptor_pop=q_valid&&q_ready;
 wire stale=r_generation!=generation;
 assign r_ready=stale||!running||output_reserved<64;
 wire response_pop=r_valid&&r_ready&&!stale&&running;
 wire pixel_push=running&&out_valid;
 wire pixel_pop=write_valid&&write_ready;
 assign busy=state!=IDLE;
 assign q_generation=generation;
 assign q_valid=running&&descriptor_count!=0;
 assign {q_inside,q_tag,q_addr00,q_addr10,q_addr01,q_addr11,q_fx,q_fy}=descriptors[dr];
 assign q_nearest=mode;
 assign write_valid=running&&pixel_count!=0;
 assign {write_addr,write_rgb}=pixels[pr];
 assign cfg_ready=RUNTIME_AFFINE&&state==IDLE&&start&&!abort;
 // The mailbox retains its latest descriptor even without a new command.
 // Snapshot it on every frame launch, including after a DDR-side recovery.
 // Only a consumed new command emits a sequence receipt.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin active_affine<=DEFAULT_AFFINE;commit_valid<=0;commit_sequence<=0;end
  else begin
   commit_valid<=0;
   if(cfg_ready)begin
    active_affine<=cfg_affine;
    if(cfg_valid)begin commit_valid<=1;commit_sequence<=cfg_sequence;end
   end
  end
 end
 generate if(RUNTIME_AFFINE)begin: runtime_geometry
 assign math_debug_h={40'sh0001000000,40'sh0000000000,40'sh0000000000,active_affine};
 assign pending=1'b1;assign solver_reject=1'b0;assign geometry_valid=state!=IDLE;
 lens_affine_instance algorithm(
 .clk(clk),.rst_n(math_reset_n),.in_valid(issue),.nearest(mode),.affine(active_affine),
 .dst_x(logical_x),.dst_y(iy),
 .req_valid(req_valid),.req_inside(req_inside),.req_error(req_error),.req_tag(req_tag),
 .addr00(a00),.addr10(a10),.addr01(a01),.addr11(a11),.req_fx(fx),.req_fy(fy),
 .rsp_valid(response_pop),.rsp_inside(r_inside),.rsp_tag(r_tag),.p00(r_p00),.p10(r_p10),.p01(r_p01),.p11(r_p11),.rsp_fx(r_fx),.rsp_fy(r_fy),
 .out_valid(out_valid),.out_rgb(out_rgb),.out_tag(out_tag));
 end else if(FIXED_IDENTITY)begin: fixed_geometry
 assign math_debug_h={40'sh0001000000,40'sh0000000000,40'sh0000000000,40'sh0006000000,40'sh0000fe56d6,40'sh0000000000,40'sh0008b988e6,40'sh0000000000,40'sh0000fe56d6};assign pending=1'b1;assign solver_reject=1'b0;assign geometry_valid=state!=IDLE;
 lens_autocrop_instance algorithm(
 .clk(clk),.rst_n(math_reset_n),.in_valid(issue),.nearest(mode),
 .dst_x(logical_x),.dst_y(iy),
 .req_valid(req_valid),.req_inside(req_inside),.req_error(req_error),.req_tag(req_tag),
 .addr00(a00),.addr10(a10),.addr01(a01),.addr11(a11),.req_fx(fx),.req_fy(fy),
 .rsp_valid(response_pop),.rsp_inside(r_inside),.rsp_tag(r_tag),.p00(r_p00),.p10(r_p10),.p01(r_p01),.p11(r_p11),.rsp_fx(r_fx),.rsp_fy(r_fy),
 .out_valid(out_valid),.out_rgb(out_rgb),.out_tag(out_tag));
 end else begin: corner_geometry
 c_corner_rectifier #(.SRC_W(SRC_W),.SRC_H(SRC_H),.OUT_W(ACTIVE_W),.OUT_H(OUT_H),.UPDATE_EVERY(1)) algorithm(
 .debug_h(math_debug_h),.clk(clk),.rst_n(math_reset_n),.src_valid(1'b0),.src_frame_start(1'b0),.src_frame_end(1'b0),.src_x(12'd0),.src_y(12'd0),.src_rgb(24'd0),
 .dst_valid(issue),.dst_frame_start(state==COMMIT),.nearest(mode),.dst_x(logical_x),.dst_y(iy),
 .corners_valid(state==PREP),.marker_reject(),.marker_dropped(),.solver_reject(solver_reject),
 .x0(corners[95:84]),.y0(corners[83:72]),.x1(corners[71:60]),.y1(corners[59:48]),.x2(corners[47:36]),.y2(corners[35:24]),.x3(corners[23:12]),.y3(corners[11:0]),
 .geometry_valid(geometry_valid),.params_pending(pending),.stale_frames(),
 .req_valid(req_valid),.req_inside(req_inside),.req_error(req_error),.req_tag(req_tag),
 .addr00(a00),.addr10(a10),.addr01(a01),.addr11(a11),.req_fx(fx),.req_fy(fy),
 .rsp_valid(response_pop),.rsp_inside(r_inside),.rsp_tag(r_tag),.p00(r_p00),.p10(r_p10),.p01(r_p01),.p11(r_p11),.rsp_fx(r_fx),.rsp_fy(r_fy),
 .out_valid(out_valid),.out_rgb(out_rgb),.out_tag(out_tag));
 end endgenerate
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 state<=IDLE;generation<=0;mode<=0;corners<=0;done<=0;error<=0;failure_reason<=0;cycles<=0;completed_pixels<=0;
 ix<=0;iy<=0;cx<=0;cy<=0;rx<=0;ry<=0;ox<=0;oy<=0;wx<=0;wy<=0;o_addr<=0;w_addr<=0;
 issued<=0;accepted<=0;responded<=0;produced<=0;coord_reserved<=0;descriptor_count<=0;output_reserved<=0;pixel_count<=0;dr<=0;dw<=0;pr<=0;pw<=0;
 end else begin
 done<=0;error<=0;
 if(abort)state<=IDLE;
 else if(state==IDLE)begin
 ix<=0;iy<=0;cx<=0;cy<=0;rx<=0;ry<=0;ox<=0;oy<=0;wx<=0;wy<=0;o_addr<=0;w_addr<=0;
 issued<=0;accepted<=0;responded<=0;produced<=0;coord_reserved<=0;descriptor_count<=0;output_reserved<=0;pixel_count<=0;dr<=0;dw<=0;pr<=0;pw<=0;
 if(start)begin
 generation<=generation+1;cycles<=0;completed_pixels<=0;failure_reason<=0;corners<=input_corners;mode<=nearest;
 if(!FIXED_IDENTITY&&!RUNTIME_AFFINE&&!input_geometry_valid)begin error<=1;failure_reason<=3;end
 else state<=PREP;
 end
 end else begin
 cycles<=cycles+1;
 if(state==PREP)state<=SOLVE;
 if(state==SOLVE&&pending)state<=COMMIT;
 if(state==COMMIT)state<=RUN;
 if(running)begin
 case({issue,descriptor_pop}) 2'b10:coord_reserved<=coord_reserved+1;2'b01:coord_reserved<=coord_reserved-1;default:begin end endcase
 case({descriptor_push,descriptor_pop})2'b10:descriptor_count<=descriptor_count+1;2'b01:descriptor_count<=descriptor_count-1;default:begin end endcase
 case({response_pop,pixel_pop})2'b10:output_reserved<=output_reserved+1;2'b01:output_reserved<=output_reserved-1;default:begin end endcase
 case({pixel_push,pixel_pop})2'b10:pixel_count<=pixel_count+1;2'b01:pixel_count<=pixel_count-1;default:begin end endcase
 if(issue)begin issued<=issued+1;{iy,ix}<=next_xy(ix,iy);end
 if(descriptor_push)begin
 descriptors[dw]<={req_inside&&(cx>=ACTIVE_X)&&(cx<ACTIVE_X+ACTIVE_W),cy,cx,a00,a10,a01,a11,fx,fy};dw<=dw+1;
 {cy,cx}<=next_xy(cx,cy);
 end
 if(descriptor_pop)begin dr<=dr+1;accepted<=accepted+1;end
 if(response_pop)begin responded<=responded+1;{ry,rx}<=next_xy(rx,ry);end
 if(pixel_push)begin
 pixels[pw]<={o_addr,out_rgb};pw<=pw+1;produced<=produced+1;
 {oy,ox}<=next_xy(ox,oy);o_addr<=next_address(o_addr,ox,oy);
 end
 if(pixel_pop)begin
 pr<=pr+1;completed_pixels<=completed_pixels+1;
 {wy,wx}<=next_xy(wx,wy);w_addr<=next_address(w_addr,wx,wy);
 if(completed_pixels==OUT_W*OUT_H-1)begin done<=1;state<=IDLE;end
 end
 if((descriptor_push&&(req_tag!={cy,expected_logical_x}||descriptor_count==256))||
 (response_pop&&(r_tag!={ry,rx}||responded>=accepted))||
 (pixel_push&&(out_tag!={oy,ox}||pixel_count==64))||
 (pixel_pop&&write_addr!=w_addr))begin error<=1;failure_reason<=11;state<=IDLE;done<=0;end
 end
 if(solver_reject)begin error<=1;failure_reason<=4;state<=IDLE;done<=0;end
 if(cycles>=TIMEOUT_CYCLES-1)begin error<=1;failure_reason<=5;state<=IDLE;done<=0;end
 end
 end
 end
// Preserve H across the math-only reset at processor completion. The first
 // RUN cycle follows the atomic coefficient commit and precedes all results.
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)debug_h<=0;else if(state==RUN&&issued==0)debug_h<=math_debug_h;
 end
 // synthesis translate_off
 initial if(TILED_ORDER&&(OUT_W<64||OUT_W%64!=0||OUT_H<8||OUT_H%8!=0))
  $fatal(1,"TILED_ORDER requires complete64x8 output tiles");
 // synthesis translate_on
endmodule
`default_nettype wire

