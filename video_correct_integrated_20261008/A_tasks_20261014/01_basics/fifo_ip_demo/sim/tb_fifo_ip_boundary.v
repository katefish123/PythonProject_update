`timescale 1ns/1ps
module tb_fifo_ip_boundary;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 1;
    reg wr_en = 0, rd_en = 0;
    reg [7:0] din = 0;
    wire [7:0] dout;
    wire full, empty, almost_full, almost_empty;
    wire [9:0] wr_water_level, rd_water_level;
    integer errors = 0, checks = 0, i;
    integer seed = 1006;
    // Linear reference queue deliberately does not share DUT ring pointers.
    reg [7:0] expected [0:8191];
    integer head = 0, tail = 0, occupancy = 0;
    reg [7:0] expected_dout = 0;
    reg accept_write, accept_read;
    GTP_GRS GRS_INST (.GRS_N(1'b1));
    fifo_ip_top dut (
        .clk(clk), .rst_n(rst_n), .wr_en(wr_en), .din(din),
        .rd_en(rd_en), .dout(dout), .full(full), .empty(empty),
        .wr_water_level(wr_water_level), .rd_water_level(rd_water_level),
        .almost_full(almost_full), .almost_empty(almost_empty)
    );

    task check_outputs;
    begin
        checks = checks + 1;
        if (wr_water_level !== occupancy || rd_water_level !== occupancy ||
            full !== (occupancy == 512) || empty !== (occupancy == 0) ||
            almost_full !== (occupancy >= 508) ||
            almost_empty !== (occupancy <= 4) || dout !== expected_dout) begin
            errors = errors + 1;
            $display("FAIL t=%0t count=%0d wr=%0d rd=%0d data=%h expected=%h full=%b empty=%b af=%b ae=%b",
                $time, occupancy, wr_water_level, rd_water_level, dout,
                expected_dout, full, empty, almost_full, almost_empty);
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
        accept_write = w && (occupancy < 512);
        accept_read = r && (occupancy > 0);
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
        $display("IP_BOUNDARY: empty read; simultaneous requests at empty");
        cycle(0, 1, 0);
        cycle(1, 1, 8'hA5);
        cycle(0, 1, 0);
        $display("IP_BOUNDARY: fill 512; rejected write; simultaneous requests at full");
        for (i = 0; i < 512; i = i + 1) cycle(1, 0, i);
        cycle(1, 0, 8'hFF);
        cycle(1, 1, 8'hEE);
        $display("IP_BOUNDARY: drain; verify rejected values were not queued");
        for (i = 0; i < 511; i = i + 1) cycle(0, 1, 0);
        cycle(0, 1, 0);
        $display("IP_BOUNDARY: simultaneous read/write and multiple pointer wraps");
        for (i = 0; i < 8; i = i + 1) cycle(1, 0, i + 32);
        for (i = 0; i < 1100; i = i + 1) cycle(1, 1, i + 64);
        for (i = 0; i < 8; i = i + 1) cycle(0, 1, 0);
        $display("IP_BOUNDARY: reset with queued data; recovery");
        cycle(1, 0, 8'h12); cycle(1, 0, 8'h34);
        reset_fifo;
        cycle(0, 1, 0);
        $display("IP_BOUNDARY: 1000 randomized cycles");
        for (i = 0; i < 1000; i = i + 1)
            cycle(($random(seed) & 1), ($random(seed) & 1), $random(seed));
        while (occupancy > 0) cycle(0, 1, 0);
        cycle(0, 0, 0);
        if (errors == 0) $display("PASS: Pango FIFO IP boundary, %0d checks, 0 errors", checks);
        else $display("FAIL: Pango FIFO IP boundary, %0d errors", errors);
        $finish;
    end
    initial begin
        #100000;
        $display("FAIL: Pango FIFO IP boundary timeout");
        $finish;
    end
endmodule
