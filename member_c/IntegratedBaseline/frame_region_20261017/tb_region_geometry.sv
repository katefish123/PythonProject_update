`timescale 1ns/1ps
module tb_region_geometry;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg cfg_valid=0,frame_start=0;wire cfg_ready,cfg_error,pending_valid,active_valid;
 reg[95:0]cfg_quad;reg[11:0]cfg_target_x=0,cfg_target_y=0;
 reg[12:0]cfg_target_w=4096,cfg_target_h=4096,cfg_width=4096,cfg_height=4096,expected_width=4096,expected_height=4096;
 reg[15:0]cfg_aspect_num=1,cfg_aspect_den=1;reg[1:0]cfg_provenance=1;
 reg[31:0]cfg_frame_id=1,cfg_version=1;wire[31:0]active_version;
 reg in_valid=0;wire in_ready,out_valid;reg[11:0]in_x=0,in_y=0;wire[11:0]out_u,out_v;wire[1:0]out_route;wire out_scene_valid;
 frame_region dut(.clk(clk),.rst_n(rst_n),.cfg_valid(cfg_valid),.cfg_ready(cfg_ready),.frame_start(frame_start),.downstream_idle(1'b1),
 .cfg_quad(cfg_quad),.cfg_target_x(cfg_target_x),.cfg_target_y(cfg_target_y),.cfg_target_w(cfg_target_w),.cfg_target_h(cfg_target_h),
 .cfg_width(cfg_width),.cfg_height(cfg_height),.cfg_aspect_num(cfg_aspect_num),.cfg_aspect_den(cfg_aspect_den),.cfg_provenance(cfg_provenance),
 .cfg_background(24'h808080),.cfg_markers_enabled(1'b0),.cfg_bank(1'b0),.cfg_frame_id(cfg_frame_id),.cfg_version(cfg_version),.cfg_mode(32'd7),
 .expected_width(expected_width),.expected_height(expected_height),.expected_mode(32'd7),.cfg_error(cfg_error),.cfg_committed(),.cfg_deferred(),.pending_valid(pending_valid),.active_valid(active_valid),.active_frame_id(),.active_version(active_version),
 .in_valid(in_valid),.in_ready(in_ready),.in_x(in_x),.in_y(in_y),.in_rgb(24'habcdef),.in_tag(32'd1),.in_frame_id(cfg_frame_id),.in_version(cfg_version),.in_mask_frame_id(32'd0),.in_mask_version(32'd0),.in_bank(1'b0),.in_mask_valid(1'b0),.in_marker_hit(1'b1),
 .out_valid(out_valid),.out_ready(1'b1),.out_route(out_route),.out_scene_valid(out_scene_valid),.out_markers_enabled(),.out_bank(),.out_x(),.out_y(),.out_u(out_u),.out_v(out_v),.out_rgb(),.out_background(),.out_tag(),.out_frame_id(),.out_version());
 integer errors=0,cases=0;
 always @(posedge clk)if(cfg_error)errors++;
 task configure(input bit accept);
 integer prior,n;begin
 @(negedge clk);while(!cfg_ready)@(negedge clk);prior=errors;cfg_valid=1;@(negedge clk);cfg_valid=0;
 for(n=0;n<30;n++)@(negedge clk);
 if(accept)begin
 if(!pending_valid||errors!=prior)$fatal(1,"boundary geometry rejected case%0d",cases);
 frame_start=1;@(negedge clk);frame_start=0;if(!active_valid||active_version!=cfg_version)$fatal(1,"boundary scene commit failed");
 end else if(pending_valid||errors==prior)$fatal(1,"invalid boundary geometry accepted case%0d",cases);
 cases++;end endtask
 task pixel(input integer x,y);
 begin @(negedge clk);in_x=x;in_y=y;in_valid=1;#1;if(!in_ready)$fatal(1,"edge pixel not accepted");
 @(negedge clk);in_valid=0;wait(out_valid);@(negedge clk);
 if(out_route!=2||!out_scene_valid||out_u!=x||out_v!=y)$fatal(1,"edge arithmetic failure x%0d y%0d",x,y);
 repeat(2)@(negedge clk);end endtask
 initial begin
 cfg_quad={12'd0,12'd0,12'd4095,12'd0,12'd4095,12'd4095,12'd0,12'd4095};
 repeat(3)@(negedge clk);rst_n=1;configure(1);
 pixel(0,0);pixel(4095,0);pixel(4095,4095);pixel(0,4095);
 cfg_target_x=4095;cfg_target_w=2;configure(0);cfg_target_x=0;cfg_target_w=4096;
 cfg_aspect_num=0;configure(0);cfg_aspect_num=1;
 cfg_frame_id=0;configure(0);cfg_frame_id=1;
 cfg_version=0;configure(0);cfg_version=2;
 cfg_provenance=2;configure(0);cfg_provenance=1;
 cfg_quad={12'd0,12'd0,12'd0,12'd4095,12'd4095,12'd4095,12'd4095,12'd0};configure(0);
 cfg_quad={12'd0,12'd0,12'd4095,12'd0,12'd4095,12'd4095,12'd0,12'd4095};
 expected_width=4097;cfg_width=4097;configure(0);expected_width=4096;cfg_width=4096;
 expected_width=1;cfg_width=1;configure(0);
 expected_width=2;expected_height=2;cfg_width=2;cfg_height=2;cfg_target_w=2;cfg_target_h=2;
 cfg_quad={12'd0,12'd0,12'd1,12'd0,12'd1,12'd1,12'd0,12'd1};configure(1);pixel(1,1);
 $display("PASS REGION_GEOMETRY cases=%0d 2/4096 edges,exclusive-end4096,no coordinate wrap,wrong winding,aspect/provenance/id/size rejects",cases);$finish;
 end
 initial begin #100000;$fatal(1,"geometry timeout");end
endmodule
