`timescale 1ns/1ps
module tb_lens_map #(parameter DISABLE_TERM=0,COMPOSED=0);
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg frame_start=0,profile_valid=1,req_valid=0,rsp_ready=0;
 reg[511:0]profile_params;reg[12:0]width,height;reg[31:0]profile_version,profile_hframe;
 reg signed[63:0]ideal_u,ideal_v;reg[31:0]req_tag,req_hframe;
 wire req_ready,rsp_valid,rsp_inside,rsp_invalid;
 wire signed[63:0]source_x,source_y;wire[31:0]rsp_tag,rsp_version,rsp_hframe;
 reg[575:0]profile_h;reg[11:0]dst_u,dst_v;
 generate if(COMPOSED)begin: composed
 lens_composed_map dut(.*);
 end else begin: brown_only
 lens_map dut(.*);
 end endgenerate
 wire pv;wire[23:0]pixel_rgb;wire[31:0]pixel_tag;
 reg[23:0]p00,p10,p01,p11;integer xx,yy,xx1,yy1;
 function[23:0]pattern(input integer x,y);
 reg[7:0]r,g,b;begin r=(x*3+y*7)%256;g=(x*11+y*5)%256;b=(x*17+y*13)%256;pattern={r,g,b};end endfunction
 always @*begin
 xx=source_x>>>30;yy=source_y>>>30;xx1=xx+1>=1920?1919:xx+1;yy1=yy+1>=1080?1079:yy+1;
 p00=0;p10=0;p01=0;p11=0;
 if(rsp_inside&&!rsp_invalid)begin p00=pattern(xx,yy);p10=pattern(xx1,yy);p01=pattern(xx,yy1);p11=pattern(xx1,yy1);end
 end
 bilinear_interp #(.TAG_W(32)) sample(.clk(clk),.rst_n(rst_n),.in_valid(rsp_valid&&rsp_ready),.in_inside(rsp_inside&&!rsp_invalid),
 .p00(p00),.p10(p10),.p01(p01),.p11(p11),.fx(source_x[29:22]),.fy(source_y[29:22]),.in_tag(rsp_tag),.out_valid(pv),.rgb(pixel_rgb),.out_tag(pixel_tag));
 reg[23:0]expected_pixels[0:1023];
 reg[923:0]vectors[0:1023];integer count=0,max_latency=0;
 reg[1523:0]composed_vectors[0:1023];
 task load(input integer i);begin
 profile_params=vectors[i][412+:512];width=vectors[i][386+:13];height=vectors[i][399+:13];
 if(DISABLE_TERM>=1&&DISABLE_TERM<=4)profile_params[(DISABLE_TERM+3)*64+:64]=0;
 profile_version=vectors[i][322+:32];profile_hframe=vectors[i][354+:32];
 ideal_u=vectors[i][130+:64];ideal_v=vectors[i][194+:64];
 req_tag=vectors[i][258+:32];req_hframe=vectors[i][290+:32];
 profile_h=composed_vectors[i][924+:576];dst_u=composed_vectors[i][1500+:12];dst_v=composed_vectors[i][1512+:12];end endtask
 initial begin
 $readmemh("D:/FPGA/output/lens_vectors_20261017/vectors.hex",vectors);
 $readmemh("D:/FPGA/output/lens_vectors_20261017/composed_vectors.hex",composed_vectors);
 $readmemh("D:/FPGA/output/lens_vectors_20261017/expected_pixels.hex",expected_pixels);
 repeat(3)@(negedge clk);rst_n=1;
 for(integer i=0;i<1024;i++)begin: check_vector
 integer latency;reg[227:0]held;
 @(negedge clk);load(i);frame_start=1;req_valid=1;
 #1;if(req_ready)$fatal(1,"request accepted on boundary");
 @(negedge clk);frame_start=0;#1;
 while(!req_ready)@(negedge clk);
 @(negedge clk);req_valid=0;
 // New profile/H can commit while old request executes; old request must hold its snapshot.
 load((i+1)%1024);frame_start=1;@(negedge clk);frame_start=0;
 latency=0;while(!rsp_valid)begin @(negedge clk);latency++;if(latency>1100)$fatal(1,"lens map timeout vector%0d",i);end
 if(latency>max_latency)max_latency=latency;
 if(rsp_tag!==vectors[i][258+:32]||rsp_version!==vectors[i][322+:32]||rsp_hframe!==vectors[i][354+:32])$fatal(1,"mixed request/profile identity");
 if(rsp_invalid!==vectors[i][129]||rsp_inside!==vectors[i][128]||source_x!==vectors[i][0+:64]||source_y!==vectors[i][64+:64])
 $fatal(1,"Brown vector%0d got xy=%0d,%0d flags%b%b expected%0d,%0d flags%b%b",i,source_x,source_y,rsp_invalid,rsp_inside,$signed(vectors[i][0+:64]),$signed(vectors[i][64+:64]),vectors[i][129],vectors[i][128]);
 held={source_x,source_y,rsp_tag,rsp_version,rsp_hframe,rsp_invalid,rsp_inside};
 repeat(3)begin @(negedge clk);if(!rsp_valid||held!=={source_x,source_y,rsp_tag,rsp_version,rsp_hframe,rsp_invalid,rsp_inside})$fatal(1,"response unstable under backpressure");end
 rsp_ready=1;@(negedge clk);rsp_ready=0;
 while(!pv)@(negedge clk);
 if(pixel_rgb!==expected_pixels[i]||pixel_tag!==vectors[i][258+:32])$fatal(1,"sample mismatch vector%0d actual=%h expected=%h",i,pixel_rgb,expected_pixels[i]);
 count++;
 end
 if(COMPOSED)begin
 @(negedge clk);load(1);profile_h=0;req_valid=1;
 @(negedge clk);req_valid=0;
 while(!rsp_valid)@(negedge clk);
 if(!rsp_invalid||rsp_inside||source_x!=0||source_y!=0)$fatal(1,"zero H denominator not rejected");
 rsp_ready=1;@(negedge clk);rsp_ready=0;
 end
 @(negedge clk);load(5);req_valid=1;@(negedge clk);req_valid=0;
 repeat(12)@(negedge clk);rst_n=0;@(negedge clk);rst_n=1;
 repeat(1100)begin @(negedge clk);if(rsp_valid)$fatal(1,"old request survived reset");end
 $display("PASS LENS_MAP composed=%0d vectors=%0d pixels=%0d max_cycles=%0d independent coefficient cases,signed bounds,numeric reject,profile snapshot,backpressure,reset",COMPOSED,count,count,max_latency);$finish;
 end
 initial begin #10000000;$fatal(1,"lens bench timeout");end
endmodule
