`timescale 1ns/1ps
`default_nettype none

// 板级顶层连线测试。
// 这里的 PLL 与 MS7210 控制器只是仿真模型，不会进入真实 FPGA。
module tb_hdmi_colorbar_top;

reg sys_clk_27m;
reg rst_n;

wire        hd_tx_pclk;
wire        hd_tx_vs;
wire        hd_tx_hs;
wire        hd_tx_de;
wire [23:0] hd_tx_data;
wire        hd_reset_n;
wire        hd_scl;
wire        hd_sda;
wire        hdmi_init_done;

integer test_failed;

hdmi_colorbar_top #(
    .H_SYNC               (12'd1),
    .H_BACK               (12'd1),
    .H_ACTIVE             (12'd4),
    .H_FRONT              (12'd1),
    .V_SYNC               (12'd1),
    .V_BACK               (12'd1),
    .V_ACTIVE             (12'd2),
    .V_FRONT              (12'd1),
    .HDMI_RESET_CYCLES    (16'd4)
) dut (
    .sys_clk_27m    (sys_clk_27m),
    .rst_n          (rst_n),
    .hd_tx_pclk     (hd_tx_pclk),
    .hd_tx_vs       (hd_tx_vs),
    .hd_tx_hs       (hd_tx_hs),
    .hd_tx_de       (hd_tx_de),
    .hd_tx_data     (hd_tx_data),
    .hd_reset_n     (hd_reset_n),
    .hd_scl         (hd_scl),
    .hd_sda         (hd_sda),
    .hdmi_init_done (hdmi_init_done)
);

always #5 sys_clk_27m = ~sys_clk_27m;

task fail_test;
    input [8*96-1:0] reason;
    begin
        test_failed = 1;
        $display("TEST_FAIL_HDMI_TOP: %0s", reason);
    end
endtask

initial begin
    sys_clk_27m = 1'b0;
    rst_n = 1'b0;
    test_failed = 0;

    repeat (3) @(posedge sys_clk_27m);
    if (hd_reset_n !== 1'b0)
        fail_test("MS7210 reset must remain low during external reset");

    rst_n = 1'b1;

    wait (hd_reset_n === 1'b1);
    wait (hdmi_init_done === 1'b1);
    wait (hd_tx_de === 1'b1);
    #1;

    if (hd_tx_data !== 24'hFF0000)
        fail_test("first active color-bar pixel must be red");

    if (hd_tx_pclk !== sys_clk_27m)
        fail_test("simulation PLL model must forward the input clock");

    if (test_failed == 0)
        $display("TEST_PASS_HDMI_TOP");

    $stop;
end

endmodule

// 27 MHz -> 148.5 MHz PLL 的仿真模型。
module video_pll_27m_148m5(
    input  wire clkin1,
    output wire clkout0,
    output reg  lock
);
reg [1:0] lock_count;
assign clkout0 = clkin1;

initial begin
    lock = 1'b0;
    lock_count = 2'd0;
end

always @(posedge clkin1) begin
    if (!lock) begin
        if (lock_count == 2'd2)
            lock <= 1'b1;
        else
            lock_count <= lock_count + 1'b1;
    end
end
endmodule

// 27 MHz -> 10 MHz PLL 的仿真模型。
module config_pll_27m_10m(
    input  wire clkin1,
    output wire clkout0,
    output reg  lock
);
reg [1:0] lock_count;
assign clkout0 = clkin1;

initial begin
    lock = 1'b0;
    lock_count = 2'd0;
end

always @(posedge clkin1) begin
    if (!lock) begin
        if (lock_count == 2'd1)
            lock <= 1'b1;
        else
            lock_count <= lock_count + 1'b1;
    end
end
endmodule

// 官方 MS7210 寄存器控制器的仿真替身。
module ms7210_ctl(
    input  wire        clk,
    input  wire        rstn,
    output reg         init_over,
    output wire [7:0]  device_id,
    output reg         iic_trig,
    output reg         w_r,
    output reg  [15:0] addr,
    output reg  [7:0]  data_in,
    input  wire        busy,
    input  wire [7:0]  data_out,
    input  wire        byte_over
);
reg [1:0] init_count;
assign device_id = 8'hB2;

initial begin
    init_over = 1'b0;
    iic_trig = 1'b0;
    w_r = 1'b0;
    addr = 16'd0;
    data_in = 8'd0;
    init_count = 2'd0;
end

always @(posedge clk) begin
    if (!rstn) begin
        init_over <= 1'b0;
        init_count <= 2'd0;
    end
    else if (!init_over) begin
        if (init_count == 2'd2)
            init_over <= 1'b1;
        else
            init_count <= init_count + 1'b1;
    end
end
endmodule

// 通用 I2C 驱动的仿真替身。
module iic_dri #(
    parameter [26:0] CLK_FRE   = 27'd10_000_000,
    parameter [19:0] IIC_FREQ  = 20'd400_000,
    parameter [9:0]  T_WR      = 10'd1,
    parameter [1:0]  ADDR_BYTE = 2'd2,
    parameter [7:0]  LEN_WIDTH = 8'd3,
    parameter [1:0]  DATA_BYTE = 2'd1
)(
    input  wire                   clk,
    input  wire                   rstn,
    input  wire                   pluse,
    input  wire [7:0]             device_id,
    input  wire                   w_r,
    input  wire [LEN_WIDTH:0]     byte_len,
    input  wire [ADDR_BYTE*8-1:0] addr,
    input  wire [7:0]             data_in,
    output wire                   busy,
    output wire                   byte_over,
    output wire [7:0]             data_out,
    output wire                   scl,
    input  wire                   sda_in,
    output wire                   sda_out,
    output wire                   sda_out_en
);
assign busy = 1'b0;
assign byte_over = 1'b0;
assign data_out = 8'd0;
assign scl = 1'b1;
assign sda_out = 1'b1;
assign sda_out_en = 1'b0;
endmodule

`default_nettype wire

