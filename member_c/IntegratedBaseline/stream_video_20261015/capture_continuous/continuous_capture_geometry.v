`timescale 1ns/1ps
`default_nettype none
module continuous_capture_geometry #(
 parameter SRC_W=1920,SRC_H=1080,MIN_PIXELS=64,MAX_PIXELS=16384,MAX_SPAN=256,FIFO_ADDR_BITS=9,
 parameter BLACK_RMIN=0,BLACK_RMAX=64,BLACK_GMIN=0,BLACK_GMAX=64,BLACK_BMIN=0,BLACK_BMAX=64,
 parameter P0_XMIN=0,P0_XMAX=SRC_W/2-1,P0_YMIN=0,P0_YMAX=SRC_H/2-1,
 parameter P1_XMIN=SRC_W/2,P1_XMAX=SRC_W-1,P1_YMIN=0,P1_YMAX=SRC_H/2-1,
 parameter P2_XMIN=SRC_W/2,P2_XMAX=SRC_W-1,P2_YMIN=SRC_H/2,P2_YMAX=SRC_H-1,
 parameter P3_XMIN=0,P3_XMAX=SRC_W/2-1,P3_YMIN=SRC_H/2,P3_YMAX=SRC_H-1
)(

 input wire rx_clk,proc_clk,rst_n,
 input wire sample_valid,sample_first,sample_bank,input wire[31:0]sample_generation,
 input wire[11:0]sample_x,sample_y,input wire[23:0]sample_rgb,
 input wire close_valid,close_bank,close_ok,input wire[31:0]close_generation,
 output reg metadata_valid,input wire metadata_ready,output reg[129:0]metadata_data,
 output reg fault
);
 reg tap_sample_valid;
 reg tap_sample_first;
 reg tap_sample_bank;
 reg[31:0] tap_sample_generation;
 reg[11:0] tap_sample_x;
 reg[11:0] tap_sample_y;
 reg[23:0] tap_sample_rgb;
 reg tap_close_valid;
 reg tap_close_bank;
 reg tap_close_ok;
 reg[31:0] tap_close_generation;
 always @(posedge rx_clk or negedge rst_n)begin
 if(!rst_n)begin
 tap_sample_valid<=0;
 tap_sample_first<=0;
 tap_sample_bank<=0;
 tap_sample_generation<=0;
 tap_sample_x<=0;
 tap_sample_y<=0;
 tap_sample_rgb<=0;
 tap_close_valid<=0;
 tap_close_bank<=0;
 tap_close_ok<=0;
 tap_close_generation<=0;
 end else begin
 tap_sample_valid<=sample_valid;
 tap_sample_first<=sample_first;
 tap_sample_bank<=sample_bank;
 tap_sample_generation<=sample_generation;
 tap_sample_x<=sample_x;
 tap_sample_y<=sample_y;
 tap_sample_rgb<=sample_rgb;
 tap_close_valid<=close_valid;
 tap_close_bank<=close_bank;
 tap_close_ok<=close_ok;
 tap_close_generation<=close_generation;
 end end
 wire black=tap_sample_rgb[23:16]>=BLACK_RMIN&&tap_sample_rgb[23:16]<=BLACK_RMAX&&tap_sample_rgb[15:8]>=BLACK_GMIN&&tap_sample_rgb[15:8]<=BLACK_GMAX&&tap_sample_rgb[7:0]>=BLACK_BMIN&&tap_sample_rgb[7:0]<=BLACK_BMAX;
 wire roi=(tap_sample_x>=P0_XMIN&&tap_sample_x<=P0_XMAX&&tap_sample_y>=P0_YMIN&&tap_sample_y<=P0_YMAX)||
 (tap_sample_x>=P1_XMIN&&tap_sample_x<=P1_XMAX&&tap_sample_y>=P1_YMIN&&tap_sample_y<=P1_YMAX)||
 (tap_sample_x>=P2_XMIN&&tap_sample_x<=P2_XMAX&&tap_sample_y>=P2_YMIN&&tap_sample_y<=P2_YMAX)||
 (tap_sample_x>=P3_XMIN&&tap_sample_x<=P3_XMAX&&tap_sample_y>=P3_YMIN&&tap_sample_y<=P3_YMAX);
 wire contribution=black&&roi;
 reg start_sent,overflow;
 reg[84:0]ends[0:1];reg eh,et;reg[1:0]ec;
 wire live=tap_sample_valid&&(tap_sample_first||contribution);
 wire event_s_ready,event_valid,event_ready;wire[84:0]event_data;
 wire send_end=ec!=0;
 wire source_valid=send_end||live;
 wire[84:0]live_data={contribution,overflow,tap_sample_first||!start_sent,1'b0,tap_sample_bank,tap_sample_generation,tap_sample_x,tap_sample_y,tap_sample_rgb};
 wire[84:0]source_data=send_end?ends[eh]:live_data;
 wire end_pop=send_end&&event_s_ready;
 async_packet_stream #(.DATA_WIDTH(85),.ADDR_BITS(FIFO_ADDR_BITS)) events(
 .wr_clk(rx_clk),.rd_clk(proc_clk),.rst_n(rst_n),.s_valid(source_valid),.s_ready(event_s_ready),.s_data(source_data),
 .m_valid(event_valid),.m_ready(event_ready),.m_data(event_data));
 always @(posedge rx_clk or negedge rst_n)begin
 if(!rst_n)begin start_sent<=0;overflow<=0;eh<=0;et<=0;ec<=0;end
 else begin
 case({tap_close_valid,end_pop})2'b10:ec<=ec+1'b1;2'b01:ec<=ec-1'b1;default:begin end endcase
 if(tap_close_valid)begin
 ends[et]<={1'b0,!tap_close_ok||overflow,!start_sent,1'b1,tap_close_bank,tap_close_generation,48'd0};et<=~et;
 end
 if(end_pop)eh<=~eh;
 if(tap_sample_first)begin start_sent<=0;overflow<=0;end
 if(live)begin
 if(!send_end&&event_s_ready)start_sent<=1;
 else overflow<=1;
 end
 end end
 reg waiting,frame_bad,held_bank;reg[31:0]held_generation;
 wire take=event_valid&&event_ready;
 assign event_ready=!waiting&&(!metadata_valid||metadata_ready);
 wire valid,reject_frame,dropped,busy;wire[11:0]x0,y0,x1,y1,x2,y2,x3,y3;
 marker_detector #(.SRC_W(SRC_W),.SRC_H(SRC_H),.MIN_PIXELS(MIN_PIXELS),.MAX_PIXELS(MAX_PIXELS),.MAX_SPAN(MAX_SPAN),.BLACK_RMIN(BLACK_RMIN),.BLACK_RMAX(BLACK_RMAX),.BLACK_GMIN(BLACK_GMIN),.BLACK_GMAX(BLACK_GMAX),.BLACK_BMIN(BLACK_BMIN),.BLACK_BMAX(BLACK_BMAX),.P0_XMIN(P0_XMIN),.P0_XMAX(P0_XMAX),.P0_YMIN(P0_YMIN),.P0_YMAX(P0_YMAX),.P1_XMIN(P1_XMIN),.P1_XMAX(P1_XMAX),.P1_YMIN(P1_YMIN),.P1_YMAX(P1_YMAX),.P2_XMIN(P2_XMIN),.P2_XMAX(P2_XMAX),.P2_YMIN(P2_YMIN),.P2_YMAX(P2_YMAX),.P3_XMIN(P3_XMIN),.P3_XMAX(P3_XMAX),.P3_YMIN(P3_YMIN),.P3_YMAX(P3_YMAX)) detector(
 .clk(proc_clk),.rst_n(rst_n),.pixel_valid(take&&event_data[84]),.frame_start(take&&event_data[82]),.frame_end(take&&event_data[81]),
 .pixel_x(event_data[47:36]),.pixel_y(event_data[35:24]),.rgb(event_data[23:0]),
 .corners_valid(valid),.frame_reject(reject_frame),.frame_dropped(dropped),.busy(busy),
 .x0(x0),.y0(y0),.x1(x1),.y1(y1),.x2(x2),.y2(y2),.x3(x3),.y3(y3));
 always @(posedge proc_clk or negedge rst_n)begin
 if(!rst_n)begin waiting<=0;frame_bad<=0;held_bank<=0;held_generation<=0;metadata_valid<=0;metadata_data<=0;fault<=0;end
 else begin
 if(metadata_valid&&metadata_ready)metadata_valid<=0;
 if(take)begin
 if(event_data[82])begin held_bank<=event_data[80];held_generation<=event_data[79:48];frame_bad<=event_data[83];end
 else if(event_data[83]||held_bank!=event_data[80]||held_generation!=event_data[79:48])frame_bad<=1;
 if(event_data[81])waiting<=1;
 end
 if(waiting&&(valid||reject_frame||dropped))begin
 metadata_valid<=1;metadata_data<={held_bank,held_generation,valid&&!reject_frame&&!dropped&&!frame_bad,valid?{x0,y0,x1,y1,x2,y2,x3,y3}:96'd0};waiting<=0;
 end
 end end
 // synthesis translate_off
 always @(posedge rx_clk)if(rst_n&&(ec>2||(tap_close_valid&&ec==2&&!end_pop)))$fatal(1,"geometry terminal ownership queue overflow");
 // synthesis translate_on
endmodule
`default_nettype wire
