`timescale 1ns/1ps
// Application-layer storage model only; not DDR PHY or controller simulation.
module tb_ddr_frame_model;
parameter PIXELS=1920*1080;
reg clk=0,rst=0,pv=0,last=0,start=0,done=0,acquire=0,release_frame=0;
reg [23:0] rgb=0;
reg ready=0;
wire pr,valid,block_last,grant,drop,writing,latest_valid,locked;
wire [255:0] data;
wire [31:0] strb;
wire [1:0] ws,ls,rs;
wire [31:0] lid,rid;
rgb888_block_packer pack(clk,rst,pv,pr,rgb,last,1'b0,valid,ready,data,strb,block_last);
ddr_frame_slots slots(clk,rst,start,done,1'b0,acquire,release_frame,grant,drop,writing,ws,
 latest_valid,ls,lid,locked,rs,rid);
reg [31:0] memory[0:3*PIXELS-1];
integer cycle=0,stored=0,delay_done=0,j,k,frame,test_passed=0;
reg saw_last=0;
always #5 clk=~clk;
always @(negedge clk)begin
 cycle=cycle+1;
 ready=rst && cycle%7!=0 && cycle%7!=1 && cycle%7!=2;
end
always @(posedge clk)if(rst)begin
 done<=0;
 if(valid && ready)begin
  if(!writing)$fatal(1,"storage without writer ownership");
  for(j=0;j<8;j=j+1)if(strb[j*4+:4]==4'hf)begin
   if(stored>=PIXELS)$fatal(1,"extra stored pixel");
   memory[ws*PIXELS+stored]=data[j*32+:32];stored=stored+1;
  end
  if(block_last)begin saw_last=1;delay_done=9;end
 end
 if(delay_done>0)begin
  delay_done=delay_done-1;
  if(delay_done==0)done<=1;
 end
end
initial begin
 repeat(3)@(negedge clk);#1;rst=1;
 for(frame=1;frame<=3;frame=frame+1)begin
  stored=0;saw_last=0;
  @(negedge clk);#1;start=1;@(negedge clk);#1;start=0;
  if(!grant)$fatal(1,"missing grant");
  for(k=0;k<PIXELS;k=k+1)begin
   @(negedge clk);#1;pv=1;rgb=frame*24'h200000+k;last=(k==PIXELS-1);
   // Keep the same pixel stable until accepted.
   @(posedge clk);
   while(!pr)@(posedge clk);
   @(negedge clk);#1;pv=0;last=0;
  end
  wait(!writing);@(negedge clk);#1;
  if(!saw_last || stored!=PIXELS || lid!=frame)$fatal(1,"frame publication before write drain");
  for(k=0;k<PIXELS;k=k+1)
   if(memory[ls*PIXELS+k]!==32'h00200000*frame+k)$fatal(1,"frame readback index=%0d",k);
  if(frame==1)begin
   acquire=1;@(negedge clk);#1;acquire=0;
  end else begin
   if(!locked || rid!=1 || rs==ls)$fatal(1,"read lock lost");
   for(k=0;k<PIXELS;k=k+1)
    if(memory[rs*PIXELS+k]!==32'h00200000+k)$fatal(1,"locked frame overwritten");
  end
 end
 test_passed=1;$display("PASS_DDR_FRAME_MODEL frames=3 pixels_per_frame=%0d stalls=3/7",PIXELS);$finish;
end
initial begin #200000000;$fatal(1,"frame model timeout");end
endmodule
