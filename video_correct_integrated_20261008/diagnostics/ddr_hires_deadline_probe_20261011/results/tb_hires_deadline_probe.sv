`timescale 1ns/1ps
module tb_hires_deadline_probe;
 localparam CONTENTIOUS=0;
 localparam OW=640,OH=904,HS=44,HB=148,HA=1920,HF=88,VS=5,VB=36,VA=1080,VF=4;
 localparam X0=HS+HB+(HA-OW)/2,Y0=VS+VB+(VA-OH)/2;
 reg ui_clk=0,pix_clk=0,reset_n=0,pub_toggle=0,pub_bank=0;
 always #4 ui_clk=~ui_clk;
 always #3.3670035 pix_clk=~pix_clk;
 wire [63:0] diagnostics;
 wire ack,cmd_valid;wire [27:0] cmd_addr;
 wire cmd_ready;
 reg rsp_valid=0;reg [255:0] rsp_data=0;
 wire hs,vs,de,image_valid,underrun;wire [23:0] rgb;
 integer ui_cycle=0,delay_count=0,requests=0,mem_y,mem_x,mem_bank;
 reg pending=0;reg [255:0] held_word;
 reg [11:0] hd1=0,hd2=0,vd1=0,vd2=0;
 integer frame_bank=0,checked_pixels=0,completed_frames=0;
 integer correct_pixels=0,black_pixels=0;
 reg previous_vs=0,test_passed=0;
 function [23:0] encode_pixel(input integer bank,input integer y,input integer x);
  encode_pixel=((bank+1)<<22)|(y<<10)|x;
 endfunction
 ddr_result_display #(.OUT_W(OW),.OUT_H(OH),.SCALE(1)) dut(
  .ui_clk(ui_clk),.ui_rst_n(reset_n),.pix_clk(pix_clk),.pix_rst_n(reset_n),.publish_toggle(pub_toggle),.publish_bank(pub_bank),
  .ack_toggle(ack),.force_pattern(1'b0),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_addr(cmd_addr),
  .rsp_valid(rsp_valid),.rsp_rdata(rsp_data),.hsync(hs),.vsync(vs),.de(de),.rgb(rgb),.image_valid(image_valid),.underrun(underrun),.diagnostic_snapshot(diagnostics));
 assign cmd_ready=reset_n&&!pending&&(ui_cycle%7!=0)&&(!CONTENTIOUS||(ui_cycle%32<16));
 always @(posedge ui_clk)begin
  rsp_valid<=0;ui_cycle<=ui_cycle+1;
  if(cmd_valid&&cmd_ready)begin
   if(cmd_addr[2:0]!=0)$fatal(1,"unaligned row beat");
   mem_bank=(cmd_addr>=28'h0200000);
   mem_y=(cmd_addr-(mem_bank?28'h0200000:28'h0100000))/OW;
   mem_x=(cmd_addr-(mem_bank?28'h0200000:28'h0100000))%OW;
   if(mem_y>=OH||mem_x>=OW)$fatal(1,"invalid high-resolution row address");
   for(integer lane=0;lane<8;lane=lane+1)held_word[lane*32+:32]={8'd0,encode_pixel(mem_bank,mem_y,mem_x+lane)};
   delay_count<=28+(ui_cycle%3);pending<=1;requests<=requests+1;
  end
  if(pending)begin
   if(delay_count==0)begin rsp_data<=held_word;rsp_valid<=1;pending<=0;end
   else delay_count<=delay_count-1;
  end
 end
 always @(posedge pix_clk)begin hd1<=dut.hc;hd2<=hd1;vd1<=dut.vc;vd2<=vd1;end
 always @(negedge pix_clk)if(reset_n)begin
  if(vs&&!previous_vs)begin frame_bank=dut.display_bank;checked_pixels=0;end
  if(image_valid&&de&&hd2>=X0&&hd2<X0+OW&&vd2>=Y0&&vd2<Y0+OH)begin
   if(rgb===encode_pixel(frame_bank,vd2-Y0,hd2-X0))correct_pixels=correct_pixels+1;
   else if(rgb===24'd0)black_pixels=black_pixels+1;
   else $fatal(1,"late display output an incorrect/stale row instead of black");
   checked_pixels=checked_pixels+1;
   if(hd2==X0+OW-1&&vd2==Y0+OH-1)begin
    if(checked_pixels!=OW*OH)$fatal(1,"incomplete native frame %0d",checked_pixels);
    if(!underrun || black_pixels<OW*(OH/2))$fatal(1,"slow model did not reproduce missing rows");
    completed_frames=completed_frames+1;
   end
  end
  previous_vs=vs;
 end
 initial begin
  repeat(8)@(negedge pix_clk);reset_n=1;
  repeat(8)@(negedge pix_clk);pub_toggle=1;
  wait(ack==pub_toggle);
  wait(completed_frames>=1);
  if(diagnostics[47:32]<=1852)$fatal(1,"row timing did not report service time beyond one physical scan line");
  test_passed=1;$display("DDR_DEADLINE_REPRODUCED correct_pixels=%0d black_pixels=%0d max_row_cycles=%0d one_line_budget=1852 hypothetical_memory_only=1",correct_pixels,black_pixels,diagnostics[47:32]);$finish;
 end
 initial begin #150000000;$fatal(1,"native high resolution display timeout");end
endmodule
