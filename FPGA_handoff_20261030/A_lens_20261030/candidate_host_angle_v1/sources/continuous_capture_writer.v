`timescale 1ns/1ps
`default_nettype none
module continuous_capture_writer #(
 parameter SRC_W=1920,SRC_H=1080,BURST_BEATS=8,
 parameter[27:0]SOURCE_BASE0=28'd0,SOURCE_BASE1=28'h0800000
)(
 input wire clk,rst_n,
 input wire packet_valid,output wire packet_ready,input wire[319:0]packet_data,
 output wire cmd_valid,input wire cmd_ready,output wire cmd_write,
 output wire[27:0]cmd_addr,output wire[255:0]cmd_wdata,output wire[31:0]cmd_wstrb,output wire[BURST_BEATS*256-1:0]cmd_burst_data,
 input wire rsp_valid,rsp_write,
 output wire terminal_valid,input wire terminal_ready,output wire[37:0]terminal_data,
 output reg fault
);
 localparam IDLE=0,COLLECT=1,REPORT=4;
 reg[2:0]state;reg bank,frame_bad,terminal_ok;reg[31:0]generation;
 reg[3:0]reason;reg[31:0]seen,written;reg[3:0]fill;
 reg[27:0]base;
 // A full slot remains owned until its ACK, including command backpressure.
 // The other slot can collect; there is still exactly one native in flight.
 reg[BURST_BEATS*256-1:0]assembly0,assembly1;
 reg[27:0]address0,address1;
 reg[1:0]occupied;
 reg fill_slot,issue_slot,inflight;
 reg input_valid;reg[319:0]input_packet;
 wire[1:0]kind=input_packet[319:318];wire pb=input_packet[317];wire[31:0]pg=input_packet[316:285];wire[23:0]pa=input_packet[284:261];wire pok=input_packet[260];wire[3:0]pr=input_packet[259:256];
 wire drained=occupied==0&&!inflight;
 wire collect_space=frame_bad||!occupied[fill_slot];
 // END stays in the existing one-record elastic slot until all owned writes
 // retire. A partial final block is then rejected by the unchanged checks.
 wire consume=input_valid&&(state==IDLE||(state==COLLECT&&
  (kind==2?drained:kind==1?collect_space:1'b1)));
 assign packet_ready=rst_n&&(!input_valid||consume);
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin input_valid<=0;input_packet<=0;end
 else if(packet_ready)begin input_valid<=packet_valid;input_packet<=packet_data;end
 end
 assign cmd_valid=rst_n&&state==COLLECT&&occupied[issue_slot]&&!inflight;
 assign cmd_write=1'b1;assign cmd_addr=issue_slot?address1:address0;
 assign cmd_burst_data=issue_slot?assembly1:assembly0;
 assign cmd_wdata=cmd_burst_data[255:0];assign cmd_wstrb=32'hffffffff;
 assign terminal_valid=rst_n&&state==REPORT;
 assign terminal_data={bank,generation,terminal_ok,reason};
 wire issue=cmd_valid&&cmd_ready;
 wire retire=rsp_valid&&(inflight||issue);
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 state<=IDLE;bank<=0;frame_bad<=0;terminal_ok<=0;generation<=0;reason<=0;seen<=0;written<=0;fill<=0;base<=0;
 assembly0<=0;assembly1<=0;address0<=0;address1<=0;occupied<=0;fill_slot<=0;issue_slot<=0;inflight<=0;fault<=0;
 end else begin
 if(consume)begin
 if(state==IDLE)begin
 if(kind!=0)fault<=1;
 else begin bank<=pb;generation<=pg;base<=pb?SOURCE_BASE1:SOURCE_BASE0;frame_bad<=0;seen<=0;written<=0;fill<=0;reason<=0;state<=COLLECT;end
 end else if(kind==1)begin
 seen<=seen+1'b1;
 if(pb!=bank||pg!=generation||pa!={seen[20:0],3'b0}||seen>=SRC_W*SRC_H/8)begin frame_bad<=1;reason<=14;fault<=1;end
 else if(!frame_bad)begin
 if(fill_slot)assembly1[fill*256+:256]<=input_packet[255:0];
 else assembly0[fill*256+:256]<=input_packet[255:0];
 if(fill==0)begin if(fill_slot)address1<=base+{4'd0,pa};else address0<=base+{4'd0,pa};end
 if(fill==BURST_BEATS-1)begin occupied[fill_slot]<=1;fill_slot<=!fill_slot;fill<=0;end
 else fill<=fill+1'b1;
 end
 end else if(kind==2)begin
 terminal_ok<=pok&&!frame_bad&&pb==bank&&pg==generation&&fill==0&&seen==SRC_W*SRC_H/8&&written==SRC_W*SRC_H/8;
 reason<=!pok?(pr!=0?pr:4'd12):frame_bad||pb!=bank||pg!=generation?4'd14:fill!=0||seen!=SRC_W*SRC_H/8||written!=SRC_W*SRC_H/8?4'd15:4'd0;
 fill<=0;state<=REPORT;
 end else begin fault<=1;frame_bad<=1;reason<=14;end
 end
 if(issue)inflight<=1;
 if(retire)begin
 if(!rsp_write)begin frame_bad<=1;reason<=14;fault<=1;end else written<=written+BURST_BEATS;
 occupied[issue_slot]<=0;issue_slot<=!issue_slot;inflight<=0;
 end
 if(state==REPORT&&terminal_ready)state<=IDLE;
 end end
 // synthesis translate_off
 initial if((BURST_BEATS!=8&&BURST_BEATS!=16)||SRC_W*SRC_H%(BURST_BEATS*8)!=0)$fatal(1,"native capture writer requires 8/16 beats and complete bursts");
 // synthesis translate_on
endmodule
`default_nettype wire
