from pathlib import Path
here=Path(__file__).resolve().parent
old=Path('D:/FPGA/output/c_stream_board_v1_20261015/rtl/algo/capture_geometry.v').read_text()
params=old.split('module capture_geometry #(',1)[1].split(')(\n',1)[0]
names=['SRC_W','SRC_H','MIN_PIXELS','MAX_PIXELS','MAX_SPAN','BLACK_RMIN','BLACK_RMAX','BLACK_GMIN','BLACK_GMAX','BLACK_BMIN','BLACK_BMAX']+[f'P{n}_{axis}{bound}' for n in range(4) for axis in 'XY' for bound in ['MIN','MAX']]
forward=','.join(f'.{n}({n})' for n in names)
body=r'''
 input wire rx_clk,proc_clk,rst_n,
 input wire sample_valid,sample_first,sample_bank,input wire[31:0]sample_generation,
 input wire[11:0]sample_x,sample_y,input wire[23:0]sample_rgb,
 input wire close_valid,close_bank,close_ok,input wire[31:0]close_generation,
 output reg metadata_valid,input wire metadata_ready,output reg[129:0]metadata_data,
 output reg fault
);
 wire black=sample_rgb[23:16]>=BLACK_RMIN&&sample_rgb[23:16]<=BLACK_RMAX&&sample_rgb[15:8]>=BLACK_GMIN&&sample_rgb[15:8]<=BLACK_GMAX&&sample_rgb[7:0]>=BLACK_BMIN&&sample_rgb[7:0]<=BLACK_BMAX;
 wire roi=(sample_x>=P0_XMIN&&sample_x<=P0_XMAX&&sample_y>=P0_YMIN&&sample_y<=P0_YMAX)||
 (sample_x>=P1_XMIN&&sample_x<=P1_XMAX&&sample_y>=P1_YMIN&&sample_y<=P1_YMAX)||
 (sample_x>=P2_XMIN&&sample_x<=P2_XMAX&&sample_y>=P2_YMIN&&sample_y<=P2_YMAX)||
 (sample_x>=P3_XMIN&&sample_x<=P3_XMAX&&sample_y>=P3_YMIN&&sample_y<=P3_YMAX);
 wire contribution=black&&roi;
 reg start_sent,overflow;
 reg[84:0]ends[0:1];reg eh,et;reg[1:0]ec;
 wire live=sample_valid&&(sample_first||contribution);
 wire event_s_ready,event_valid,event_ready;wire[84:0]event_data;
 wire send_end=ec!=0;
 wire source_valid=send_end||live;
 wire[84:0]live_data={contribution,overflow,sample_first||!start_sent,1'b0,sample_bank,sample_generation,sample_x,sample_y,sample_rgb};
 wire[84:0]source_data=send_end?ends[eh]:live_data;
 wire end_pop=send_end&&event_s_ready;
 async_packet_stream #(.DATA_WIDTH(85),.ADDR_BITS(FIFO_ADDR_BITS)) events(
 .wr_clk(rx_clk),.rd_clk(proc_clk),.rst_n(rst_n),.s_valid(source_valid),.s_ready(event_s_ready),.s_data(source_data),
 .m_valid(event_valid),.m_ready(event_ready),.m_data(event_data));
 always @(posedge rx_clk or negedge rst_n)begin
 if(!rst_n)begin start_sent<=0;overflow<=0;eh<=0;et<=0;ec<=0;end
 else begin
 case({close_valid,end_pop})2'b10:ec<=ec+1'b1;2'b01:ec<=ec-1'b1;default:begin end endcase
 if(close_valid)begin
 ends[et]<={1'b0,!close_ok||overflow,!start_sent,1'b1,close_bank,close_generation,48'd0};et<=~et;
 end
 if(end_pop)eh<=~eh;
 if(sample_first)begin start_sent<=0;overflow<=0;end
 if(live)begin
 if(!send_end&&event_s_ready)start_sent<=1;
 else overflow<=1;
 end
 end end
 reg waiting,frame_bad,held_bank;reg[31:0]held_generation;
 wire take=event_valid&&event_ready;
 assign event_ready=!waiting&&(!metadata_valid||metadata_ready);
 wire valid,reject_frame,dropped,busy;wire[11:0]x0,y0,x1,y1,x2,y2,x3,y3;
 marker_detector #(@FORWARD@) detector(
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
 always @(posedge rx_clk)if(rst_n&&(ec>2||(close_valid&&ec==2&&!end_pop)))$fatal(1,"geometry terminal ownership queue overflow");
 // synthesis translate_on
endmodule
`default_nettype wire
'''.replace('@FORWARD@',forward)
# Equal RX pipeline delay for sample framing and terminal identity, before ROI.
ports,logic=body.split(' wire black=',1)
tap_fields=[('sample_valid',1),('sample_first',1),('sample_bank',1),('sample_generation',32),('sample_x',12),('sample_y',12),('sample_rgb',24),('close_valid',1),('close_bank',1),('close_ok',1),('close_generation',32)]
import re
logic=' wire black='+logic
for name,width in tap_fields:
 logic=re.sub(r'\b'+name+r'\b','tap_'+name,logic)
