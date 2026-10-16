`timescale 1ns/1ps
module tb_geometry_cdc;
reg rx_clk=0,proc_clk=0,rst_n=0,proc_run=1;
always #3.367003367 rx_clk=~rx_clk;
always #8.754037 if(proc_run)proc_clk=~proc_clk;else proc_clk=0;
reg sample_valid=0,sample_first=0,sample_bank=1;reg[31:0]sample_generation=32'h12345678;
reg[11:0]sample_x=0,sample_y=0;reg[23:0]sample_rgb=0;
reg close_valid=0,close_bank=1,close_ok=1;reg[31:0]close_generation=32'h12345678;
wire metadata_valid,fault;reg metadata_ready=0;wire[129:0]metadata_data;
continuous_capture_geometry #(.FIFO_ADDR_BITS(5),.MIN_PIXELS(16),.MAX_PIXELS(4096),.MAX_SPAN(128)) dut(.*);
integer outputs=0;reg held=0;reg[129:0]held_data;
always @(posedge proc_clk)if(rst_n)begin
if(held&&(!metadata_valid||metadata_data!==held_data))$fatal(1,"metadata changed under backpressure");
held<=metadata_valid&&!metadata_ready;held_data<=metadata_data;
if(metadata_valid&&metadata_ready)begin $display("GEOMETRY_DESCRIPTOR bank=%0b generation=%h valid=%0b corners96=%h",metadata_data[129],metadata_data[128:97],metadata_data[96],metadata_data[95:0]);outputs<=outputs+1;end
end else held<=0;
function[23:0]pixel;input integer x,y,kind;integer cx,cy;begin
pixel=(x%100==0||y%100==0)?24'h606060:24'hd0d0d0;
for(integer c=0;c<4;c=c+1)begin
case(c)0:begin cx=650;cy=70;end 1:begin cx=1250;cy=110;end 2:begin cx=1320;cy=1010;end default:begin cx=590;cy=960;end endcase
if(x>=cx-10&&x<=cx+10&&y>=cy-10&&y<=cy+10)begin
if(kind!=0)pixel=0;else case(c)0:pixel=24'h64141e;1:pixel=24'h14be1e;2:pixel=24'ha0be14;3:pixel=24'h2814b4;endcase
end end
end endfunction
task full_frame;input integer kind;begin
for(integer y=0;y<1080;y=y+1)begin
for(integer x=0;x<1920;x=x+1)begin
@(negedge rx_clk);sample_valid=1;sample_first=x==0&&y==0;sample_x=x;sample_y=y;sample_rgb=pixel(x,y,kind);
end
@(negedge rx_clk);sample_valid=0;sample_first=0;repeat(280)@(negedge rx_clk);
end
@(negedge rx_clk);close_valid=1;close_bank=sample_bank;close_generation=sample_generation;close_ok=1;
@(negedge rx_clk);close_valid=0;
end endtask
task consume;input bit bank;input[31:0]generation;input bit valid;input[95:0]corners;begin
wait(metadata_valid);repeat(30)@(negedge proc_clk);
if(metadata_data!=={bank,generation,valid,corners})$fatal(1,"metadata bank/gen/corner mismatch got=%h",metadata_data);
metadata_ready=1;@(negedge proc_clk);metadata_ready=0;
end endtask
task overflow_frame;begin
for(integer n=0;n<1000;n=n+1)begin @(negedge rx_clk);sample_valid=1;sample_first=n==0;sample_x=n%1920;sample_y=n/1920;sample_rgb=24'he02020;end
@(negedge rx_clk);sample_valid=0;sample_first=0;close_valid=1;close_bank=sample_bank;close_generation=sample_generation;
@(negedge rx_clk);close_valid=0;repeat(5)@(negedge rx_clk);
end endtask
initial begin
repeat(8)@(negedge rx_clk);rst_n=1;
full_frame(0);consume(1,32'h12345678,1,{12'd650,12'd70,12'd1250,12'd110,12'd1320,12'd1010,12'd590,12'd960});
sample_generation=32'h12345679;sample_bank=0;full_frame(1);consume(0,32'h12345679,0,96'd0);
proc_run=0;repeat(3)@(negedge rx_clk);sample_generation=32'h1234567a;sample_bank=1;overflow_frame();
sample_generation=32'h1234567b;sample_bank=0;overflow_frame();if(dut.ec!=2||!dut.overflow)$fatal(1,"overflow/end-retention coverage absent");
proc_run=1;consume(1,32'h1234567a,0,96'd0);consume(0,32'h1234567b,0,96'd0);
if(fault||outputs!=4)$fatal(1,"CDC unexpected fault/count");
@(negedge rx_clk);rst_n=0;repeat(5)@(negedge proc_clk);rst_n=1;repeat(10)@(negedge proc_clk);
if(metadata_valid||fault||dut.ec)$fatal(1,"shared reset did not clear geometry path");
$display("PASS geometry CDC2 fullHD source rasters exact color corners/reject-black bank/gen held metadata and2 retained overflow terminals shared-reset");$finish;
end
initial begin #100000000;$fatal(1,"CDC timeout outputs=%0d",outputs);end
endmodule
