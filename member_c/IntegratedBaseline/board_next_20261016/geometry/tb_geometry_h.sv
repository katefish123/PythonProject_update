`timescale 1ns/1ps
module tb_geometry_h;
reg clk=0;always #8.754037 clk=~clk;
reg rst_n=0,start=0,in_valid=0;reg[11:0]x0,y0,x1,y1,x2,y2,x3,y3,dst_x=0,dst_y=0;reg[7:0]in_tag=0;
wire busy,done,error,out_valid,out_error;wire[19:0]src_x_q,src_y_q;wire[7:0]out_tag;
wire signed[39:0]h[0:8];reg[39:0]expected_h[0:8];reg[63:0]probes[0:24];integer received=0;
homography_solver #(.SRC_W(1920),.SRC_H(1080),.OUT_W(765),.OUT_H(1080)) solver(clk,rst_n,start,x0,y0,x1,y1,x2,y2,x3,y3,busy,done,error,h[0],h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8]);
perspective_coord #(.TAG_W(8)) coordinates(clk,rst_n,in_valid,dst_x,dst_y,in_tag,h[0],h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8],out_valid,out_error,src_x_q,src_y_q,out_tag);
always @(posedge clk)if(rst_n&&out_valid)begin
if(out_error||out_tag!=received||src_x_q!==probes[received][39:20]||src_y_q!==probes[received][19:0])$fatal(1,"H direction/grid mismatch probe=%0d",received);
if(received==0||received==4||received==20||received==24)$display("H_CORNER dst=%0d,%0d source_UQ8=%0d,%0d",probes[received][63:52],probes[received][51:40],src_x_q,src_y_q);
received<=received+1;
end
task check;input string folder;begin
$readmemh({folder,"/H40.hex"},expected_h);$readmemh({folder,"/probes64.hex"},probes);
@(negedge clk);start=1;@(negedge clk);start=0;wait(done);if(error)$fatal(1,"B solver rejected");
for(integer j=0;j<9;j=j+1)if(h[j]!==expected_h[j])$fatal(1,"B integer H mismatch coefficient=%0d",j);
received=0;
for(integer k=0;k<25;k=k+1)begin @(negedge clk);in_valid=1;dst_x=probes[k][63:52];dst_y=probes[k][51:40];in_tag=k;end
@(negedge clk);in_valid=0;wait(received==25);repeat(3)@(negedge clk);
$display("PASS original B solver/perspective25 independent probes exact H direction %s",folder);
end endtask
initial begin
repeat(5)@(negedge clk);rst_n=1;
x0=650;y0=70;x1=1250;y1=110;x2=1320;y2=1010;x3=590;y3=960;
check("D:/FPGA/worktrees/c_pipeline_next/member_c/IntegratedBaseline/board_next_20261016/geometry/fixtures/canonical");
x0=1100;y0=100;x1=1700;y1=160;x2=1650;y2=950;x3=1150;y3=900;
check("D:/FPGA/worktrees/c_pipeline_next/member_c/IntegratedBaseline/board_next_20261016/geometry/fixtures/right_side");
$display("PASS B math unmodified2 color quads H and50 grid probes with independent software oracle");$finish;
end
initial begin #1000000;$fatal(1,"H timeout");end
endmodule
