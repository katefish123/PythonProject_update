`timescale 1ns/1ps
`default_nettype none

// Standalone HDMI link probe. The TX pattern and timing do not depend on the
// RX input, frame processor, or DDR. The RX pins are observed only for status.
module hdmi_link_i2c_probe_top (
    input  wire        sys_clk_27m,
    input  wire        rst_n,
    input  wire        hd_rx_pclk,
    input  wire        hd_rx_vs,
    input  wire        hd_rx_hs,
    input  wire        hd_rx_de,
    input  wire [23:0] hd_rx_data,
    output wire        hd_tx_pclk,
    output reg         hd_tx_vs,
    output reg         hd_tx_hs,
    output reg         hd_tx_de,
    output reg  [23:0] hd_tx_data,
    output wire        hd_reset_n,
    output wire        hd_scl,
    inout  wire        hd_sda,
    output wire [7:0]  led
);
    wire pix_clk, cfg_clk, pix_lock, cfg_lock;
    video_pll_27m_148m5 vp(.clkin1(sys_clk_27m), .clkout0(pix_clk), .lock(pix_lock));
    config_pll_27m_10m cp(.clkin1(sys_clk_27m), .clkout0(cfg_clk), .lock(cfg_lock));

    wire clocks_ready = rst_n && pix_lock && cfg_lock;
    wire cfg_rst_n, pix_rst_n, rx_rst_n, sys_rst_n;
    reset_sync cfg_reset(.clk(cfg_clk), .arst_n(clocks_ready), .rst_n(cfg_rst_n));
    reset_sync pix_reset(.clk(pix_clk), .arst_n(clocks_ready), .rst_n(pix_rst_n));
    reset_sync rx_reset (.clk(hd_rx_pclk), .arst_n(clocks_ready), .rst_n(rx_rst_n));
    reset_sync sys_reset(.clk(sys_clk_27m), .arst_n(clocks_ready), .rst_n(sys_rst_n));

    reg [13:0] reset_count;
    always @(posedge cfg_clk or negedge cfg_rst_n) begin
        if (!cfg_rst_n) reset_count <= 14'd0;
        else if (reset_count < 14'd10000) reset_count <= reset_count + 1'b1;
    end
    assign hd_reset_n = cfg_rst_n && (reset_count == 14'd10000);

    wire rx_done, tx_done, ack_error;
    wire first_nack_valid, first_nack_write, first_nack_owner_tx, first_nack_scl;
    wire [7:0] first_nack_device;
    wire [15:0] first_nack_addr;
    wire [2:0] first_nack_state;
    wire [4:0] first_nack_byte;
    wire [1:0] first_nack_sda_code;
    hdmi_config_diag #(.TX_FIRST(1'b1)) config_bus (
        .cfg_clk(cfg_clk), .reset_n(hd_reset_n), .rx_done(rx_done), .tx_done(tx_done),
        .scl(hd_scl), .sda(hd_sda), .ack_error(ack_error),
        .first_nack_valid(first_nack_valid), .first_nack_device(first_nack_device),
        .first_nack_addr(first_nack_addr), .first_nack_state(first_nack_state),
        .first_nack_byte(first_nack_byte), .first_nack_write(first_nack_write),
        .first_nack_owner_tx(first_nack_owner_tx), .first_nack_sda_code(first_nack_sda_code),
        .first_nack_scl(first_nack_scl)
    );

    // Source synchronous RX capture. These registers do not feed the TX path.
    reg rx_vs_q, rx_hs_q, rx_de_q;
    reg [23:0] rx_rgb_q;
    always @(posedge hd_rx_pclk or negedge rx_rst_n) begin
        if (!rx_rst_n) begin
            rx_vs_q <= 1'b0;
            rx_hs_q <= 1'b0;
            rx_de_q <= 1'b0;
            rx_rgb_q <= 24'd0;
        end else begin
            rx_vs_q <= hd_rx_vs;
            rx_hs_q <= hd_rx_hs;
            rx_de_q <= hd_rx_de;
            rx_rgb_q <= hd_rx_data;
        end
    end

    // Measure the last complete DE line width and count HS pulses since the
    // most recent VS edge (or reset). The displayed height counter also
    // advances without VS, so missing VS cannot look like missing RX clock/DE.
    reg rx_de_seen, rx_de_prev, rx_hs_prev, rx_vs_prev;
    reg [15:0] line_pixels, line_count;
    reg [15:0] rx_width, rx_height;
    reg [23:0] rx_sample_rgb;
    always @(posedge hd_rx_pclk or negedge rx_rst_n) begin
        if (!rx_rst_n) begin
            rx_de_seen <= 1'b0;
            rx_de_prev <= 1'b0;
            rx_hs_prev <= 1'b0;
            rx_vs_prev <= 1'b0;
            line_pixels <= 16'd0;
            line_count <= 16'd0;
            rx_width <= 16'd0;
            rx_height <= 16'd0;
            rx_sample_rgb <= 24'd0;
        end else begin
            rx_de_prev <= rx_de_q;
            rx_hs_prev <= rx_hs_q;
            rx_vs_prev <= rx_vs_q;
            if (rx_de_q) begin
                rx_de_seen <= 1'b1;
                line_pixels <= line_pixels + 1'b1;
                rx_sample_rgb <= rx_rgb_q;
            end
            if (!rx_de_q && rx_de_prev) begin
                rx_width <= line_pixels;
                line_pixels <= 16'd0;
            end
            if (rx_hs_q && !rx_hs_prev && line_count != 16'hffff) begin
                line_count <= line_count + 1'b1;
                rx_height <= line_count + 1'b1;
            end
            if (rx_vs_q && !rx_vs_prev) begin
                rx_height <= line_count;
                line_count <= 16'd0;
            end
        end
    end

    // RX clock presence is observed in the 27 MHz domain using a divided
    // source-clock toggle, avoiding a high-rate asynchronous sampler.
    reg [7:0] rx_alive_div;
    reg rx_alive_toggle;
    always @(posedge hd_rx_pclk or negedge rx_rst_n) begin
        if (!rx_rst_n) begin
            rx_alive_div <= 8'd0;
            rx_alive_toggle <= 1'b0;
        end else if (rx_alive_div == 8'hff) begin
            rx_alive_div <= 8'd0;
            rx_alive_toggle <= ~rx_alive_toggle;
        end else rx_alive_div <= rx_alive_div + 1'b1;
    end

    (* ASYNC_REG = "TRUE" *) reg [2:0] alive_sync, de_sync, rx_done_sync, tx_done_sync, ack_sync;
    reg rxclock_seen;
    reg alive_seen_q;
    reg [25:0] heartbeat;
    always @(posedge sys_clk_27m or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            alive_sync <= 3'b000;
            de_sync <= 3'b000;
            rx_done_sync <= 3'b000;
            tx_done_sync <= 3'b000;
            ack_sync <= 3'b000;
            alive_seen_q <= 1'b0;
            rxclock_seen <= 1'b0;
            heartbeat <= 26'd0;
        end else begin
            alive_sync <= {alive_sync[1:0], rx_alive_toggle};
            de_sync <= {de_sync[1:0], rx_de_seen};
            rx_done_sync <= {rx_done_sync[1:0], rx_done};
            tx_done_sync <= {tx_done_sync[1:0], tx_done};
            ack_sync <= {ack_sync[1:0], ack_error};
            heartbeat <= heartbeat + 1'b1;
            alive_seen_q <= alive_sync[2];
            if (alive_sync[2] != alive_seen_q) rxclock_seen <= 1'b1;
        end
    end

    // The full status word is captured at each TX VS rising edge, then held
    // for the entire frame so asynchronous RX/I2C measurements cannot tear.
    (* ASYNC_REG = "TRUE" *) reg [15:0] rx_width_meta, rx_width_pix;
    (* ASYNC_REG = "TRUE" *) reg [15:0] rx_height_meta, rx_height_pix;
    (* ASYNC_REG = "TRUE" *) reg [23:0] rx_sample_meta, rx_sample_pix;
    (* ASYNC_REG = "TRUE" *) reg [2:0] rxclock_pix_sync, de_pix_sync, ack_pix_sync;
    (* ASYNC_REG = "TRUE" *) reg [2:0] rx_done_pix_sync, tx_done_pix_sync, nack_valid_pix_sync;
    (* ASYNC_REG = "TRUE" *) reg [7:0] nack_device_meta, nack_device_pix;
    (* ASYNC_REG = "TRUE" *) reg [15:0] nack_addr_meta, nack_addr_pix;
    (* ASYNC_REG = "TRUE" *) reg [2:0] nack_state_meta, nack_state_pix;
    (* ASYNC_REG = "TRUE" *) reg [4:0] nack_byte_meta, nack_byte_pix;
    (* ASYNC_REG = "TRUE" *) reg nack_write_meta, nack_write_pix, nack_owner_meta, nack_owner_pix;
    (* ASYNC_REG = "TRUE" *) reg [1:0] nack_sda_meta, nack_sda_pix;
    (* ASYNC_REG = "TRUE" *) reg nack_scl_meta, nack_scl_pix;
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            rx_width_meta <= 16'd0; rx_width_pix <= 16'd0;
            rx_height_meta <= 16'd0; rx_height_pix <= 16'd0;
            rx_sample_meta <= 24'd0; rx_sample_pix <= 24'd0;
            rxclock_pix_sync <= 3'b000; de_pix_sync <= 3'b000;
            ack_pix_sync <= 3'b000; rx_done_pix_sync <= 3'b000;
            tx_done_pix_sync <= 3'b000; nack_valid_pix_sync <= 3'b000;
            nack_device_meta <= 8'd0; nack_device_pix <= 8'd0;
            nack_addr_meta <= 16'd0; nack_addr_pix <= 16'd0;
            nack_state_meta <= 3'd0; nack_state_pix <= 3'd0;
            nack_byte_meta <= 5'd0; nack_byte_pix <= 5'd0;
            nack_write_meta <= 1'b0; nack_write_pix <= 1'b0;
            nack_owner_meta <= 1'b0; nack_owner_pix <= 1'b0;
            nack_sda_meta <= 2'b0; nack_sda_pix <= 2'b0;
            nack_scl_meta <= 1'b0; nack_scl_pix <= 1'b0;
        end else begin
            rx_width_meta <= rx_width; rx_width_pix <= rx_width_meta;
            rx_height_meta <= rx_height; rx_height_pix <= rx_height_meta;
            rx_sample_meta <= rx_sample_rgb; rx_sample_pix <= rx_sample_meta;
            rxclock_pix_sync <= {rxclock_pix_sync[1:0], rxclock_seen};
            de_pix_sync <= {de_pix_sync[1:0], de_sync[2]};
            ack_pix_sync <= {ack_pix_sync[1:0], ack_sync[2]};
            rx_done_pix_sync <= {rx_done_pix_sync[1:0], rx_done_sync[2]};
            tx_done_pix_sync <= {tx_done_pix_sync[1:0], tx_done_sync[2]};
            nack_valid_pix_sync <= {nack_valid_pix_sync[1:0], first_nack_valid};
            nack_device_meta <= first_nack_device; nack_device_pix <= nack_device_meta;
            nack_addr_meta <= first_nack_addr; nack_addr_pix <= nack_addr_meta;
            nack_state_meta <= first_nack_state; nack_state_pix <= nack_state_meta;
            nack_byte_meta <= first_nack_byte; nack_byte_pix <= nack_byte_meta;
            nack_write_meta <= first_nack_write; nack_write_pix <= nack_write_meta;
            nack_owner_meta <= first_nack_owner_tx; nack_owner_pix <= nack_owner_meta;
            nack_sda_meta <= first_nack_sda_code; nack_sda_pix <= nack_sda_meta;
            nack_scl_meta <= first_nack_scl; nack_scl_pix <= nack_scl_meta;
        end
    end

    wire [98:0] status_payload_pix = {
        tx_done_pix_sync[2], rx_done_pix_sync[2], ack_pix_sync[2], nack_valid_pix_sync[2],
        nack_device_pix, nack_addr_pix, nack_state_pix, nack_byte_pix,
        nack_write_pix, nack_owner_pix, nack_sda_pix, nack_scl_pix,
        rxclock_pix_sync[2], de_pix_sync[2], rx_width_pix, rx_height_pix, rx_sample_pix
    };
    wire [119:0] status_word_pix = {status_payload_pix, 21'd0};

    wire [11:0] h_count, v_count;
    wire raw_hs, raw_vs, raw_de;
    video_timing_vtc #(
        .H_SYNC(12'd44), .H_BACK(12'd148), .H_ACTIVE(12'd1920), .H_FRONT(12'd88),
        .V_SYNC(12'd5), .V_BACK(12'd36), .V_ACTIVE(12'd1080), .V_FRONT(12'd4)
    ) timing (
        .clk(pix_clk), .rst_n(pix_rst_n), .h_cnt(h_count), .v_cnt(v_count),
        .hsync(raw_hs), .vsync(raw_vs), .de(raw_de)
    );

    wire [11:0] active_x = h_count - 12'd192;
    wire [11:0] active_y = v_count - 12'd41;
    reg raw_vs_prev;
    reg [119:0] status_frame_pix;
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            raw_vs_prev <= 1'b0;
            status_frame_pix <= 120'd0;
        end else begin
            raw_vs_prev <= raw_vs;
            if (raw_vs && !raw_vs_prev) status_frame_pix <= status_word_pix;
        end
    end
    wire [3:0] status_column = active_x / 12'd128;
    wire [2:0] status_row = (active_y - 12'd1000) / 12'd10;
    wire [6:0] status_index = 7'd119 - (status_row * 7'd15) - status_column;
    wire status_on = status_frame_pix[status_index];
    wire [23:0] bar_rgb = (active_x < 12'd480)  ? 24'hff0000 :
                          (active_x < 12'd960)  ? 24'h00ff00 :
                          (active_x < 12'd1440) ? 24'h0000ff : 24'hffffff;
    wire status_area = raw_de && active_y >= 12'd1000;
    wire [23:0] raw_rgb = status_area ? (status_on ? 24'h00b000 : 24'hb00000) : bar_rgb;

    // Final launch registers capture RGB and all qualifiers on the same edge.
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if (!pix_rst_n) begin
            hd_tx_vs <= 1'b0;
            hd_tx_hs <= 1'b0;
            hd_tx_de <= 1'b0;
            hd_tx_data <= 24'd0;
        end else begin
            hd_tx_vs <= raw_vs;
            hd_tx_hs <= raw_hs;
            hd_tx_de <= raw_de;
            hd_tx_data <= raw_de ? raw_rgb : 24'd0;
        end
    end
    assign hd_tx_pclk = pix_clk;

    assign led = {
        alive_seen_q | rxclock_seen, ack_sync[2], de_sync[2], tx_done_sync[2],
        rx_done_sync[2], cfg_lock, pix_lock, heartbeat[24]
    };
endmodule

`default_nettype wire
