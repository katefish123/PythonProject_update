`timescale 1ns/1ps
`default_nettype none

// MS7210 配置连接层。
//
// 本文件只负责连接“MS7210 寄存器控制器”和“通用 I2C 驱动”。
// 真正的寄存器表由盘古官方 ms7210_ctl.v 提供，I2C 时序由官方
// iic_dri.v 提供；取得有明确来源的文件后，将它们加入 PDS 工程即可。
module ms7210_config (
    input  wire cfg_clk,
    input  wire reset_n,

    output wire init_done,
    output wire iic_scl,
    inout  wire iic_sda
);

wire [7:0]  device_id;
wire        iic_trigger;
wire        write_read;
wire [15:0] register_address;
wire [7:0]  write_data;
wire        iic_busy;
wire [7:0]  read_data;
wire        byte_done;
wire        sda_input;
wire        sda_output;
wire        sda_output_enable;

ms7210_ctl u_ms7210_ctl (
    .clk       (cfg_clk),
    .rstn      (reset_n),
    .init_over (init_done),
    .device_id (device_id),
    .iic_trig  (iic_trigger),
    .w_r       (write_read),
    .addr      (register_address),
    .data_in   (write_data),
    .busy      (iic_busy),
    .data_out  (read_data),
    .byte_over (byte_done)
);

iic_dri #(
    .CLK_FRE   (27'd10_000_000),
    .IIC_FREQ  (20'd400_000),
    .T_WR      (10'd1),
    .ADDR_BYTE (2'd2),
    .LEN_WIDTH (8'd3),
    .DATA_BYTE (2'd1)
) u_iic_dri (
    .clk        (cfg_clk),
    .rstn       (reset_n),
    .pluse      (iic_trigger),
    .device_id  (device_id),
    .w_r        (write_read),
    .byte_len   (4'd1),
    .addr       (register_address),
    .data_in    (write_data),
    .busy       (iic_busy),
    .byte_over  (byte_done),
    .data_out   (read_data),
    .scl        (iic_scl),
    .sda_in     (sda_input),
    .sda_out    (sda_output),
    .sda_out_en (sda_output_enable)
);

assign iic_sda = sda_output_enable ? sda_output : 1'bz;
assign sda_input = iic_sda;

endmodule

`default_nettype wire

