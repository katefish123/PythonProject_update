`timescale 1ns/1ps
// Stage 1: reset, four writes, then four reads. No boundary tests.
module tb_fifo_basic;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 1;
    reg wr_en = 0;
    reg rd_en = 0;
    reg [7:0] din = 0;
    wire [7:0] dout;
    wire full, empty;
    wire [4:0] count;
    integer errors = 0;
    integer i;

    sync_fifo dut (
        .clk(clk), .rst_n(rst_n), .wr_en(wr_en), .rd_en(rd_en),
        .din(din), .dout(dout), .full(full), .empty(empty), .count(count)
    );

    task check_state;
        input [4:0] expected_count;
        input [7:0] expected_data;
    begin
        if (count !== expected_count || dout !== expected_data ||
            empty !== (expected_count == 0) || full !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL t=%0t count=%0d expected=%0d dout=%h expected=%h",
                $time, count, expected_count, dout, expected_data);
        end
    end
    endtask

    initial begin
        // Drive inputs on falling edges; inspect after rising-edge updates.
        @(negedge clk); rst_n = 0;
        @(posedge clk); #1; check_state(0, 0);
        @(negedge clk); rst_n = 1;
        @(posedge clk); #1; check_state(0, 0);

        $display("BASIC: write 11, 22, 33, 44 (hex)");
        for (i = 1; i <= 4; i = i + 1) begin
            @(negedge clk); wr_en = 1; din = i * 8'h11;
            @(posedge clk); #1; check_state(i, 0);
        end
        @(negedge clk); wr_en = 0; din = 0;
        repeat (2) begin
            @(posedge clk); #1; check_state(4, 0);
        end

        $display("BASIC: read 11, 22, 33, 44 (hex)");
        for (i = 1; i <= 4; i = i + 1) begin
            @(negedge clk); rd_en = 1;
            @(posedge clk); #1; check_state(4-i, i * 8'h11);
        end
        @(negedge clk); rd_en = 0;
        repeat (2) begin
            @(posedge clk); #1; check_state(0, 8'h44);
        end
        if (errors == 0) $display("PASS: basic FIFO simulation");
        else $display("FAIL: basic FIFO simulation, %0d errors", errors);
        $finish;
    end
    initial begin
        #5000;
        $display("FAIL: basic simulation timeout");
        $finish;
    end
endmodule
