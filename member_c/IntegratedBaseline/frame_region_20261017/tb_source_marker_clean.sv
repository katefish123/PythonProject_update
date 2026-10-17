`timescale 1ns/1ps
module tb_source_marker_clean;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg in_valid=0,out_ready=0,markers_enabled=0,mask_valid=0;
 wire in_ready,out_valid,out_error;
 reg[31:0]frame_id=0,version=0,mask_frame_id=0,mask_version=0,in_tag=0;
 reg[3:0]marker_hit=0;reg[23:0]background=0;reg[95:0]pixels=0;
 wire[95:0]out_pixels;wire[31:0]out_tag,out_frame_id,out_version;
 source_marker_clean dut(.*);
 task check(input integer i);
 reg[95:0]want,held;reg bad;begin
 @(negedge clk);markers_enabled=i%5!=0;mask_valid=i%7!=0;frame_id=17;version=23;
 mask_frame_id=i%11==0?18:17;mask_version=i%13==0?24:23;marker_hit=i%16;
 in_tag=i;background=24'h8293a4;pixels={24'h010203,24'h243546,24'h576879,24'h8a9bac};
 bad=markers_enabled&&(!mask_valid||mask_frame_id!=frame_id||mask_version!=version);
 want=pixels;for(integer j=0;j<4;j++)if(markers_enabled&&!bad&&marker_hit[j])want[j*24+:24]=background;
 in_valid=1;#1;if(!in_ready)$fatal(1,"unexpected input stall");@(negedge clk);in_valid=0;
 if(!out_valid||out_pixels!==want||out_error!==bad||out_tag!==i||out_frame_id!==17||out_version!==23)$fatal(1,"mask cleaner mismatch %0d",i);
 held=out_pixels;
 repeat(i%4)begin @(negedge clk);if(!out_valid||out_pixels!==held||in_ready)$fatal(1,"cleaner backpressure overwritten");end
 out_ready=1;@(negedge clk);out_ready=0;
 end endtask
 initial begin
 repeat(3)@(negedge clk);rst_n=1;
 for(integer i=0;i<256;i++)check(i);
 @(negedge clk);out_ready=1;in_valid=1;markers_enabled=1;mask_valid=1;frame_id=17;mask_frame_id=17;version=23;mask_version=23;
 for(integer j=0;j<128;j++)begin: stream_check
 reg[95:0]want;
 in_tag=j;marker_hit=j%16;want=pixels;
 for(integer k=0;k<4;k++)if(marker_hit[k])want[k*24+:24]=background;
 #1;if(!in_ready)$fatal(1,"cleanup cannot accept one token per clock");
 @(negedge clk);if(!out_valid||out_tag!==j||out_pixels!==want||out_error)$fatal(1,"stream cleanup mismatch %0d",j);
 end
 in_valid=0;@(negedge clk);out_ready=0;
 check(999);@(negedge clk);in_valid=1;@(negedge clk);in_valid=0;rst_n=0;@(negedge clk);rst_n=1;
 if(out_valid)$fatal(1,"cleanup packet survived reset");
 $display("PASS SOURCE_MARKER_CLEAN exact four-neighbor masks,unmarked identity,stale association rejection,backpressure,reset");$finish;
 end
 initial begin #100000;$fatal(1,"cleaner timeout");end
endmodule
