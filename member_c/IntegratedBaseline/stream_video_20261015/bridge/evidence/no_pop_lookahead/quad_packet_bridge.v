`timescale 1ns/1ps
`default_nettype none
module quad_packet_bridge #(
 parameter SRC_W=1920,SRC_H=1080,OUT_W=768,OUT_H=1080,FIFO_ADDR_BITS=9
)(
 input wire proc_clk,ui_clk,rst_n,
 input wire q_valid,output wire q_ready,input wire q_inside,q_nearest,
 input wire[23:0]q_addr00,q_addr10,q_addr01,q_addr11,q_tag,
 input wire[7:0]q_fx,q_fy,input wire[31:0]q_generation,input wire[27:0]q_base,
 output reg fault,
 output wire req_valid,input wire req_ready,
 output wire[27:0]req_base,output wire[31:0]req_generation,
 output wire[11:0]req_x,req_y,output wire req_nearest,req_inside,
 output wire[23:0]req_tag,output wire[7:0]req_fx,req_fy,
 input wire rsp_valid,output wire rsp_ready,input wire rsp_inside,
 input wire[23:0]rsp_p00,rsp_p10,rsp_p01,rsp_p11,rsp_tag,
 input wire[7:0]rsp_fx,rsp_fy,input wire[31:0]rsp_generation,
 output wire r_valid,input wire r_ready,output wire r_inside,
 output wire[23:0]r_p00,r_p10,r_p01,r_p11,r_tag,
 output wire[7:0]r_fx,r_fy,output wire[31:0]r_generation
);
 // Elastic raw and decoded stages split descriptor read, constant-width
 // address division, and packet RAM input into separate clock periods.
 reg raw_valid,packet_valid;reg[197:0]raw_payload;reg[125:0]packet_payload;
 wire packet_ready;
 wire cooked_ready=!packet_valid||packet_ready;
 assign q_ready=rst_n&&(!raw_valid||cooked_ready);
 wire[27:0]h_base;wire[31:0]h_generation;
 wire[23:0]h_addr00,h_addr10,h_addr01,h_addr11,h_tag;
 wire[7:0]h_fx,h_fy;wire h_inside,h_nearest;
 assign {h_base,h_generation,h_addr00,h_addr10,h_addr01,h_addr11,h_tag,h_fx,h_fy,h_inside,h_nearest}=raw_payload;
 wire[23:0]source_x=h_addr00%SRC_W,source_y=h_addr00/SRC_W;
 wire[23:0]next_x=!h_nearest&&source_x<SRC_W-1?source_x+1:source_x;
 wire[23:0]next_y=!h_nearest&&source_y<SRC_H-1?source_y+1:source_y;
 wire bad_tag=h_tag[11:0]>=OUT_W||h_tag[23:12]>=OUT_H;
 wire bad_address=h_inside&&(h_addr00>=SRC_W*SRC_H||
 h_addr10!=source_y*SRC_W+next_x||h_addr01!=next_y*SRC_W+source_x||h_addr11!=next_y*SRC_W+next_x);
 wire inside_checked=h_inside&&!bad_address&&!bad_tag;
 wire[11:0]checked_x=inside_checked?source_x[11:0]:12'd0;
 wire[11:0]checked_y=inside_checked?source_y[11:0]:12'd0;
 always @(posedge proc_clk or negedge rst_n)begin
  if(!rst_n)begin fault<=0;raw_valid<=0;packet_valid<=0;raw_payload<=0;packet_payload<=0;end
  else begin
   if(cooked_ready)begin
    packet_valid<=raw_valid;
    if(raw_valid)begin
     packet_payload<={h_base,h_generation,checked_x,checked_y,h_nearest,inside_checked,h_tag,h_fx,h_fy};
     if(bad_tag||bad_address)fault<=1;
    end
   end
   if(q_ready)begin
    raw_valid<=q_valid;
    if(q_valid)raw_payload<={q_base,q_generation,q_addr00,q_addr10,q_addr01,q_addr11,q_tag,q_fx,q_fy,q_inside,q_nearest};
   end
  end
 end
 async_packet_stream #(.DATA_WIDTH(126),.ADDR_BITS(FIFO_ADDR_BITS)) requests(
 .wr_clk(proc_clk),.rd_clk(ui_clk),.rst_n(rst_n),
 .s_valid(packet_valid),.s_ready(packet_ready),.s_data(packet_payload),
 .m_valid(req_valid),.m_ready(req_ready),.m_data({req_base,req_generation,req_x,req_y,req_nearest,req_inside,req_tag,req_fx,req_fy}));
 async_packet_stream #(.DATA_WIDTH(169),.ADDR_BITS(FIFO_ADDR_BITS)) responses(
 .wr_clk(ui_clk),.rd_clk(proc_clk),.rst_n(rst_n),
 .s_valid(rsp_valid),.s_ready(rsp_ready),.s_data({rsp_generation,rsp_inside,rsp_p00,rsp_p10,rsp_p01,rsp_p11,rsp_tag,rsp_fx,rsp_fy}),
 .m_valid(r_valid),.m_ready(r_ready),.m_data({r_generation,r_inside,r_p00,r_p10,r_p01,r_p11,r_tag,r_fx,r_fy}));
endmodule
`default_nettype wire
