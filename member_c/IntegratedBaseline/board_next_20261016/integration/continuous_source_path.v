`timescale 1ns/1ps
`default_nettype none
module continuous_source_path #(
 parameter MARKER_MODE=1,
 parameter SRC_W=1920,SRC_H=1080,MIN_PIXELS=64,MAX_PIXELS=16384,MAX_SPAN=256,FIFO_ADDR_BITS=9,
 parameter BLACK_RMIN=0,BLACK_RMAX=64,BLACK_GMIN=0,BLACK_GMAX=64,BLACK_BMIN=0,BLACK_BMAX=64,
 parameter P0_XMIN=0,P0_XMAX=SRC_W/2-1,P0_YMIN=0,P0_YMAX=SRC_H/2-1,
 parameter P1_XMIN=SRC_W/2,P1_XMAX=SRC_W-1,P1_YMIN=0,P1_YMAX=SRC_H/2-1,
 parameter P2_XMIN=SRC_W/2,P2_XMAX=SRC_W-1,P2_YMIN=SRC_H/2,P2_YMAX=SRC_H-1,
 parameter P3_XMIN=0,P3_XMAX=SRC_W/2-1,P3_YMIN=SRC_H/2,P3_YMAX=SRC_H-1,
 parameter IN_W=1920,IN_H=1080,DATA_FIFO_ADDR_BITS=10,BURST_BEATS=8,PROC_CYCLES_PER_MS=54000,
 parameter[27:0]SOURCE_BASE0=28'd0,SOURCE_BASE1=28'h0800000
)(

 input wire rx_clk,proc_clk,ui_clk,rst_n,enabled,raw_requested,rx_vs,rx_de,input wire[23:0]rx_rgb,
 output wire frame_valid,input wire frame_ready,output wire frame_bank,
 output wire[31:0]frame_generation,output wire[95:0]frame_corners,output wire frame_geometry_valid,
 output wire[DATA_FIFO_ADDR_BITS:0]data_fifo_peak,output wire[31:0]frame_capture_ms,output wire[511:0]reject_reason_counts,output wire[31:0]admitted_frames,
 input wire release_valid,release_bank,input wire[31:0]release_generation,
 output wire[31:0]rejected_frames,dropped_frames,output wire[3:0]last_failure_reason,output wire fault,output wire[3:0]fault_components,
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
 assign fault_components={geometry_fault,manager_fault,writer_fault_sync[2],rx_fault_sync[2]};
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
 wire queue_ready,alloc_source_ready;wire[DATA_FIFO_ADDR_BITS:0]rx_fifo_peak;
 snapshot_cdc #(.WIDTH(DATA_FIFO_ADDR_BITS+1)) fifo_peak_crossing(.s_clk(rx_clk),.d_clk(proc_clk),.rst_n(rst_n),.s_data(rx_fifo_peak),.d_data(data_fifo_peak),.d_valid());
 wire is_begin=packet[319:318]==0;
 assign packet_ready=queue_ready&&(!is_begin||alloc_source_ready);
 async_packet_stream_monitored #(.DATA_WIDTH(320),.ADDR_BITS(DATA_FIFO_ADDR_BITS)) data_crossing(
 .wr_clk(rx_clk),.rd_clk(ui_clk),.rst_n(rst_n),
 .wr_peak(rx_fifo_peak),.s_valid(packet_valid&&(!is_begin||alloc_source_ready)),.s_ready(queue_ready),.s_data(packet),
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
 continuous_capture_geometry #(.MARKER_MODE(MARKER_MODE),.SRC_W(SRC_W),.SRC_H(SRC_H),.MIN_PIXELS(MIN_PIXELS),.MAX_PIXELS(MAX_PIXELS),.MAX_SPAN(MAX_SPAN),.BLACK_RMIN(BLACK_RMIN),.BLACK_RMAX(BLACK_RMAX),.BLACK_GMIN(BLACK_GMIN),.BLACK_GMAX(BLACK_GMAX),.BLACK_BMIN(BLACK_BMIN),.BLACK_BMAX(BLACK_BMAX),.P0_XMIN(P0_XMIN),.P0_XMAX(P0_XMAX),.P0_YMIN(P0_YMIN),.P0_YMAX(P0_YMAX),.P1_XMIN(P1_XMIN),.P1_XMAX(P1_XMAX),.P1_YMIN(P1_YMIN),.P1_YMAX(P1_YMAX),.P2_XMIN(P2_XMIN),.P2_XMAX(P2_XMAX),.P2_YMIN(P2_YMIN),.P2_YMAX(P2_YMAX),.P3_XMIN(P3_XMIN),.P3_XMAX(P3_XMAX),.P3_YMIN(P3_YMIN),.P3_YMAX(P3_YMAX),.FIFO_ADDR_BITS(FIFO_ADDR_BITS)) geometry(
 .rx_clk(rx_clk),.proc_clk(proc_clk),.rst_n(rst_n),
 .sample_valid(sample_valid),.sample_first(sample_first),.sample_bank(sample_bank),.sample_generation(sample_generation),.sample_x(sample_x),.sample_y(sample_y),.sample_rgb(rx_rgb),
 .close_valid(close_valid),.close_bank(close_bank),.close_ok(close_ok),.close_generation(close_generation),
 .metadata_valid(metadata_valid),.metadata_ready(metadata_ready),.metadata_data(metadata_data),.fault(geometry_fault));
 wire return_valid,return_ready;wire[32:0]return_data;
 continuous_capture_manager #(.PROC_CYCLES_PER_MS(PROC_CYCLES_PER_MS)) manager(
 .clk(proc_clk),.rst_n(rst_n),.raw_requested(raw_requested),.allocation_valid(alloc_valid),.allocation_ready(alloc_ready),.allocation_data(alloc_data),
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
