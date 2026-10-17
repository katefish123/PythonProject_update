`timescale 1ns/1ps

module tb_counter_en_rst;

    reg        clk;
    reg        rst_n;
    reg        en;
    wire [7:0] count;

    counter_en_rst u_counter_en_rst (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (en),
        .count (count)
    );

    // 100 MHz simulation clock: 10 ns period.
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        en    = 1'b0;

        #20;
        rst_n = 1'b1;  // Release reset; counter stays at zero because en=0.

        #20;
        en = 1'b1;     // Start counting.

        #100;
        en = 1'b0;     // Hold current count.

        #40;
        en = 1'b1;     // Resume counting.

        #60;
        rst_n = 1'b0;  // Reset counter to zero again.

        #20;
        rst_n = 1'b1;

        #40;
        $finish;
    end

endmodule
