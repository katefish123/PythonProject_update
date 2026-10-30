`timescale 1ns/1ps
// Learning wrapper. All requests belong to clk. rst_n is active low.
module fifo_ip_top (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       wr_en,
    input  wire [7:0] din,
    input  wire       rd_en,
    output wire [7:0] dout,
    output wire       full,
    output wire       empty,
    output wire [9:0] wr_water_level,
    output wire [9:0] rd_water_level,
    output wire       almost_full,
    output wire       almost_empty
);
    // The generated Pango IP uses an active-high reset.
    wire rst = !rst_n;

    // Block writes at full and reads at empty, using pre-edge flags.
    wire write_accept = wr_en && !full && rst_n;
    wire read_accept  = rd_en && !empty && rst_n;

    fifo_sync_8x512 u_fifo (
        .clk            (clk),
        .rst            (rst),
        .wr_en          (write_accept),
        .wr_data        (din),
        .wr_full        (full),
        .wr_water_level (wr_water_level),
        .almost_full    (almost_full),
        .rd_en          (read_accept),
        .rd_data        (dout),
        .rd_empty       (empty),
        .rd_water_level (rd_water_level),
        .almost_empty   (almost_empty)
    );
endmodule
