`timescale 1ns/1ps
module tb_fifo_ip_basic;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 1;
    reg wr_en = 0, rd_en = 0;
    reg [7:0] din = 0;
    wire [7:0] dout;
    wire full, empty, almost_full, almost_empty;
    wire [9:0] wr_water_level, rd_water_level;
    integer errors = 0;
    integer i;

    // Required by the official Pango memory simulation model.
    GTP_GRS GRS_INST (.GRS_N(1'b1));
    fifo_ip_top dut (
        .clk(clk), .rst_n(rst_n), .wr_en(wr_en), .din(din),
        .rd_en(rd_en), .dout(dout), .full(full), .empty(empty),
        .wr_water_level(wr_water_level), .rd_water_level(rd_water_level),
        .almost_full(almost_full), .almost_empty(almost_empty)
    );

    task check_count;
        input integer expected;
    begin
        if (wr_water_level !== expected || rd_water_level !== expected ||
            empty !== (expected == 0) || full !== (expected == 512)) begin
            errors = errors + 1;
            $display("FAIL count t=%0t wr=%0d rd=%0d expected=%0d empty=%b full=%b",
                $time, wr_water_level, rd_water_level, expected, empty, full);
        end
    end
    endtask

    initial begin
        @(negedge clk); rst_n = 0;
        repeat (3) @(posedge clk);
        #1; check_count(0);
        if (dout !== 8'h00) begin
            errors = errors + 1;
            $display("FAIL reset data: %h", dout);
        end
        @(negedge clk); rst_n = 1;
        repeat (2) @(posedge clk);
        #1; check_count(0);

        $display("IP_BASIC: write 11,22,33,44 (hex)");
        for (i = 1; i <= 4; i = i + 1) begin
            @(negedge clk); wr_en = 1; din = i * 8'h11;
            @(posedge clk); #1; check_count(i);
        end
        @(negedge clk); wr_en = 0; din = 0;
        repeat (2) @(posedge clk);
        #1; check_count(4);

        $display("IP_BASIC: read 11,22,33,44 (hex)");
        for (i = 1; i <= 4; i = i + 1) begin
            @(negedge clk); rd_en = 1;
            @(posedge clk); #1;
            check_count(4-i);
            if (dout !== (i * 8'h11)) begin
                errors = errors + 1;
                $display("FAIL data t=%0t got=%h expected=%h", $time, dout, i * 8'h11);
            end
        end
        @(negedge clk); rd_en = 0;
        repeat (2) @(posedge clk);
        #1; check_count(0);
        if (errors == 0) $display("PASS: Pango FIFO IP basic, 0 errors");
        else $display("FAIL: Pango FIFO IP basic, %0d errors", errors);
        $finish;
    end
    initial begin
        #5000;
        $display("FAIL: Pango FIFO IP basic timeout");
        $finish;
    end
endmodule
