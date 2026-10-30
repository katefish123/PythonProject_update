`timescale 1ns / 1ps

// MES2L676-100HP / PG2L100H-6FBG676
// LED0 is active-high: logic 1 turns the LED on.
module top_led_on (
    output wire led0
);

    assign led0 = 1'b1;

endmodule
