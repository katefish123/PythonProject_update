`timescale 1ns/1ps
module tb_affine_lens;
 reg clk=0,rst_n=0,in_valid=0,nearest=0,cross_enable=0;
 always #6.734 clk=~clk;
 reg[239:0]affine;reg[11:0]dst_x=0,dst_y=0;
 wire req_valid,req_inside,req_error,out_valid;wire[23:0]req_tag,addr00,addr10,addr01,addr11,out_rgb,out_tag;wire[7:0]req_fx,req_fy;
 wire l_req_valid,l_req_inside,l_req_error,l_out_valid;wire[23:0]l_req_tag,l_addr00,l_addr10,l_addr01,l_addr11,l_out_rgb,l_out_tag;wire[7:0]l_req_fx,l_req_fy;
 reg rsp_valid=0,rsp_inside=0,l_rsp_valid=0,l_rsp_inside=0;
 reg[23:0]rsp_tag=0,p00=0,p10=0,p01=0,p11=0,l_rsp_tag=0,l_p00=0,l_p10=0,l_p01=0,l_p11=0;
 reg[7:0]rsp_fx=0,rsp_fy=0,l_rsp_fx=0,l_rsp_fy=0;
 lens_affine_instance dut(.*);
 lens_autocrop_instance legacy(.clk(clk),.rst_n(rst_n),.in_valid(in_valid&&cross_enable),.nearest(nearest),.dst_x(dst_x),.dst_y(dst_y),
 .req_valid(l_req_valid),.req_inside(l_req_inside),.req_error(l_req_error),.req_tag(l_req_tag),
 .addr00(l_addr00),.addr10(l_addr10),.addr01(l_addr01),.addr11(l_addr11),.req_fx(l_req_fx),.req_fy(l_req_fy),
 .rsp_valid(l_rsp_valid),.rsp_inside(l_rsp_inside),.rsp_tag(l_rsp_tag),.p00(l_p00),.p10(l_p10),.p01(l_p01),.p11(l_p11),.rsp_fx(l_rsp_fx),.rsp_fy(l_rsp_fy),
 .out_valid(l_out_valid),.out_rgb(l_out_rgb),.out_tag(l_out_tag));
 reg[23:0]tags[0:7967],expected_rgb[0:7967];reg[137:0]expected_request[0:7967];reg[239:0]matrices[0:41];
 integer request_queue[$],output_queue[$],legacy_request_queue[$],legacy_output_queue[$];
 integer drive_index=0,sent=0,requests=0,outputs=0,legacy_requests=0,legacy_outputs=0,cancel_req=0,cancel_out=0;
 integer accepted=0,rejected=0,numerical_errors=0,bubbles=0,resets=0;reg[31:0]rng=32'h5e97ad34;
 function[23:0]pixel(input[23:0]a);reg[7:0]r,g,b;begin
  r=a*13+(a>>8)+17;g=a*7+(a>>3)+43;b=a*3+(a>>11)+97;pixel={r,g,b};end endfunction
 integer index,ignored;
 always @(posedge clk)begin
  if(!rst_n)begin
   cancel_req=cancel_req+request_queue.size();cancel_out=cancel_out+output_queue.size();
   request_queue.delete();output_queue.delete();legacy_request_queue.delete();legacy_output_queue.delete();
   rsp_valid<=0;rsp_inside<=0;l_rsp_valid<=0;l_rsp_inside<=0;
  end else begin
   if(in_valid)begin request_queue.push_back(drive_index);sent=sent+1;if(cross_enable)legacy_request_queue.push_back(drive_index);end
   else bubbles=bubbles+1;
   if(req_valid)begin
    if(request_queue.size()==0)$fatal(1,"AFFINE_UNEXPECTED_REQUEST");index=request_queue.pop_front();
    if({req_error,req_inside,req_tag,addr00,addr10,addr01,addr11,req_fx,req_fy}!==expected_request[index])
     $fatal(1,"AFFINE_REQUEST_MISMATCH index=%0d actual=%h expected=%h",index,{req_error,req_inside,req_tag,addr00,addr10,addr01,addr11,req_fx,req_fy},expected_request[index]);
    requests=requests+1;output_queue.push_back(index);
    if(req_inside)accepted=accepted+1;else rejected=rejected+1;
    if(req_error)numerical_errors=numerical_errors+1;
   end
   if(out_valid)begin
    if(output_queue.size()==0)$fatal(1,"AFFINE_UNEXPECTED_RGB");index=output_queue.pop_front();
    if(out_tag!==tags[index]||out_rgb!==expected_rgb[index])$fatal(1,"AFFINE_RGB_MISMATCH index=%0d tag=%h rgb=%h expectedtag=%h expectedrgb=%h",index,out_tag,out_rgb,tags[index],expected_rgb[index]);
    outputs=outputs+1;
   end
   if(l_req_valid)begin
    if(legacy_request_queue.size()==0)$fatal(1,"LEGACY_UNEXPECTED_REQUEST");index=legacy_request_queue.pop_front();
    if({l_req_error,l_req_inside,l_req_tag,l_addr00,l_addr10,l_addr01,l_addr11,l_req_fx,l_req_fy}!==expected_request[index])$fatal(1,"LEGACY_REQUEST_MISMATCH index=%0d",index);
    legacy_requests=legacy_requests+1;legacy_output_queue.push_back(index);
   end
   if(l_out_valid)begin
    if(legacy_output_queue.size()==0)$fatal(1,"LEGACY_UNEXPECTED_RGB");index=legacy_output_queue.pop_front();
    if(l_out_tag!==tags[index]||l_out_rgb!==expected_rgb[index])$fatal(1,"LEGACY_RGB_MISMATCH index=%0d",index);
    legacy_outputs=legacy_outputs+1;
   end
   rsp_valid<=req_valid;rsp_inside<=req_inside;rsp_tag<=req_tag;rsp_fx<=req_fx;rsp_fy<=req_fy;
   p00<=pixel(addr00);p10<=pixel(addr10);p01<=pixel(addr01);p11<=pixel(addr11);
   l_rsp_valid<=l_req_valid;l_rsp_inside<=l_req_inside;l_rsp_tag<=l_req_tag;l_rsp_fx<=l_req_fx;l_rsp_fy<=l_req_fy;
   l_p00<=pixel(l_addr00);l_p10<=pixel(l_addr10);l_p01<=pixel(l_addr01);l_p11<=pixel(l_addr11);
  end
 end
 task reset;begin
  @(negedge clk);in_valid=0;rst_n=0;cross_enable=0;repeat(3)@(negedge clk);rst_n=1;resets=resets+1;
  repeat(80)begin @(negedge clk);if(req_valid||out_valid||l_req_valid||l_out_valid)$fatal(1,"AFFINE_RESET_LEAK");end
 end endtask
 task send(input integer n);begin
  @(negedge clk);drive_index=n;dst_x=tags[n][11:0];dst_y=tags[n][23:12];in_valid=1;
 end endtask
 task drain;begin
  @(negedge clk);in_valid=0;repeat(100)@(negedge clk);
  if(request_queue.size()||output_queue.size()||legacy_request_queue.size()||legacy_output_queue.size())$fatal(1,"AFFINE_MISSING_TRANSACTION");
 end endtask
 task run_frame(input integer c,start,count,mode,legacy_mode);begin
  affine=matrices[c];nearest=mode;cross_enable=legacy_mode;
  for(integer n=start;n<start+count;n=n+1)begin
   rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
   if(rng[1:0]==0)begin @(negedge clk);in_valid=0;dst_x=rng[11:0];dst_y=rng[23:12];repeat(rng[3:2])@(negedge clk);end
   send(n);
  end
  drain();$display("AFFINE_FRAME_PASS case=%0d requests=%0d mode=%0d legacy=%0d",c,count,mode,legacy_mode);
 end endtask
 initial begin
  $readmemh("input_tags.hex",tags);$readmemh("expected_requests.hex",expected_request);$readmemh("expected_rgb.hex",expected_rgb);
   matrices[0]=240'h00060000000000fe56d600000000000008b988e600000000000000fe56d6;
  matrices[1]=240'h00060000000000fe56d600000000000008b988e600000000000000fe56d6;
  matrices[2]=240'h000000000000010000000000000000000000000000000000000001000000;
  matrices[3]=240'h000000000000010000000000000000000000000000000000000001000000;
  matrices[4]=240'h010ab84abe0000f746eaffffbdbe09ff950fb10500004241f70000f746ea;
  matrices[5]=240'h010ab84abe0000f746eaffffbdbe09ff950fb10500004241f70000f746ea;
  matrices[6]=240'h03447c1f010000b504f3ffff4afb0dff9b8c03ef0000b504f30000b504f3;
  matrices[7]=240'h03447c1f010000b504f3ffff4afb0dff9b8c03ef0000b504f30000b504f3;
  matrices[8]=240'h05db0000000000000000ffff00000001a400000000010000000000000000;
  matrices[9]=240'h05db0000000000000000ffff00000001a400000000010000000000000000;
  matrices[10]=240'h0437000000ffff0000000000000000077f0000000000000000ffff000000;
  matrices[11]=240'h0437000000ffff0000000000000000077f0000000000000000ffff000000;
  matrices[12]=240'hfe5c0000000000000000000100000005db000000ffff0000000000000000;
  matrices[13]=240'hfe5c0000000000000000000100000005db000000ffff0000000000000000;
  matrices[14]=240'hfff800000000010000000000000000fff000000000000000000001000000;
  matrices[15]=240'hfff800000000010000000000000000fff000000000000000000001000000;
  matrices[16]=240'h80000000007fffffffff80000000007fffffffff80000000007fffffffff;
  matrices[17]=240'h80000000007fffffffff80000000007fffffffff80000000007fffffffff;
  matrices[18]=240'h01f400000000000000000000000000ffffffffff00000000000000000000;
  matrices[19]=240'h01f400000000000000000000000000ffffffffff00000000000000000000;
  matrices[20]=240'h01f4000000000000000000000000000fffffffff00000000000000000000;
  matrices[21]=240'h01f4000000000000000000000000000fffffffff00000000000000000000;
  matrices[22]=240'h01f400000000000000000000000000100000000000000000000000000000;
  matrices[23]=240'h01f400000000000000000000000000100000000000000000000000000000;
  matrices[24]=240'h0fff000000000000000000000000000fa000000000000000000000000000;
  matrices[25]=240'h0fff000000000000000000000000000fa000000000000000000000000000;
  matrices[26]=240'h01f641000000000000000000000000000428000000000000000000000000;
  matrices[27]=240'h01f641000000000000000000000000000428000000000000000000000000;
  matrices[28]=240'h01f641000000000000000000000000000427000000000000000000000000;
  matrices[29]=240'h01f641000000000000000000000000000427000000000000000000000000;
  matrices[30]=240'h01f6410000000000000000000000000003a8000000000000000000000000;
  matrices[31]=240'h01f6410000000000000000000000000003a8000000000000000000000000;
  matrices[32]=240'h01f6590000000000000000000000000788d2000000000000000000000000;
  matrices[33]=240'h01f6590000000000000000000000000788d2000000000000000000000000;
  matrices[34]=240'h01f659000000000000000000000000078956000000000000000000000000;
  matrices[35]=240'h01f659000000000000000000000000078956000000000000000000000000;
  matrices[36]=240'h0003c800000000000000000000000001f733000000000000000000000000;
  matrices[37]=240'h0003c800000000000000000000000001f733000000000000000000000000;
  matrices[38]=240'h04389600000000000000000000000001f4e0000000000000000000000000;
  matrices[39]=240'h04389600000000000000000000000001f4e0000000000000000000000000;
  matrices[40]=240'h04391600000000000000000000000001f4e0000000000000000000000000;
  matrices[41]=240'h04391600000000000000000000000001f4e0000000000000000000000000;
  affine=240'h00060000000000fe56d600000000000008b988e600000000000000fe56d6;reset();for(integer n=0;n<8;n=n+1)send(n);reset();
  for(integer n=8;n<32;n=n+1)send(n);reset();
   run_frame(0,32,320,0,1);
  run_frame(1,352,320,1,1);
  run_frame(2,672,448,0,0);
  run_frame(3,1120,448,1,0);
  run_frame(4,1568,448,0,0);
  run_frame(5,2016,448,1,0);
  run_frame(6,2464,448,0,0);
  run_frame(7,2912,448,1,0);
  run_frame(8,3360,448,0,0);
  run_frame(9,3808,448,1,0);
  run_frame(10,4256,448,0,0);
  run_frame(11,4704,448,1,0);
  run_frame(12,5152,448,0,0);
  run_frame(13,5600,448,1,0);
  run_frame(14,6048,448,0,0);
  run_frame(15,6496,448,1,0);
  run_frame(16,6944,128,0,0);
  run_frame(17,7072,128,1,0);
  run_frame(18,7200,32,0,0);
  run_frame(19,7232,32,1,0);
  run_frame(20,7264,32,0,0);
  run_frame(21,7296,32,1,0);
  run_frame(22,7328,32,0,0);
  run_frame(23,7360,32,1,0);
  run_frame(24,7392,32,0,0);
  run_frame(25,7424,32,1,0);
  run_frame(26,7456,32,0,0);
  run_frame(27,7488,32,1,0);
  run_frame(28,7520,32,0,0);
  run_frame(29,7552,32,1,0);
  run_frame(30,7584,32,0,0);
  run_frame(31,7616,32,1,0);
  run_frame(32,7648,32,0,0);
  run_frame(33,7680,32,1,0);
  run_frame(34,7712,32,0,0);
  run_frame(35,7744,32,1,0);
  run_frame(36,7776,32,0,0);
  run_frame(37,7808,32,1,0);
  run_frame(38,7840,32,0,0);
  run_frame(39,7872,32,1,0);
  run_frame(40,7904,32,0,0);
  run_frame(41,7936,32,1,0);
  if(sent!=7968||requests+cancel_req!=sent||outputs+cancel_out!=requests||requests<3000||outputs<3000||accepted<1000||rejected<100||numerical_errors<20||cancel_req<8||cancel_out<1||legacy_requests<500||legacy_requests!=legacy_outputs||bubbles<100)
   $fatal(1,"AFFINE_COVERAGE sent=%0d req=%0d out=%0d cancelled=%0d/%0d inside=%0d outside=%0d numerical=%0d legacy=%0d bubbles=%0d",sent,requests,outputs,cancel_req,cancel_out,accepted,rejected,numerical_errors,legacy_requests,bubbles);
  $display("AFFINE_LENS_PASS sent=%0d requests=%0d rgb=%0d inside=%0d outside=%0d numerical_errors=%0d reset_cancelled_requests=%0d reset_cancelled_rgb=%0d legacy_requests=%0d legacy_rgb=%0d bubbles=%0d resets=%0d",sent,requests,outputs,accepted,rejected,numerical_errors,cancel_req,cancel_out,legacy_requests,legacy_outputs,bubbles,resets);$finish;
 end
 initial begin #2000000;$fatal(1,"AFFINE_TIMEOUT");end
endmodule
