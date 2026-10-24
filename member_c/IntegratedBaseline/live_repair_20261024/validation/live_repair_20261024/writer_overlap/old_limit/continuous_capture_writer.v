`timescale 1ns/1ps
`default_nettype none
module continuous_capture_writer #(
 parameter SRC_W=1920,SRC_H=1080,BURST_BEATS=8,
 parameter[27:0]SOURCE_BASE0=28'd0,SOURCE_BASE1=28'h0800000
)(
 input wire clk,rst_n,
 input wire packet_valid,output wire packet_ready,input wire[319:0]packet_data,
 output wire cmd_valid,input wire cmd_ready,output wire cmd_write,
 output wire[27:0]cmd_addr,output wire[255:0]cmd_wdata,output wire[31:0]cmd_wstrb,output wire[2047:0]cmd_burst_data,
 input wire rsp_valid,rsp_write,
 output wire terminal_valid,input wire terminal_ready,output wire[37:0]terminal_data,
 output reg fault
);
 localparam IDLE=0,COLLECT=1,SEND=2,WAIT_ACK=3,REPORT=4;
 reg[2:0]state;reg bank,frame_bad,terminal_ok;reg[31:0]generation;
 reg[3:0]reason;reg[31:0]seen,written;reg[3:0]fill;
 reg[27:0]base,burst_addr;reg[2047:0]assembly;
 // One-record elastic boundary breaks the async FIFO's combinational output
 // from header validation and assembly. It can retain END/next DATA while an
 // owned native burst waits for command acceptance or its final-beat ACK.
 reg input_valid;reg[319:0]input_packet;
 wire consume=input_valid&&(state==IDLE||state==COLLECT);
 wire[1:0]kind=input_packet[319:318];wire pb=input_packet[317];wire[31:0]pg=input_packet[316:285];wire[23:0]pa=input_packet[284:261];wire pok=input_packet[260];wire[3:0]pr=input_packet[259:256];
 assign packet_ready=rst_n&&(!input_valid||consume);
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin input_valid<=0;input_packet<=0;end
 else if(packet_ready)begin input_valid<=packet_valid;input_packet<=packet_data;end
 end
 assign cmd_valid=rst_n&&state==SEND;assign cmd_write=1'b1;
 assign cmd_addr=burst_addr;assign cmd_wdata=assembly[255:0];assign cmd_wstrb=32'hffffffff;assign cmd_burst_data=assembly;
 assign terminal_valid=rst_n&&state==REPORT;
 assign terminal_data={bank,generation,terminal_ok,reason};
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin state<=IDLE;bank<=0;frame_bad<=0;terminal_ok<=0;generation<=0;reason<=0;seen<=0;written<=0;fill<=0;base<=0;burst_addr<=0;assembly<=0;fault<=0;end
 else begin
 // Data storage depends only on registered packet kind/valid and local
 // collection position. Header errors still block fill/SEND below; writing
 // a rejected partial lane is harmless because it never becomes owned.
 // Every one of eight lanes is overwritten before SEND; clearing 2048 bits
 // on BEGIN/END/ACK only adds a large shared enable cone and is unnecessary.
 if(consume&&state==COLLECT&&kind==1)assembly[fill*256+:256]<=input_packet[255:0];
 if(consume)begin
 if(state==IDLE)begin
 if(kind!=0)fault<=1;
 else begin bank<=pb;generation<=pg;base<=pb?SOURCE_BASE1:SOURCE_BASE0;frame_bad<=0;seen<=0;written<=0;fill<=0;reason<=0;state<=COLLECT;end
 end else if(kind==1)begin
 seen<=seen+1'b1;
 if(pb!=bank||pg!=generation||pa!={seen[20:0],3'b0}||seen>=SRC_W*SRC_H/8)begin frame_bad<=1;reason<=14;fault<=1;end
 else if(!frame_bad)begin
 if(fill==0)burst_addr<=base+{4'd0,pa};
 fill<=fill+1'b1;
 if(fill==BURST_BEATS-1)state<=SEND;
 end
 end else if(kind==2)begin
 terminal_ok<=pok&&!frame_bad&&pb==bank&&pg==generation&&fill==0&&seen==SRC_W*SRC_H/8&&written==SRC_W*SRC_H/8;
 reason<=!pok?(pr!=0?pr:4'd12):frame_bad||pb!=bank||pg!=generation?4'd14:fill!=0||seen!=SRC_W*SRC_H/8||written!=SRC_W*SRC_H/8?4'd15:4'd0;
 fill<=0;state<=REPORT;
 end else begin fault<=1;frame_bad<=1;reason<=14;end
 end
 if(state==SEND&&cmd_ready)begin
 if(rsp_valid)begin
 if(!rsp_write)begin frame_bad<=1;reason<=14;fault<=1;end else written<=written+BURST_BEATS;
 fill<=0;state<=COLLECT;
 end else state<=WAIT_ACK;
 end
 if(state==WAIT_ACK&&rsp_valid)begin
 if(!rsp_write)begin frame_bad<=1;reason<=14;fault<=1;end else written<=written+BURST_BEATS;
 fill<=0;state<=COLLECT;
 end
 if(state==REPORT&&terminal_ready)state<=IDLE;
 end end
 // synthesis translate_off
 initial if(BURST_BEATS!=8||SRC_W*SRC_H%64!=0)$fatal(1,"native capture writer requires8beat bursts and64pixel multiple");
 // synthesis translate_on
endmodule
`default_nettype wire
