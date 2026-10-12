`timescale 1ns/1ps
`default_nettype none

// Board-level MS7200 RX then MS7210 TX configuration.
// ack_error preserves raw sticky bus history; config_error is the fatal
// readiness gate, allowing only pre-probe scratch retry NACKs.
module hdmi_config #(
    parameter TX_FIRST = 1'b0,
    parameter CLK_FRE  = 27'd10_000_000,
    parameter IIC_FREQ = 20'd400_000,
    parameter POST_RESET_SETTLE_CYCLES = CLK_FRE / 100
) (
    input  wire cfg_clk,
    input  wire reset_n,
    output wire rx_done,
    output wire tx_done,
    output wire scl,
    inout  wire sda,
    output wire ack_error,
    output reg config_error,
    output reg startup_retry_seen
);
    wire [7:0] rx_id, tx_id, rx_data, tx_data, read_data;
    wire [15:0] rx_addr, tx_addr;
    wire rx_trig, tx_trig, rx_wr, tx_wr;
    wire bus_busy, byte_done, sda_out, sda_out_en, bus_ack_error;
    wire nack_pulse, transaction_write, transaction_owner_tx, transaction_nack;
    wire [7:0] transaction_device;
    wire [15:0] transaction_addr;
    reg [31:0] settle_count;
    wire settle_done = (settle_count >= POST_RESET_SETTLE_CYCLES);
    wire controller_reset_n = reset_n && settle_done;
    reg bus_busy_d;
    reg rx_probe_done, tx_probe_done;

    // Keep all I2C/controller state reset and the bus idle after board reset;
    // 100k cfg_clk cycles is 10 ms with the default 10 MHz configuration PLL.
    always @(posedge cfg_clk or negedge reset_n) begin
        if (!reset_n) settle_count <= 32'd0;
        else if (!settle_done) settle_count <= settle_count + 1'b1;
    end
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
        .rstn(controller_reset_n && (!TX_FIRST || switch_to_rx)),
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
        .rstn(controller_reset_n && (TX_FIRST || switch_to_tx)),
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
        .rstn(controller_reset_n),
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
        .sda_out_en(sda_out_en),
        .owner_tx(select_tx),
        .nack_pulse(nack_pulse),
        .transaction_device(transaction_device),
        .transaction_addr(transaction_addr),
        .transaction_write(transaction_write),
        .transaction_owner_tx(transaction_owner_tx),
        .transaction_nack(transaction_nack)
    );

    wire bus_falling = bus_busy_d && !bus_busy;
    always @(posedge cfg_clk or negedge controller_reset_n) begin
        if (!controller_reset_n) begin
            bus_busy_d <= 1'b0;
            rx_probe_done <= 1'b0;
            tx_probe_done <= 1'b0;
            config_error <= 1'b0;
            startup_retry_seen <= 1'b0;
        end else begin
            bus_busy_d <= bus_busy;
            // A scratch probe succeeds only on a completed read returning 5A
            // with no NACK anywhere in that I2C transaction.
            if (bus_falling && !transaction_nack && !transaction_write &&
                transaction_addr == 16'h0003 && read_data == 8'h5A) begin
                if (transaction_owner_tx) tx_probe_done <= 1'b1;
                else rx_probe_done <= 1'b1;
            end

            if (nack_pulse) begin
                // Only the pre-probe 0003 scratch exercise is recoverable.
                // Once a chip verified its scratch value, even INIT's later
                // 0003=C3 write is fatal like every other configuration NACK.
                if (transaction_addr == 16'h0003 &&
                    (transaction_owner_tx ? !tx_probe_done : !rx_probe_done))
                    startup_retry_seen <= 1'b1;
                else
                    config_error <= 1'b1;
            end
        end
    end

    // I2C SDA is open-drain: drive low or release; never source a logic high.
    assign sda = (sda_out_en && !sda_out) ? 1'b0 : 1'bz;
    assign ack_error = bus_ack_error;
endmodule

`default_nettype wire
