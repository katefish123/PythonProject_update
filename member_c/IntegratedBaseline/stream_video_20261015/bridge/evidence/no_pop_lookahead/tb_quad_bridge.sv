`timescale 1ns/1ps
module tb_quad_bridge;
localparam N=1600;
integer sent=0,ui_received=0,received=0,ptick=0,utick=0,x,y,ex,ey;integer max_run=0,run_length=0;integer q_stalls=0;
reg proc_clk=0,ui_clk=0,rst_n=0;always #5 proc_clk=~proc_clk;always #3 ui_clk=~ui_clk;
reg q_valid=0,q_inside=0,q_nearest=0;wire q_ready;reg[23:0]q_addr00,q_addr10,q_addr01,q_addr11,q_tag;reg[7:0]q_fx,q_fy;reg[31:0]q_generation;reg[27:0]q_base;
wire req_valid,req_inside,req_nearest;wire[27:0]req_base;wire[31:0]req_generation;wire[11:0]req_x,req_y;wire[23:0]req_tag;wire[7:0]req_fx,req_fy;
wire req_ready,rsp_valid,rsp_ready;wire rsp_inside=req_inside;wire[23:0]rsp_p00=ui_received,rsp_p10=ui_received+1,rsp_p01=ui_received+2,rsp_p11=ui_received+3,rsp_tag=req_tag;wire[7:0]rsp_fx=req_fx,rsp_fy=req_fy;wire[31:0]rsp_generation=req_generation;
wire r_valid,r_inside;reg r_ready=0;wire[23:0]r_p00,r_p10,r_p01,r_p11,r_tag;wire[7:0]r_fx,r_fy;wire[31:0]r_generation;wire fault;
quad_packet_bridge #(.SRC_W(32),.SRC_H(16),.OUT_W(32),.OUT_H(16),.FIFO_ADDR_BITS(4)) dut(.*);

reg[31:0]prng=32'hdeadbeef;reg[31:0]urng=32'h98761234;
wire allow_ui=utick>80&&(utick>500||urng[1:0]!=0);
assign req_ready=allow_ui&&rsp_ready;
assign rsp_valid=req_valid&&allow_ui;
function expected_inside;input integer i;begin expected_inside=(i%7!=0)&&(i<N-2);end endfunction
function[23:0]expected_tag;input integer i;begin expected_tag=(i==N-1)?24'd32:((i/32)%16)*4096+i%32;end endfunction
always @(negedge proc_clk)begin
 if(rst_n)begin
 q_valid=sent<N;q_nearest=sent%2;q_inside=sent%7!=0;q_generation=sent/128+1;q_base=28'h10000+(sent/64)*4096;
 x=sent%32;y=(sent/32)%16;ex=(x<31&&!q_nearest)?x+1:x;ey=(y<15&&!q_nearest)?y+1:y;
 q_addr00=y*32+x;q_addr10=y*32+ex;q_addr01=ey*32+x;q_addr11=ey*32+ex;
 if(!q_inside)begin q_addr00=24'hffffff;q_addr10=24'hfffffe;q_addr01=24'hfffffd;q_addr11=24'hfffffc;end
 if(sent==N-2)q_addr10=0;
 q_tag=expected_tag(sent);q_fx=sent%256;q_fy=(sent+1)%256;
 r_ready=ptick>180&&(ptick>600||prng[2:0]>2);
 end else begin q_valid=0;r_ready=0;end
end
always @(posedge proc_clk)if(rst_n)begin
 if(sent<N-2&&fault)$fatal(1,"unexpected sticky fault before invalid packet");
 ptick<=ptick+1;prng<={prng[30:0],prng[31]^prng[21]^prng[1]^prng[0]};
 if(q_valid&&q_ready)sent<=sent+1;
 if(q_valid&&!q_ready)q_stalls<=q_stalls+1;
 if(r_valid&&r_ready)begin
 if({r_p00,r_p10,r_p01,r_p11}!={24'(received),24'(received+1),24'(received+2),24'(received+3)})$fatal(1,"response pixels/order %0d",received);
 if(r_generation!==received/128+1||r_tag!==expected_tag(received)||r_inside!==expected_inside(received)||r_fx!==8'(received%256)||r_fy!==8'((received+1)%256))$fatal(1,"response metadata %0d",received);
 received<=received+1;run_length<=run_length+1;if(run_length+1>max_run)max_run<=run_length+1;
 end else run_length<=0;
end
always @(posedge ui_clk)if(rst_n)begin
 utick<=utick+1;urng<={urng[30:0],urng[31]^urng[21]^urng[1]^urng[0]};
 if(req_valid&&req_ready)begin
 if(req_base!==28'h10000+(ui_received/64)*4096||req_generation!==ui_received/128+1||req_tag!==expected_tag(ui_received)||req_nearest!==1'(ui_received%2)||req_inside!==expected_inside(ui_received))$fatal(1,"request metadata/base %0d",ui_received);
 if(req_x!==(expected_inside(ui_received)?ui_received%32:0)||req_y!==(expected_inside(ui_received)?(ui_received/32)%16:0)||req_fx!==8'(ui_received%256)||req_fy!==8'((ui_received+1)%256))$fatal(1,"request coordinate/fraction %0d",ui_received);
 ui_received<=ui_received+1;
 end
end
initial begin
 repeat(4)@(negedge proc_clk);rst_n=1;wait(received==N);
 if(!fault||q_stalls==0||max_run<32)$fatal(1,"coverage fault=%0b fullstalls=%0d max_run=%0d",fault,q_stalls,max_run);
 @(negedge proc_clk);rst_n=0;repeat(5)@(negedge proc_clk);
if(fault)$fatal(1,"hard reset did not clear sticky fault");
sent=0;ui_received=0;received=0;ptick=0;utick=0;run_length=0;max_run=0;q_stalls=0;rst_n=1;
wait(received==N);if(!fault||q_stalls==0||max_run<32)$fatal(1,"reset coverage failure");
$display("PASS quad bridge async metadata/base/generation full/stalls faults max_run=%0d",max_run);$finish;
end
initial begin #200000;$fatal(1,"bridge timeout");end
endmodule


