`timescale 1ns/1ps
module tb_quad_bridge_1920;
localparam N=16384;
integer sent=0,ui_received=0,received=0,ptick=0,utick=0,x,y,ex,ey;integer max_run=0,run_length=0;integer q_stalls=0;integer q_run=0,q_max=0,packet_run=0,packet_max=0;
reg proc_clk=0,ui_clk=0,rst_n=0;always #8.754037 proc_clk=~proc_clk;always #3 ui_clk=~ui_clk;
reg q_valid=0,q_inside=0,q_nearest=0;wire q_ready;reg[23:0]q_addr00,q_addr10,q_addr01,q_addr11,q_tag;reg[7:0]q_fx,q_fy;reg[31:0]q_generation;reg[27:0]q_base;
wire req_valid,req_inside,req_nearest;wire[27:0]req_base;wire[31:0]req_generation;wire[11:0]req_x,req_y;wire[23:0]req_tag;wire[7:0]req_fx,req_fy;
wire req_ready,rsp_valid,rsp_ready;wire rsp_inside=req_inside;wire[23:0]rsp_p00=ui_received,rsp_p10=ui_received+1,rsp_p01=ui_received+2,rsp_p11=ui_received+3,rsp_tag=req_tag;wire[7:0]rsp_fx=req_fx,rsp_fy=req_fy;wire[31:0]rsp_generation=req_generation;
wire r_valid,r_inside;reg r_ready=0;wire[23:0]r_p00,r_p10,r_p01,r_p11,r_tag;wire[7:0]r_fx,r_fy;wire[31:0]r_generation;wire fault;
quad_packet_bridge #(.SRC_W(1920),.SRC_H(1080),.OUT_W(768),.OUT_H(1080),.FIFO_ADDR_BITS(5)) dut(.*);

reg[31:0]prng=32'hdeadbeef;reg[31:0]urng=32'h98761234;
wire allow_ui=utick>80&&(utick>500||urng[1:0]!=0);
assign req_ready=allow_ui&&rsp_ready;
assign rsp_valid=req_valid&&allow_ui;
function integer coord_x;input integer i;begin
case(i%5) 0:coord_x=0;1:coord_x=1919;2:coord_x=1918;default:coord_x=(i*73)%1920;endcase
end endfunction
function integer coord_y;input integer i;begin
case(i%5) 0:coord_y=1079;1:coord_y=0;2:coord_y=1078;default:coord_y=(i*131)%1080;endcase
end endfunction
function[31:0]expected_generation;input integer i;begin expected_generation=32'hfffffff0+i/128;end endfunction
function[27:0]expected_base;input integer i;begin expected_base=28'h10000+(i%2)*28'h0800000+(i%16)*4096;end endfunction
function expected_inside;input integer i;begin expected_inside=(i%7!=0)&&(i<N-5);end endfunction
function[23:0]expected_tag;input integer i;begin
expected_tag=(i==N-1)?24'(1080*4096):((i==N-2)?24'd768:(((i/768)%1080)*4096+i%768));
end endfunction
reg req_stalled=0,r_stalled=0;reg[125:0]held_req;reg[168:0]held_r;
always @(posedge ui_clk)if(rst_n)begin
 if(req_stalled&&(!req_valid||{req_base,req_generation,req_x,req_y,req_nearest,req_inside,req_tag,req_fx,req_fy}!==held_req))$fatal(1,"request changed under stall");
 req_stalled<=req_valid&&!req_ready;held_req<={req_base,req_generation,req_x,req_y,req_nearest,req_inside,req_tag,req_fx,req_fy};
end else req_stalled<=0;
always @(posedge proc_clk)if(rst_n)begin
 if(r_stalled&&(!r_valid||{r_generation,r_inside,r_p00,r_p10,r_p01,r_p11,r_tag,r_fx,r_fy}!==held_r))$fatal(1,"response changed under stall");
 r_stalled<=r_valid&&!r_ready;held_r<={r_generation,r_inside,r_p00,r_p10,r_p01,r_p11,r_tag,r_fx,r_fy};
end else r_stalled<=0;
always @(negedge proc_clk)begin
 if(rst_n)begin
 q_valid=sent<N;q_nearest=sent%2;q_inside=sent%7!=0||sent>=N-5;q_generation=expected_generation(sent);q_base=expected_base(sent);
 x=coord_x(sent);y=coord_y(sent);ex=(x<1919&&!q_nearest)?x+1:x;ey=(y<1079&&!q_nearest)?y+1:y;
 q_addr00=y*1920+x;q_addr10=y*1920+ex;q_addr01=ey*1920+x;q_addr11=ey*1920+ex;
 if(!q_inside)begin q_addr00=24'hffffff;q_addr10=24'hfffffe;q_addr01=24'hfffffd;q_addr11=24'hfffffc;end
 if(sent==N-5)q_addr10=q_addr10^1;
 if(sent==N-4)q_addr00=1920*1080;
 if(sent==N-3)q_addr11=q_addr11^1;
 q_tag=expected_tag(sent);q_fx=sent%256;q_fy=(sent+1)%256;
 r_ready=ptick>180&&(ptick>600||prng[2:0]>2);
 end else begin q_valid=0;r_ready=0;end
end
always @(posedge proc_clk)if(rst_n)begin
 if(sent<N-5&&fault)$fatal(1,"unexpected sticky fault before invalid packet");
 ptick<=ptick+1;prng<={prng[30:0],prng[31]^prng[21]^prng[1]^prng[0]};
 if(q_valid&&q_ready)begin sent<=sent+1;q_run<=q_run+1;if(q_run+1>q_max)q_max<=q_run+1;end else q_run<=0;
 if(dut.packet_valid&&dut.packet_ready)begin packet_run<=packet_run+1;if(packet_run+1>packet_max)packet_max<=packet_run+1;end else packet_run<=0;
 if(q_valid&&!q_ready)q_stalls<=q_stalls+1;
 if(r_valid&&r_ready)begin
 if({r_p00,r_p10,r_p01,r_p11}!={24'(received),24'(received+1),24'(received+2),24'(received+3)})$fatal(1,"response pixels/order %0d",received);
 if(r_generation!==expected_generation(received)||r_tag!==expected_tag(received)||r_inside!==expected_inside(received)||r_fx!==8'(received%256)||r_fy!==8'((received+1)%256))$fatal(1,"response metadata %0d",received);
 received<=received+1;run_length<=run_length+1;if(run_length+1>max_run)max_run<=run_length+1;
 end else run_length<=0;
end
always @(posedge ui_clk)if(rst_n)begin
 utick<=utick+1;urng<={urng[30:0],urng[31]^urng[21]^urng[1]^urng[0]};
 if(req_valid&&req_ready)begin
 if(req_base!==expected_base(ui_received)||req_generation!==expected_generation(ui_received)||req_tag!==expected_tag(ui_received)||req_nearest!==1'(ui_received%2)||req_inside!==expected_inside(ui_received))$fatal(1,"request metadata/base %0d",ui_received);
 if(req_x!==(expected_inside(ui_received)?coord_x(ui_received):0)||req_y!==(expected_inside(ui_received)?coord_y(ui_received):0)||req_fx!==8'(ui_received%256)||req_fy!==8'((ui_received+1)%256))$fatal(1,"request coordinate/fraction %0d",ui_received);
 ui_received<=ui_received+1;
 end
end
initial begin
 repeat(4)@(negedge proc_clk);rst_n=1;
 // Flush a live, backpressured request pipeline, not merely an idle bridge.
 wait(sent>=24);@(negedge proc_clk);rst_n=0;repeat(5)@(negedge proc_clk);
 sent=0;ui_received=0;received=0;ptick=0;utick=0;run_length=0;max_run=0;q_stalls=0;q_run=0;q_max=0;packet_run=0;packet_max=0;rst_n=1;
 wait(received==N);
 if(!fault||q_stalls==0||max_run<512||q_max<512||packet_max<512)$fatal(1,"coverage fault=%0b fullstalls=%0d max_run=%0d",fault,q_stalls,max_run);
 @(negedge proc_clk);rst_n=0;repeat(5)@(negedge proc_clk);
if(fault)$fatal(1,"hard reset did not clear sticky fault");
sent=0;ui_received=0;received=0;ptick=0;utick=0;run_length=0;max_run=0;q_stalls=0;q_run=0;q_max=0;packet_run=0;packet_max=0;rst_n=1;
wait(received==N);if(!fault||q_stalls==0||max_run<512||q_max<512||packet_max<512)$fatal(1,"reset coverage failure");
$display("PASS quad bridge1920 32768packets edge/nearest/bypass/invalid/full/stall/base/generation-wrap/reset max_run=%0d q_run=%0d packet_run=%0d",max_run,q_max,packet_max);$finish;
end
initial begin #2000000;$fatal(1,"bridge timeout");end
endmodule


