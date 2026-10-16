`timescale 1ns/1ps
`ifndef DETECTOR_MODULE
`define DETECTOR_MODULE marker_detector
`endif
module tb_image_regression;
reg clk=0;always #8.754037 clk=~clk;
reg rst_n=0,pixel_valid=0,frame_start=0,frame_end=0;reg[11:0]pixel_x=0,pixel_y=0;reg[23:0]rgb=0;
wire corners_valid,frame_reject,frame_dropped,busy;wire[11:0]x0,y0,x1,y1,x2,y2,x3,y3;
`DETECTOR_MODULE #(.SRC_W(1920),.SRC_H(1080),.MIN_PIXELS(16),.MAX_PIXELS(4096),.MAX_SPAN(128)) dut(.*);
integer cx[0:3],cy[0:3];reg[23:0]colors[0:3];reg got_valid=0,got_reject=0;
always @(posedge clk)if(rst_n)begin if(corners_valid)got_valid<=1;if(frame_reject||frame_dropped)got_reject<=1;end
reg[47:0]events[0:20000];reg[2047:0]path;reg[95:0]want_corners;integer fd,rc,n,want,cases=0;
initial begin
 repeat(5)@(negedge clk);rst_n=1;
 fd=$fopen("D:/FPGA/worktrees/c_pipeline_next/member_c/IntegratedBaseline/board_next_20261016/geometry/fixtures/cases.txt","r");if(!fd)$fatal(1,"missing image cases");
 while(!$feof(fd))begin
  rc=$fscanf(fd,"%s %d %h %d\n",path,want,want_corners,n);
  if(rc==4)begin
   if(n>0)$readmemh(path,events,0,n-1);
   got_valid=0;got_reject=0;frame_start=1;@(negedge clk);frame_start=0;
   for(integer i=0;i<n;i=i+1)begin pixel_valid=1;pixel_x=events[i][47:36];pixel_y=events[i][35:24];rgb=events[i][23:0];@(negedge clk);end
   pixel_valid=0;frame_end=1;@(negedge clk);frame_end=0;repeat(500)@(negedge clk);
   if(want)begin
    if(!got_valid||got_reject||{x0,y0,x1,y1,x2,y2,x3,y3}!==want_corners)$fatal(1,"image positive corners mismatch %s",path);
   end else if(got_valid||!got_reject)$fatal(1,"image negative accepted %s",path);
   $display("PASS RGB image regression valid=%0d events=%0d corners96=%h file=%s",want,n,want_corners,path);cases=cases+1;
  end
 end
 if(cases!=5)$fatal(1,"image case count");$display("PASS5 synthetic original1920x1080 RGB image regressions exact independent color centroid/order");$finish;
end
endmodule
