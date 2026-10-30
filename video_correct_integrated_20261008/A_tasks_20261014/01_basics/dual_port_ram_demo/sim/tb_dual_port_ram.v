`timescale 1ns/1ps
module tb_dual_port_ram;
    reg clk;
    reg we;
    reg re;
    reg [3:0] wr_addr;
    reg [3:0] rd_addr;
    reg [7:0] din;
    wire [7:0] dout;
    integer i;
    integer errors;
    reg [7:0] expected_mem [0:15];

    dual_port_ram dut (
        .clk(clk), .we(we), .wr_addr(wr_addr), .din(din),
        .re(re), .rd_addr(rd_addr), .dout(dout)
    );
    initial clk = 0;
    always #5 clk = ~clk;

    task cycle_check;
        input write_enable;
        input read_enable;
        input [3:0] write_address;
        input [3:0] read_address;
        input [7:0] data;
        reg [7:0] held_output;
        reg [7:0] expected_output;
        begin
            @(negedge clk);
            held_output = dout;
            we = write_enable;
            re = read_enable;
            wr_addr = write_address;
            rd_addr = read_address;
            din = data;
            expected_output = read_enable ? expected_mem[read_address] : held_output;
            #1;
            if (dout !== held_output) begin
                errors = errors + 1;
                $display("FAIL: output changed before rising edge");
            end
            @(posedge clk);
            #1;
            if (dout !== expected_output) begin
                errors = errors + 1;
                $display("FAIL: re=%b rd_addr=%0d expected=%h actual=%h",
                         re, rd_addr, expected_output, dout);
            end
            if (write_enable)
                expected_mem[write_address] = data;
            $display("CHECK: we=%b re=%b wr_addr=%0d rd_addr=%0d din=%h dout=%h",
                     we, re, wr_addr, rd_addr, din, dout);
        end
    endtask

    initial begin
        we = 0;
        re = 0;
        wr_addr = 0;
        rd_addr = 0;
        din = 0;
        errors = 0;

        // 1. Initialize all locations through the write port.
        for (i = 0; i < 16; i = i + 1)
            cycle_check(1, 0, i, 0, 8'hA0 + i);

        // 2. Read back all locations.
        for (i = 0; i < 16; i = i + 1)
            cycle_check(0, 1, 0, i, 0);

        // 3. Simultaneously write and read different addresses.
        // Read the next address, wrapping 15 -> 0.
        for (i = 0; i < 16; i = i + 1)
            cycle_check(1, 1, i, (i + 1) % 16, 8'h50 + i);

        // 4. Check all newly written data.
        for (i = 0; i < 16; i = i + 1)
            cycle_check(0, 1, 0, i, 0);

        // 5. Disable reading: writes and address changes must not alter dout.
        cycle_check(1, 0, 3, 7, 8'hCC);
        cycle_check(0, 0, 0, 8, 0);
        cycle_check(0, 0, 0, 9, 0);
        cycle_check(0, 1, 0, 3, 0);

        if (errors == 0)
            $display("TEST PASS: all dual-port RAM checks passed.");
        else
            $display("TEST FAIL: %0d errors.", errors);
        $finish;
    end
endmodule
