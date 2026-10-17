`timescale 1ns/1ps

module rgb2ycbcr_tb;
    reg clk = 0;
    reg rst_n = 0;
    reg vsync_in = 0;
    reg hsync_in = 0;
    reg de_in = 0;
    reg [7:0] red = 0;
    reg [7:0] green = 0;
    reg [7:0] blue = 0;
    wire de_out;
    wire [7:0] y, cb, cr;

    always #3 clk = ~clk;

    RGB2YCbCr dut (
        .clk(clk), .rst_n(rst_n),
        .vsync_in(vsync_in), .hsync_in(hsync_in), .de_in(de_in),
        .red(red), .green(green), .blue(blue),
        .vsync_out(), .hsync_out(), .de_out(de_out),
        .y(y), .cb(cb), .cr(cr)
    );

    task check_pixel;
        input [7:0] r_i, g_i, b_i;
        input [7:0] y_e, cb_e, cr_e;
        begin
            @(negedge clk);
            red = r_i; green = g_i; blue = b_i; de_in = 1'b1;
            repeat (3) @(posedge clk);
            #1;
            if(!de_out || y !== y_e || cb !== cb_e || cr !== cr_e)
                $fatal(1, "RGB %0d,%0d,%0d expected %0d,%0d,%0d got %0d,%0d,%0d",
                       r_i, g_i, b_i, y_e, cb_e, cr_e, y, cb, cr);
            @(negedge clk);
            de_in = 1'b0;
            repeat (3) @(posedge clk);
            #1;
            if(de_out || y !== 0 || cb !== 0 || cr !== 0)
                $fatal(1, "outputs were not blanked by DE");
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        check_pixel(8'd0,   8'd0,   8'd0,   8'd0,   8'd128, 8'd128);
        check_pixel(8'd255, 8'd255, 8'd255, 8'd255, 8'd128, 8'd128);
        check_pixel(8'd255, 8'd0,   8'd0,   8'd76,  8'd85,  8'd255);
        check_pixel(8'd0,   8'd0,   8'd255, 8'd28,  8'd255, 8'd107);
        $display("RGB2YCBCR_PASS");
        $finish;
    end
endmodule
