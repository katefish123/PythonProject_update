`timescale 1ns/1ps
`default_nettype none
// Exclusive writer owner. Publishes a descriptor, not an HDMI bank switch.
// Guard/writer/UI/engine reset and external bank reservation are coordinated.
module corrected_frame_guard #(parameter WIDTH=1920,HEIGHT=1080)(
 input wire clk,rst_n,start,output wire start_ready,input wire abort_frame,
 input wire[31:0]source_frame_id,source_version,input wire source_bank,result_bank,front_valid,front_bank,
 input wire in_valid,output wire in_ready,input wire in_scene_valid,in_error,
 input wire[11:0]in_x,in_y,input wire in_last,input wire[23:0]in_rgb,
 input wire[31:0]in_frame_id,in_version,input wire in_bank,
 input wire upstream_idle,writer_drained,writer_fault,output wire writer_frame_start,writer_abort,writer_bank,
 output wire write_valid,input wire write_ready,output wire[23:0]write_addr,write_rgb,
 output wire publish_valid,input wire publish_ready,output wire[31:0]publish_frame_id,publish_version,
 output wire publish_source_bank,publish_result_bank,output wire[12:0]publish_width,publish_height,
 output reg[24:0]completed_pixels,output wire busy,output reg failed,output reg[3:0]failure_reason);
 localparam IDLE=0,ARM=1,RUN=2,DRAIN=3,COMMIT=4,ABORT_DRAIN=5,TOTAL=WIDTH*HEIGHT;
 reg[2:0]state;reg[31:0]frame_id,version;reg sb,rb;reg[11:0]expected_x,expected_y;
 wire collision=front_valid&&front_bank==rb;
 wire scene_good=in_scene_valid&&!in_error;
 wire association_good=in_frame_id==frame_id&&in_version==version&&in_bank==sb;
 wire raster_good=in_x==expected_x&&in_y==expected_y&&in_last==(completed_pixels==TOTAL-1);
 wire pixel_good=scene_good&&association_good&&raster_good;
 assign busy=state!=IDLE;
 assign start_ready=state==IDLE&&upstream_idle&&writer_drained&&!writer_fault&&!abort_frame;
 assign writer_frame_start=state==ARM&&!abort_frame&&!writer_fault&&!collision;
 assign writer_bank=rb;
 assign writer_abort=state==ABORT_DRAIN||(busy&&(abort_frame||writer_fault||collision))||(state==RUN&&in_valid&&!pixel_good);
 assign in_ready=state==ABORT_DRAIN||(state==RUN&&!abort_frame&&!writer_fault&&!collision&&(!pixel_good||write_ready));
 assign write_valid=state==RUN&&in_valid&&pixel_good&&!abort_frame&&!writer_fault&&!collision;
 assign write_addr=completed_pixels[23:0];assign write_rgb=in_rgb;
 assign publish_valid=state==COMMIT&&upstream_idle&&writer_drained&&!abort_frame&&!writer_fault&&!collision;
 assign publish_frame_id=frame_id;assign publish_version=version;assign publish_source_bank=sb;assign publish_result_bank=rb;
 assign publish_width=WIDTH;assign publish_height=HEIGHT;
 task cancel(input[3:0]reason);begin state<=ABORT_DRAIN;failure_reason<=reason;end endtask
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin state<=IDLE;frame_id<=0;version<=0;sb<=0;rb<=0;expected_x<=0;expected_y<=0;completed_pixels<=0;failed<=0;failure_reason<=0;end
 else begin
 failed<=0;
 if(state!=IDLE&&state!=ABORT_DRAIN&&(abort_frame||writer_fault||collision))cancel(writer_fault?4'd7:collision?4'd6:4'd5);
 else case(state)
 IDLE:if(start&&start_ready)begin
 completed_pixels<=0;expected_x<=0;expected_y<=0;
 if(source_frame_id==0||source_version==0||(front_valid&&front_bank==result_bank))begin failed<=1;failure_reason<=1;end
 else begin frame_id<=source_frame_id;version<=source_version;sb<=source_bank;rb<=result_bank;failure_reason<=0;state<=ARM;end
 end
 ARM:state<=RUN;
 RUN:if(in_valid&&in_ready)begin
 if(!pixel_good)cancel(!scene_good?4'd2:!association_good?4'd3:4'd4);
 else begin
 completed_pixels<=completed_pixels+1'b1;
 if(completed_pixels==TOTAL-1)state<=DRAIN;
 else if(expected_x==WIDTH-1)begin expected_x<=0;expected_y<=expected_y+1'b1;end
 else expected_x<=expected_x+1'b1;
 end end
 DRAIN:if(writer_drained&&upstream_idle)state<=COMMIT;
 COMMIT:if(!writer_drained||!upstream_idle)cancel(4'd7);else if(publish_valid&&publish_ready)state<=IDLE;
 ABORT_DRAIN:if(writer_drained&&upstream_idle)begin state<=IDLE;failed<=1;end
 default:state<=IDLE;
 endcase end end
 // synthesis translate_off
 initial begin
 if(WIDTH<2||WIDTH>4096||HEIGHT<2||HEIGHT>4096||TOTAL>16777215||TOTAL%64!=0)$fatal(1,"Unsupported aligned64 canvas");
 end
 // synthesis translate_on
endmodule
`default_nettype wire