declarations=''.join(f' reg'+(f'[{width-1}:0]' if width>1 else '')+f' tap_{name};\n' for name,width in tap_fields)
pipeline=' always @(posedge rx_clk or negedge rst_n)begin\n if(!rst_n)begin\n'+''.join(f' tap_{name}<=0;\n' for name,width in tap_fields)+' end else begin\n'+''.join(f' tap_{name}<={name};\n' for name,width in tap_fields)+' end end\n'
body=ports+declarations+pipeline+logic
(here/'continuous_capture_geometry.v').write_text('`timescale 1ns/1ps\n`default_nettype none\nmodule continuous_capture_geometry #('+params+')(\n'+body)
# Top-level parameter list extends the original geometry parameters.
top_params=params.rstrip()+',\n parameter IN_W=1920,IN_H=1080,DATA_FIFO_ADDR_BITS=10,BURST_BEATS=8,PROC_CYCLES_PER_MS=54000,\n parameter[27:0]SOURCE_BASE0=28\'d0,SOURCE_BASE1=28\'h0800000\n'
top=r'''
 input wire rx_clk,proc_clk,ui_clk,rst_n,enabled,rx_vs,rx_de,input wire[23:0]rx_rgb,
 output wire frame_valid,input wire frame_ready,output wire frame_bank,
 output wire[31:0]frame_generation,output wire[95:0]frame_corners,output wire frame_geometry_valid,
 output wire[31:0]frame_capture_ms,output wire[511:0]reject_reason_counts,output wire[31:0]admitted_frames,
 input wire release_valid,release_bank,input wire[31:0]release_generation,
 output wire[31:0]rejected_frames,dropped_frames,output wire[3:0]last_failure_reason,output wire fault,
 output wire cmd_valid,input wire cmd_ready,output wire cmd_write,output wire[27:0]cmd_addr,
 output wire[255:0]cmd_wdata,output wire[31:0]cmd_wstrb,output wire[2047:0]cmd_burst_data,
 input wire rsp_valid,rsp_write
);
 wire packet_valid,packet_ready;wire[319:0]packet;
 wire sample_valid,sample_first,sample_bank,close_valid,close_bank,close_ok;
 wire[11:0]sample_x,sample_y;wire[31:0]sample_generation,close_generation;wire[3:0]close_reason;
 wire credit_valid,credit_ready,credit_bank;wire[31:0]credit_generation;
 wire rx_fault,writer_fault,manager_fault,geometry_fault;
 wire[31:0]dropped_rx,admitted_rx;
 (* ASYNC_REG="TRUE" *)reg[2:0]rx_fault_sync,writer_fault_sync;
 (* ASYNC_REG="TRUE" *)reg[31:0]drop_gray_q0,drop_gray_q1,drop_gray_q2;
 (* ASYNC_REG="TRUE" *)reg[31:0]admit_gray_q0,admit_gray_q1,admit_gray_q2;
 reg[31:0]drop_gray,admit_gray;
 always @(posedge rx_clk or negedge rst_n)begin
 if(!rst_n)begin drop_gray<=0;admit_gray<=0;end
 else begin drop_gray<=(dropped_rx>>1)^dropped_rx;admit_gray<=(admitted_rx>>1)^admitted_rx;end
 end
 genvar bit_n;
 generate for(bit_n=0;bit_n<32;bit_n=bit_n+1)begin: drop_decode
 assign dropped_frames[bit_n]=^(drop_gray_q2>>bit_n);
 assign admitted_frames[bit_n]=^(admit_gray_q2>>bit_n);
 end endgenerate
 always @(posedge proc_clk or negedge rst_n)begin
 if(!rst_n)begin rx_fault_sync<=0;writer_fault_sync<=0;drop_gray_q0<=0;drop_gray_q1<=0;drop_gray_q2<=0;admit_gray_q0<=0;admit_gray_q1<=0;admit_gray_q2<=0;end
 else begin rx_fault_sync<={rx_fault_sync[1:0],rx_fault};writer_fault_sync<={writer_fault_sync[1:0],writer_fault};drop_gray_q0<=drop_gray;drop_gray_q1<=drop_gray_q0;drop_gray_q2<=drop_gray_q1;admit_gray_q0<=admit_gray;admit_gray_q1<=admit_gray_q0;admit_gray_q2<=admit_gray_q1;end
 end
 assign fault=rx_fault_sync[2]||writer_fault_sync[2]||manager_fault||geometry_fault;
 continuous_capture_rx #(.IN_W(IN_W),.IN_H(IN_H),.SRC_W(SRC_W),.SRC_H(SRC_H)) capture(
 .clk(rx_clk),.rst_n(rst_n),.enabled(enabled),.rx_vs(rx_vs),.rx_de(rx_de),.rx_rgb(rx_rgb),
 .release_valid(credit_valid),.release_bank(credit_bank),.release_generation(credit_generation),
 .packet_valid(packet_valid),.packet_ready(packet_ready),.packet_data(packet),
 .sample_valid(sample_valid),.sample_first(sample_first),.sample_x(sample_x),.sample_y(sample_y),.sample_bank(sample_bank),.sample_generation(sample_generation),
 .close_valid(close_valid),.close_bank(close_bank),.close_ok(close_ok),.close_generation(close_generation),.close_reason(close_reason),
 .dropped_frames(dropped_rx),.admitted_frames(admitted_rx),.fault(rx_fault),.owned_banks());
 assign credit_ready=1'b1;
 wire alloc_valid,alloc_ready;wire[32:0]alloc_data;
 wire ui_packet_valid,ui_packet_ready;wire[319:0]ui_packet;
 wire queue_ready,alloc_source_ready;
 wire is_begin=packet[319:318]==0;
 assign packet_ready=queue_ready&&(!is_begin||alloc_source_ready);
 async_packet_stream #(.DATA_WIDTH(320),.ADDR_BITS(DATA_FIFO_ADDR_BITS)) data_crossing(
 .wr_clk(rx_clk),.rd_clk(ui_clk),.rst_n(rst_n),
 .s_valid(packet_valid&&(!is_begin||alloc_source_ready)),.s_ready(queue_ready),.s_data(packet),
 .m_valid(ui_packet_valid),.m_ready(ui_packet_ready),.m_data(ui_packet));
 async_packet_stream #(.DATA_WIDTH(33),.ADDR_BITS(2)) allocation_crossing(
 .wr_clk(rx_clk),.rd_clk(proc_clk),.rst_n(rst_n),
 .s_valid(packet_valid&&is_begin&&queue_ready),.s_ready(alloc_source_ready),.s_data(packet[317:285]),
 .m_valid(alloc_valid),.m_ready(alloc_ready),.m_data(alloc_data));
 wire terminal_valid,terminal_ready;wire[37:0]terminal_data;
 wire writer_terminal_valid,writer_terminal_ready;wire[37:0]writer_terminal;
 continuous_capture_writer #(.SRC_W(SRC_W),.SRC_H(SRC_H),.BURST_BEATS(BURST_BEATS),.SOURCE_BASE0(SOURCE_BASE0),.SOURCE_BASE1(SOURCE_BASE1)) writer(
 .clk(ui_clk),.rst_n(rst_n),.packet_valid(ui_packet_valid),.packet_ready(ui_packet_ready),.packet_data(ui_packet),
 .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_write(cmd_write),.cmd_addr(cmd_addr),.cmd_wdata(cmd_wdata),.cmd_wstrb(cmd_wstrb),.cmd_burst_data(cmd_burst_data),
 .rsp_valid(rsp_valid),.rsp_write(rsp_write),.terminal_valid(writer_terminal_valid),.terminal_ready(writer_terminal_ready),.terminal_data(writer_terminal),.fault(writer_fault));
 async_packet_stream #(.DATA_WIDTH(38),.ADDR_BITS(2)) completion_crossing(
 .wr_clk(ui_clk),.rd_clk(proc_clk),.rst_n(rst_n),
 .s_valid(writer_terminal_valid),.s_ready(writer_terminal_ready),.s_data(writer_terminal),
 .m_valid(terminal_valid),.m_ready(terminal_ready),.m_data(terminal_data));
 wire metadata_valid,metadata_ready;wire[129:0]metadata_data;
 continuous_capture_geometry #(@FORWARD@,.FIFO_ADDR_BITS(FIFO_ADDR_BITS)) geometry(
 .rx_clk(rx_clk),.proc_clk(proc_clk),.rst_n(rst_n),
 .sample_valid(sample_valid),.sample_first(sample_first),.sample_bank(sample_bank),.sample_generation(sample_generation),.sample_x(sample_x),.sample_y(sample_y),.sample_rgb(rx_rgb),
 .close_valid(close_valid),.close_bank(close_bank),.close_ok(close_ok),.close_generation(close_generation),
 .metadata_valid(metadata_valid),.metadata_ready(metadata_ready),.metadata_data(metadata_data),.fault(geometry_fault));
 wire return_valid,return_ready;wire[32:0]return_data;
 continuous_capture_manager #(.PROC_CYCLES_PER_MS(PROC_CYCLES_PER_MS)) manager(
 .clk(proc_clk),.rst_n(rst_n),.allocation_valid(alloc_valid),.allocation_ready(alloc_ready),.allocation_data(alloc_data),
 .terminal_valid(terminal_valid),.terminal_ready(terminal_ready),.terminal_data(terminal_data),
 .metadata_valid(metadata_valid),.metadata_ready(metadata_ready),.metadata_data(metadata_data),
 .frame_valid(frame_valid),.frame_ready(frame_ready),.frame_bank(frame_bank),.frame_generation(frame_generation),.frame_corners(frame_corners),.frame_geometry_valid(frame_geometry_valid),
 .frame_capture_ms(frame_capture_ms),.reject_reason_counts(reject_reason_counts),
 .release_valid(release_valid),.release_bank(release_bank),.release_generation(release_generation),
 .return_valid(return_valid),.return_ready(return_ready),.return_data(return_data),
 .rejected_frames(rejected_frames),.last_failure_reason(last_failure_reason),.fault(manager_fault));
 async_packet_stream #(.DATA_WIDTH(33),.ADDR_BITS(2)) credit_crossing(
 .wr_clk(proc_clk),.rd_clk(rx_clk),.rst_n(rst_n),
 .s_valid(return_valid),.s_ready(return_ready),.s_data(return_data),
 .m_valid(credit_valid),.m_ready(credit_ready),.m_data({credit_bank,credit_generation}));
endmodule
`default_nettype wire
'''.replace('@FORWARD@',forward)
(here/'continuous_source_path.v').write_text('`timescale 1ns/1ps\n`default_nettype none\nmodule continuous_source_path #('+top_params+')(\n'+top)
'''
'''
