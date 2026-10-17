`timescale 1ns/1ps
`default_nettype none

// Board-level MS7200 RX then MS7210 TX configuration.
// init outputs report controller completion; ack_error is sticky until reset.
module hdmi_config #(
    parameter TX_FIRST = 1'b0,
    parameter CLK_FRE  = 27'd10_000_000,
    parameter IIC_FREQ = 20'd400_000
) (
    input  wire cfg_clk,
    input  wire reset_n,
    output wire rx_done,
    output wire tx_done,
    output wire scl,
    inout  wire sda,
    output wire ack_error
);
    wire [7:0] rx_id, tx_id, rx_data, tx_data, read_data;
    wire [15:0] rx_addr, tx_addr;
    wire rx_trig, tx_trig, rx_wr, tx_wr;
    wire bus_busy, byte_done, sda_out, sda_out_en, bus_ack_error;
    reg switch_to_tx = 1'b0;
    reg switch_to_rx = 1'b0;
    wire select_tx;

    // Latch ownership only at an idle bus boundary. Hold the next controller
    // in reset until then, so its first trigger cannot be lost while the
    // current controller finishes an in-flight register read.
    always @(posedge cfg_clk or negedge reset_n) begin
        if (!reset_n) begin
            switch_to_tx <= 1'b0;
            switch_to_rx <= 1'b0;
        end else if (!bus_busy) begin
            if (!TX_FIRST && rx_done)
                switch_to_tx <= 1'b1;
            if (TX_FIRST && tx_done)
                switch_to_rx <= 1'b1;
        end
    end
    assign select_tx = TX_FIRST ? !switch_to_rx : switch_to_tx;

    ms7200_ctl u_ms7200_rx (
        .clk(cfg_clk),
        .rstn(reset_n && (!TX_FIRST || switch_to_rx)),
        .init_over(rx_done),
        .device_id(rx_id),
        .iic_trig(rx_trig),
        .w_r(rx_wr),
        .addr(rx_addr),
        .data_in(rx_data),
        .busy(select_tx ? 1'b0 : bus_busy),
        .data_out(select_tx ? 8'd0 : read_data),
        .byte_over(select_tx ? 1'b0 : byte_done)
    );

    ms7210_ctl u_ms7210_tx (
        .clk(cfg_clk),
        .rstn(reset_n && (TX_FIRST || switch_to_tx)),
        .init_over(tx_done),
        .device_id(tx_id),
        .iic_trig(tx_trig),
        .w_r(tx_wr),
        .addr(tx_addr),
        .data_in(tx_data),
        .busy(select_tx ? bus_busy : 1'b0),
        .data_out(select_tx ? read_data : 8'd0),
        .byte_over(select_tx ? byte_done : 1'b0)
    );

    iic_dri #(
        .CLK_FRE(CLK_FRE),
        .IIC_FREQ(IIC_FREQ),
        .T_WR(10'd1),
        .ADDR_BYTE(2'd2),
        .LEN_WIDTH(8'd3),
        .DATA_BYTE(2'd1)
    ) u_iic_dri (
        .clk(cfg_clk),
        .rstn(reset_n),
        .pluse(select_tx ? tx_trig : rx_trig),
        .device_id(select_tx ? tx_id : rx_id),
        .w_r(select_tx ? tx_wr : rx_wr),
        .byte_len(4'd1),
        .addr(select_tx ? tx_addr : rx_addr),
        .data_in(select_tx ? tx_data : rx_data),
        .busy(bus_busy),
        .byte_over(byte_done),
        .data_out(read_data),
        .ack_error(bus_ack_error),
        .scl(scl),
        .sda_in(sda),
        .sda_out(sda_out),
        .sda_out_en(sda_out_en)
    );

    // I2C SDA is open-drain: drive low or release; never source a logic high.
    assign sda = (sda_out_en && !sda_out) ? 1'b0 : 1'bz;
    assign ack_error = bus_ack_error;
endmodule

`default_nettype wire
