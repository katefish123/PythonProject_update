`timescale 1ns/1ps

module tb_hdmi_link_probe;
    reg sys_clk_27m = 1'b0;
    reg rst_n = 1'b0;
    reg hd_rx_pclk = 1'b0;
    reg hd_rx_vs = 1'b0, hd_rx_hs = 1'b0, hd_rx_de = 1'b0;
    reg [23:0] hd_rx_data = 24'd0;
    wire hd_tx_pclk, hd_tx_vs, hd_tx_hs, hd_tx_de;
    wire [23:0] hd_tx_data;
    wire hd_reset_n, hd_scl, hd_sda;
    wire [7:0] led;
    integer i;

    hdmi_link_probe_top dut(.*);
    always #5 sys_clk_27m = ~sys_clk_27m;
    always #4 hd_rx_pclk = ~hd_rx_pclk;

    initial begin
        #35 rst_n = 1'b1;
        wait (hd_reset_n === 1'b1);
        wait (led[4] === 1'b1);

        // A short source-synchronous burst exercises the RX capture and sticky
        // DE observation without affecting the autonomous TX color bars.
        @(negedge hd_rx_pclk);
        hd_rx_hs = 1'b1;
        hd_rx_de = 1'b1;
        hd_rx_data = 24'h123456;
        repeat (8) @(negedge hd_rx_pclk);
        hd_rx_de = 1'b0;
        hd_rx_hs = 1'b0;
        wait (led[5] === 1'b1);
        wait (led[7] === 1'b1);
        if (led[3] !== 1'b1 || led[4] !== 1'b1 || led[6] !== 1'b0)
            $fatal(1, "configuration/ACK LED status mismatch: %b", led);

        // Verify every pixel in the first active row and all four exact
        // 480-pixel regions, independent of RX/DDR state.
        wait (hd_tx_de === 1'b1);
        #1;
        for (i = 0; i < 1920; i = i + 1) begin
            if (hd_tx_de !== 1'b1) $fatal(1, "DE ended early at active pixel %0d", i);
            case (i / 480)
                0: if (hd_tx_data !== 24'hff0000) $fatal(1, "bar 0 is not red at %0d: %h", i, hd_tx_data);
                1: if (hd_tx_data !== 24'h00ff00) $fatal(1, "bar 1 is not green at %0d: %h", i, hd_tx_data);
                2: if (hd_tx_data !== 24'h0000ff) $fatal(1, "bar 2 is not blue at %0d: %h", i, hd_tx_data);
                3: if (hd_tx_data !== 24'hffffff) $fatal(1, "bar 3 is not white at %0d: %h", i, hd_tx_data);
            endcase
            #1;
            @(posedge hd_tx_pclk);
            #1;
        end
        if (hd_tx_de !== 1'b0) $fatal(1, "DE did not end after 1920 active pixels");
        if (hd_tx_pclk !== sys_clk_27m)
            $fatal(1, "simulation PLL forwarding model mismatch");
        $display("HDMI_LINK_PROBE_SIM_PASS led=%b exactly 1920 active pixels; four 480-pixel bar colors verified", led);
        $finish;
    end
endmodule

// Behavioral clock models keep the simulation fast. Synthesis uses the real
// Pango PLL wrappers listed by prepare_link_probe.py.
module video_pll_27m_148m5(input wire clkin1, output wire clkout0, output reg lock = 1'b0);
    reg [2:0] count = 3'd0;
    assign clkout0 = clkin1;
    always @(posedge clkin1) if (!lock) begin
        count <= count + 1'b1;
        if (count == 3'd2) lock <= 1'b1;
    end
endmodule

module config_pll_27m_10m(input wire clkin1, output wire clkout0, output reg lock = 1'b0);
    reg [2:0] count = 3'd0;
    assign clkout0 = clkin1;
    always @(posedge clkin1) if (!lock) begin
        count <= count + 1'b1;
        if (count == 3'd2) lock <= 1'b1;
    end
endmodule

// The top-level build uses the real TX-first I2C controllers. The test stub
// only supplies completed configuration status so raster timing is isolated.
module hdmi_config #(
    parameter TX_FIRST = 1'b0,
    parameter CLK_FRE = 27'd10_000_000,
    parameter IIC_FREQ = 20'd400_000
) (
    input wire cfg_clk, reset_n,
    output reg rx_done, output reg tx_done,
    output wire scl, inout wire sda, output wire ack_error
);
    reg [3:0] count;
    assign scl = 1'b1;
    assign sda = 1'bz;
    assign ack_error = 1'b0;
    always @(posedge cfg_clk or negedge reset_n) begin
        if (!reset_n) begin count <= 0; rx_done <= 0; tx_done <= 0; end
        else begin
            if (count < 4'd8) count <= count + 1'b1;
            if (count >= 4'd2) tx_done <= 1'b1;
            if (count >= 4'd6) rx_done <= 1'b1;
        end
    end
endmodule
