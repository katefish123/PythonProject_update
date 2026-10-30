`timescale 1ns/1ps
`default_nettype none
// Clock-independent integration boundary; the board wrapper owns PLLs and I/O.
// This bring-up profile uses BRAM snapshots (1080p input decimated by six).
module video_correct_core #(
    parameter IN_W=1920,IN_H=1080,DECIMATE=6,
    parameter SRC_W=IN_W/DECIMATE,SRC_H=IN_H/DECIMATE,
    parameter OUT_W=160,OUT_H=226,SCALE=4,
    parameter H_SYNC=44,H_BACK=148,H_ACTIVE=1920,H_FRONT=88,
    parameter V_SYNC=5,V_BACK=36,V_ACTIVE=1080,V_FRONT=4,
    parameter MIN_PIXELS=16,MAX_PIXELS=4096,MAX_SPAN=128,
    parameter CAPTURE_TIMEOUT=54000000,RETRY_CYCLES=270000
)(
    input wire proc_clk,proc_rst_n,rx_clk,rx_rst_n,pix_clk,pix_rst_n,
    input wire enabled,rx_vs,rx_de,
    input wire [23:0] rx_rgb,
    input wire nearest,force_pattern,
    output wire hsync,vsync,de,
    output wire [23:0] rgb,
    output wire image_valid,working,frame_error,input_wait,
    output wire [31:0] good_frames,rejected_frames
);
    wire capture_request,capture_complete,capture_ok;
    wire processor_start,processor_reset_n,processor_done,processor_error;
    wire write_bank,publish_toggle,publish_bank,display_ack;
    wire mem_valid,mem_rsp_valid,write_valid;
    wire [23:0] mem_addr,mem_rgb,write_addr,write_rgb;
    frame_session #(.CAPTURE_TIMEOUT(CAPTURE_TIMEOUT),.RETRY_CYCLES(RETRY_CYCLES)) session(
        .clk(proc_clk),.rst_n(proc_rst_n),.enabled(enabled),
        .capture_request(capture_request),.capture_complete(capture_complete),.capture_ok(capture_ok),
        .processor_start(processor_start),.processor_reset_n(processor_reset_n),
        .processor_done(processor_done),.processor_error(processor_error),
        .write_bank(write_bank),.publish_toggle(publish_toggle),.publish_bank(publish_bank),.display_ack(display_ack),
        .frame_error(frame_error),.input_wait(input_wait),.working(working),
        .good_frames(good_frames),.rejected_frames(rejected_frames));
    snapshot_capture #(.IN_W(IN_W),.IN_H(IN_H),.DECIMATE(DECIMATE),.SRC_W(SRC_W),.SRC_H(SRC_H)) source_store(
        .rx_clk(rx_clk),.rx_rst_n(rx_rst_n),.rx_vs(rx_vs),.rx_de(rx_de),.rx_rgb(rx_rgb),
        .request_toggle(capture_request),.complete_toggle(capture_complete),.capture_ok(capture_ok),
        .rd_clk(proc_clk),.rd_rst_n(processor_reset_n),.rd_valid(mem_valid),.rd_addr(mem_addr),
        .rd_rsp_valid(mem_rsp_valid),.rd_rgb(mem_rgb));
    frame_processor #(.SRC_W(SRC_W),.SRC_H(SRC_H),.OUT_W(OUT_W),.OUT_H(OUT_H),
        .MIN_PIXELS(MIN_PIXELS),.MAX_PIXELS(MAX_PIXELS),.MAX_SPAN(MAX_SPAN)) processor(
        .clk(proc_clk),.rst_n(processor_reset_n),.start(processor_start),.nearest(nearest),
        .busy(),.done(processor_done),.error(processor_error),
        .mem_valid(mem_valid),.mem_ready(1'b1),.mem_addr(mem_addr),.mem_rsp_valid(mem_rsp_valid),.mem_rgb(mem_rgb),
        .write_valid(write_valid),.write_ready(1'b1),.write_addr(write_addr),.write_rgb(write_rgb),
        .cycles(),.completed_pixels(),.geometry_valid());
    result_display #(.OUT_W(OUT_W),.OUT_H(OUT_H),.SCALE(SCALE),
        .H_SYNC(H_SYNC),.H_BACK(H_BACK),.H_ACTIVE(H_ACTIVE),.H_FRONT(H_FRONT),
        .V_SYNC(V_SYNC),.V_BACK(V_BACK),.V_ACTIVE(V_ACTIVE),.V_FRONT(V_FRONT)) display_store(
        .wr_clk(proc_clk),.wr_en(write_valid),.wr_bank(write_bank),.wr_addr(write_addr),.wr_rgb(write_rgb),
        .pix_clk(pix_clk),.rst_n(pix_rst_n),.publish_toggle(publish_toggle),.publish_bank(publish_bank),
        .force_pattern(force_pattern),.ack_toggle(display_ack),.hsync(hsync),.vsync(vsync),.de(de),.rgb(rgb),.image_valid(image_valid));
endmodule
`default_nettype wire
