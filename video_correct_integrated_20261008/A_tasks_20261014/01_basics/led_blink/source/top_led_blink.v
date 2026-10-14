`timescale 1ns / 1ps

module top_led_blink #(
    parameter [23:0] CNT_MAX = 24'd13_499_999
)(
    input  wire clk_27m,
    output wire led0
);

    reg [23:0] count  = 24'd0;
    reg        led0_r = 1'b0;

    always @(posedge clk_27m) begin
        if (count == CNT_MAX) begin
            count  <= 24'd0;
            led0_r <= ~led0_r;
        end
        else begin
            count <= count + 1'b1;
        end
    end

    assign led0 = led0_r;

endmodule