`timescale 1ns/1ps
module tb_frame_region #(parameter NATIVE=0);
 localparam SW=NATIVE?1920:128,SH=NATIVE?1080:72,PIXELS=SW*SH;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg cfg_valid=0,frame_start=0,downstream_idle=1;wire cfg_ready,cfg_error,cfg_committed,cfg_deferred,pending_valid,active_valid;
 reg[95:0]cfg_quad;reg[11:0]cfg_target_x=SW/4,cfg_target_y=SH/4;
 reg[12:0]cfg_target_w=SW/2,cfg_target_h=SH/2,cfg_width=SW,cfg_height=SH;
 reg[15:0]cfg_aspect_num=SW,cfg_aspect_den=SH;reg[1:0]cfg_provenance=1;
 reg[23:0]cfg_background=24'ha1b2c3;reg cfg_markers_enabled=1,cfg_bank=0;
 reg[31:0]cfg_frame_id=1,cfg_version=42,cfg_mode=7;
 reg[12:0]expected_width=SW,expected_height=SH;reg[31:0]expected_mode=7;
 wire[31:0]active_frame_id,active_version;
 reg send_active=0,stalls=0,manual_hold=0;integer sent=0,received=0,limit=0,tick=0,errors=0;
 reg[31:0]in_frame_id=1,in_version=42,in_mask_frame_id=1,in_mask_version=42;
 reg in_bank=0,in_mask_valid=1;
 wire in_valid=send_active&&sent<limit;wire in_ready;
 wire[11:0]in_x=sent%SW,in_y=sent/SW;
 wire[31:0]in_tag=sent;
 function[23:0]pattern(input integer x,y);reg[7:0]r,g,b;begin r=(x*3+y*7)%256;g=(x*11+y*5)%256;b=(x*17+y*13)%256;pattern={r,g,b};end endfunction
 wire[23:0]in_rgb=pattern(in_x,in_y);
 integer qx[0:3],qy[0:3];
 function bit marker(input integer x,y);
 bit hit;begin hit=0;for(integer i=0;i<4;i++)if(x>=qx[i]-SW/128-1&&x<=qx[i]+SW/128+1&&y>=qy[i]-SH/72-1&&y<=qy[i]+SH/72+1&&((x+y)%4!=0))hit=1;return hit;end endfunction
 wire in_marker_hit=marker(in_x,in_y);
 wire out_valid;wire out_ready=!manual_hold&&(!stalls||tick%11<8);
 wire[1:0]out_route;wire out_scene_valid,out_markers_enabled,out_bank;
 wire[11:0]out_x,out_y,out_u,out_v;wire[23:0]out_rgb,out_background;
 wire[31:0]out_tag,out_frame_id,out_version;
 frame_region dut(.*);
 integer raw_count=0,fill_count=0,warp_count=0,outside_count=0,accept_cycles=0,first_accept_tick=0,last_accept_tick=0;
 reg expected_scene=1;reg[23:0]expected_bg=24'ha1b2c3;
 function bit quad_contains(input integer x,y);
 longint z;bit ok;begin ok=1;for(integer i=0;i<4;i++)begin
 z=(qx[(i+1)%4]-qx[i])*(y-qy[i])-(qy[(i+1)%4]-qy[i])*(x-qx[i]);if(z<0)ok=0;end return ok;end endfunction
 always @(posedge clk)begin
 tick<=tick+1;if(cfg_error)errors<=errors+1;
 if(rst_n&&in_valid&&in_ready)begin
 if(sent==0)first_accept_tick<=tick;
 else if(!stalls&&!manual_hold&&tick!=last_accept_tick+1)$fatal(1,"ROUTER_NOT_ONE_PIXEL_PER_CLOCK");
 last_accept_tick<=tick;sent<=sent+1;accept_cycles<=accept_cycles+1;end
 if(rst_n&&out_valid&&out_ready)begin: score
 integer x,y,want;reg[23:0]rgb;
 x=received%SW;y=received/SW;want=0;
 if(expected_scene)begin
 if(marker(x,y))want=1;
 else if(quad_contains(x,y))want=(x>=SW/4&&x<SW/4+SW/2&&y>=SH/4&&y<SH/4+SH/2)?2:1;
 end
 rgb=want==1?expected_bg:pattern(x,y);
 if(out_tag!==received||out_x!==x||out_y!==y||out_rgb!==rgb||out_route!==want||out_scene_valid!==expected_scene
 ||out_frame_id!==in_frame_id||out_version!==in_version||out_bank!==in_bank||out_background!==expected_bg
 ||out_markers_enabled!==expected_scene)$fatal(1,"region pixel%0d route%0d wanted%0d scene%b wanted%b RGB%h/%h",received,out_route,want,out_scene_valid,expected_scene,out_rgb,rgb);
 if(want==2)begin if(out_u!==x-SW/4||out_v!==y-SH/4)$fatal(1,"local target coords wrong");warp_count<=warp_count+1;end
 else begin if(out_u!=0||out_v!=0)$fatal(1,"invalid local coordinate exposed");if(want==0)raw_count<=raw_count+1;else fill_count<=fill_count+1;end
 if(!quad_contains(x,y)&&!marker(x,y))begin if(out_rgb!==pattern(x,y))$fatal(1,"OUTSIDE_ORIGINAL_FRAME_CHANGED");outside_count<=outside_count+1;end
 received<=received+1;
 end end
 task boundary;begin @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;end endtask
 task load_config;
 begin @(negedge clk);while(!cfg_ready)@(negedge clk);cfg_valid=1;@(negedge clk);cfg_valid=0;end endtask
 task wait_pending;
 integer n;begin n=0;while(!pending_valid)begin @(negedge clk);n++;if(n>40)$fatal(1,"geometry validation did not finish");end end endtask
 task run_pixels(input integer n,input bit stall_pattern);
 begin @(negedge clk);sent=0;received=0;limit=n;accept_cycles=0;stalls=stall_pattern;send_active=1;
 wait(received==n);@(negedge clk);send_active=0;repeat(3)@(negedge clk);
 if(sent!=n||out_valid)$fatal(1,"pixel loss or stale output");end endtask
 initial begin: test
 integer prior;reg[255:0]held;
 qx[0]=SW/10;qy[0]=SH/10;qx[1]=SW*9/10;qy[1]=SH/8;
 qx[2]=SW*15/16;qy[2]=SH*7/8;qx[3]=SW/16;qy[3]=SH*9/10;
 cfg_quad={12'(qx[0]),12'(qy[0]),12'(qx[1]),12'(qy[1]),12'(qx[2]),12'(qy[2]),12'(qx[3]),12'(qy[3])};
 repeat(3)@(negedge clk);rst_n=1;load_config();wait_pending();
 if(active_valid)$fatal(1,"pending config applied before boundary");boundary();
 if(!active_valid||active_version!=42)$fatal(1,"valid scene not committed");
 run_pixels(PIXELS,0);if(accept_cycles!=PIXELS||outside_count==0||raw_count==0||fill_count==0||warp_count==0)$fatal(1,"native route coverage missing");
 if(last_accept_tick-first_accept_tick+1!=PIXELS)$fatal(1,"admission span does not match native full raster");
 $display("REGION_SCAN pixels=%0d outside_identity=%0d raw=%0d fill=%0d warp=%0d accepted_cycles=%0d admission_span_cycles=%0d",PIXELS,outside_count,raw_count,fill_count,warp_count,accept_cycles,last_accept_tick-first_accept_tick+1);
 if(!NATIVE)begin
 run_pixels(257,1);
 in_mask_version=999;expected_scene=0;run_pixels(259,1);in_mask_version=42;expected_scene=1;
 in_frame_id=9;in_mask_frame_id=9;expected_scene=0;run_pixels(271,1);in_frame_id=1;in_mask_frame_id=1;expected_scene=1;
 in_bank=1;expected_scene=0;run_pixels(273,1);in_bank=0;expected_scene=1;
 in_version=90;in_mask_version=90;expected_scene=0;run_pixels(277,1);in_version=42;in_mask_version=42;expected_scene=1;
 prior=errors;cfg_aspect_den=0;load_config();repeat(30)@(negedge clk);if(errors==prior||pending_valid||active_version!=42)$fatal(1,"zero aspect denominator accepted");cfg_aspect_den=SH;
 prior=errors;cfg_target_x=0;load_config();repeat(30)@(negedge clk);if(errors==prior||pending_valid)$fatal(1,"rectangle outside quad accepted");cfg_target_x=SW/4;
 prior=errors;cfg_width=SW-1;load_config();repeat(30)@(negedge clk);if(errors==prior||pending_valid)$fatal(1,"runtime dimension mismatch accepted");cfg_width=SW;
 prior=errors;cfg_quad[95:72]=cfg_quad[71:48];load_config();repeat(30)@(negedge clk);if(errors==prior||pending_valid)$fatal(1,"degenerate quad accepted");cfg_quad[95:72]={12'(qx[0]),12'(qy[0])};
 @(negedge clk);sent=0;received=0;limit=1;manual_hold=1;send_active=1;
 wait(out_valid);@(negedge clk);send_active=0;
 held={out_route,out_scene_valid,out_x,out_y,out_u,out_v,out_rgb,out_background,out_tag,out_frame_id,out_version,out_bank,out_markers_enabled};
 cfg_frame_id=2;cfg_version=43;cfg_background=24'h445566;load_config();wait_pending();boundary();
 if(!cfg_deferred||active_version!=42||held!=={out_route,out_scene_valid,out_x,out_y,out_u,out_v,out_rgb,out_background,out_tag,out_frame_id,out_version,out_bank,out_markers_enabled})$fatal(1,"STALLED_PACKET_CHANGED_ON_FRAME_COMMIT");
 manual_hold=0;wait(received==1);repeat(3)@(negedge clk);
 downstream_idle=0;boundary();if(!cfg_deferred||active_version!=42)$fatal(1,"commit ignored downstream ownership");
 downstream_idle=1;boundary();if(active_version!=43||pending_valid)$fatal(1,"deferred scene not committed");
 in_frame_id=2;in_version=43;in_mask_frame_id=2;in_mask_version=43;expected_bg=24'h445566;
 run_pixels(263,1);
 expected_mode=8;expected_scene=0;run_pixels(269,1);expected_mode=7;expected_scene=1;
 cfg_frame_id=3;cfg_version=44;load_config();wait_pending();expected_mode=8;boundary();
 if(pending_valid||active_valid||active_version!=43)$fatal(1,"pending scene mode changed but committed");expected_mode=7;
 @(negedge clk);manual_hold=1;sent=0;received=0;limit=1;send_active=1;wait(out_valid);
 @(negedge clk);send_active=0;rst_n=0;@(negedge clk);rst_n=1;
 if(out_valid||pending_valid||active_valid)$fatal(1,"scene or packet survived reset");manual_hold=0;
 end
 $display("PASS FRAME_REGION native=%0d same-size routing,outside identity,exact marker flags,association,backpressure,deferred commit,geometry validation,reset",NATIVE);$finish;
 end
 initial begin #60000000;$fatal(1,"region timeout sent%0d received%0d",sent,received);end
endmodule
