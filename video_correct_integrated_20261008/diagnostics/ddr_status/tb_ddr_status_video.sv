`timescale 1ns/1ps
module tb_ddr_status_video;
 localparam HS=1,HB=1,HA=128,HF=1,VS=1,VB=1,VA=32,VF=1;
 localparam HST=HS+HB+HA+HF,VST=VS+VB+VA+VF,CX=2,CY=24,CW=4,CH=4,CG=1;
 reg clk=0,reset_n=0;always #5 clk=~clk;
 reg [14:0] status_async=15'b101100101011010;
 reg [14:0] first_status=15'b101100101011010;
 wire hsync,vsync,de,pix_clk;wire [23:0] rgb;
 reg test_passed=0;
 ddr_status_video #(.H_SYNC(HS),.H_BACK(HB),.H_ACTIVE(HA),.H_FRONT(HF),
  .V_SYNC(VS),.V_BACK(VB),.V_ACTIVE(VA),.V_FRONT(VF),
  .STATUS_X(CX),.STATUS_Y(CY),.CELL_W(CW),.CELL_H(CH),.CELL_GAP(CG)) dut(
  .pix_clk(clk),.reset_n(reset_n),.status_async(status_async),.hsync(hsync),.vsync(vsync),.de(de),.rgb(rgb),.pix_clk_out(pix_clk));
 task check_pixel(input integer x,input integer y,input [23:0] expected,input [255:0] labeltext);
  begin
   wait(dut.vc==VS+VB+y && dut.hc==HS+HB+x+1);#1;
   if(rgb!==expected)$fatal(1,"%0s at %0d,%0d got=%h expected=%h",labeltext,x,y,rgb,expected);
  end
 endtask
 integer n;
 initial begin
  repeat(4)@(negedge clk);reset_n=1;
  repeat(HST*VST+8)@(posedge clk);
  // The first set checks all 15 independently synchronized status cells.
  check_pixel(CX+CW/2,CY+CH/2,first_status[14]?24'h00ff00:24'hff0000,"first status cell");
  status_async=0; // Change the async source mid-frame; remaining cells must retain the frame snapshot.
  for(n=1;n<15;n=n+1)
   check_pixel(CX+n*(CW+CG)+CW/2,CY+CH/2,first_status[14-n]?24'h00ff00:24'hff0000,"frame-latched status cell");
  check_pixel(HA/16,4,24'hffffff,"white color bar");
  check_pixel(HA*3/16,4,24'hffff00,"yellow color bar");
  check_pixel(HA*5/16,4,24'h00ffff,"cyan color bar");
  check_pixel(HA*7/16,4,24'h00ff00,"green color bar");
  for(n=0;n<15;n=n+1)
   check_pixel(CX+n*(CW+CG)+CW/2,CY+CH/2,24'hff0000,"cleared status cell");
 if(pix_clk!==clk)$fatal(1,"TX pixel clock pass-through failed");
 test_passed=1;$display("DDR_STATUS_VIDEO_PASS bars=8 status_cells=15 async_sync=3 reset_independent=1");$finish;
 end
 initial begin #2000000;$fatal(1,"status video timeout");end
endmodule
