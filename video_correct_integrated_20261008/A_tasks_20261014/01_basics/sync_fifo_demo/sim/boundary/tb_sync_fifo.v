`timescale 1ns/1ps
module tb_sync_fifo;
    reg clk = 0;
    always #5 clk = ~clk; // Simulation clock only; not a board constraint.
    reg rst_n = 1;
    reg wr_en = 0, rd_en = 0;
    reg [7:0] din = 0;
    wire [7:0] dout;
    wire full, empty;
    wire [4:0] count;
    sync_fifo dut (.clk(clk), .rst_n(rst_n), .wr_en(wr_en),
        .din(din), .rd_en(rd_en), .dout(dout), .full(full),
        .empty(empty), .count(count));

    // Independent queue model: no DUT pointers or memory used.
    reg [7:0] expected [0:8191];
    reg [7:0] expected_dout;
    integer head = 0, tail = 0, occupancy = 0;
    integer errors = 0, checks = 0, i;
    integer seed = 1004;
    reg accept_read, accept_write;

    task check_outputs;
    begin
        checks = checks + 1;
        if (count !== occupancy || empty !== (occupancy == 0) ||
            full !== (occupancy == 16) || dout !== expected_dout) begin
            errors = errors + 1;
            $display("FAIL t=%0t count=%0d expected=%0d dout=%h expected=%h full=%b empty=%b",
                $time, count, occupancy, dout, expected_dout, full, empty);
        end
    end
    endtask

    task reset_fifo;
    begin
        @(negedge clk);
        rst_n = 0; wr_en = 0; rd_en = 0; din = 0;
        head = 0; tail = 0; occupancy = 0; expected_dout = 0;
        #1; check_outputs;
        @(negedge clk); rst_n = 1;
    end
    endtask

    task cycle;
        input w;
        input r;
        input [7:0] data;
    begin
        @(negedge clk);
        wr_en = w; rd_en = r; din = data;
        accept_read = r && (occupancy > 0);
        accept_write = w && (occupancy < 16);
        @(posedge clk);
        if (accept_read) begin
            expected_dout = expected[head]; head = head + 1;
        end
        if (accept_write) begin
            expected[tail] = data; tail = tail + 1;
        end
        case ({accept_write, accept_read})
            2'b10: occupancy = occupancy + 1;
            2'b01: occupancy = occupancy - 1;
        endcase
        #1; check_outputs;
    end
    endtask

    initial begin
        reset_fifo;
        $display("TEST: empty read and simultaneous requests at empty");
        cycle(0, 1, 0);
        cycle(1, 1, 8'hA5);
        cycle(0, 1, 0);
        $display("TEST: fill, rejected write, simultaneous requests at full");
        for (i = 0; i < 16; i = i + 1) cycle(1, 0, i);
        cycle(1, 0, 8'hFF);
        cycle(1, 1, 8'hEE);
        for (i = 0; i < 15; i = i + 1) cycle(0, 1, 0);
        cycle(0, 1, 0);
        $display("TEST: simultaneous read/write and pointer wrapping");
        for (i = 0; i < 8; i = i + 1) cycle(1, 0, i + 32);
        for (i = 0; i < 64; i = i + 1) cycle(1, 1, i + 64);
        for (i = 0; i < 8; i = i + 1) cycle(0, 1, 0);
        $display("TEST: reset with queued data");
        cycle(1, 0, 8'h12); cycle(1, 0, 8'h34);
        reset_fifo;
        cycle(0, 1, 0);
        $display("TEST: 1000 randomized cycles");
        for (i = 0; i < 1000; i = i + 1)
            cycle(($random(seed) & 1), ($random(seed) & 1), $random(seed));
        while (occupancy > 0) cycle(0, 1, 0);
        cycle(0, 0, 0);
        if (errors == 0) $display("PASS: %0d checks", checks);
        else $display("FAIL: %0d errors / %0d checks", errors, checks);
        $finish;
    end
    initial begin
        #200000;
        $display("FAIL: simulation timeout");
        $finish;
    end
endmodule
