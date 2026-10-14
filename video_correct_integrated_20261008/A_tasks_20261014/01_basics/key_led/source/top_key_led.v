`timescale 1ns / 1ps

module top_key_led(
    input  key0,
    output led0
);

    // KEY0 按下为 0；LED0 点亮需要 1
    assign led0 = ~key0;

endmodule