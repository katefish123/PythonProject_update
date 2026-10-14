`timescale 1ns/1ps

module tb_single_port_ram;
    reg clk;
    reg we;
    reg [3:0] addr;
    reg [7:0] din;
    wire [7:0] dout;
    integer i;
    integer errors;

    single_port_ram dut (
        .clk(clk), .we(we), .addr(addr), .din(din), .dout(dout)
    );

    // Clock period: 10 ns. Drive inputs on falling edges.
    initial clk = 1'b0;
    always #5 clk = ~clk;

    task write_word;
        input [3:0] address;
        input [7:0] data;
        reg [7:0] held_output;
        begin
            @(negedge clk);
            held_output = dout;
            we = 1'b1;
            addr = address;
            din = data;
            @(posedge clk);
            #1;
            if (dout !== held_output) begin
                errors = errors + 1;
                $display("FAIL: output changed during write, addr=%0d", address);
            end
        end
    endtask

    task read_check;
        input [3:0] address;
        input [7:0] expected;
        reg [7:0] held_output;
        begin
            @(negedge clk);
            held_output = dout;
            we = 1'b0;
            addr = address;
            #1;
            if (dout !== held_output) begin
                errors = errors + 1;
                $display("FAIL: output changed before rising edge, addr=%0d", address);
            end
            @(posedge clk);
            // Allow nonblocking assignments to settle before checking.
            #1;
            if (dout !== expected) begin
                errors = errors + 1;
                $display("FAIL: addr=%0d expected=%h actual=%h", address, expected, dout);
            end else begin
                $display("PASS: addr=%0d data=%h", address, dout);
            end
        end
    endtask

    initial begin
        we = 1'b0;
        addr = 4'd0;
        din = 8'd0;
        errors = 0;

        // Unwritten memory is intentionally unknown; initialize by writing.
        for (i = 0; i < 16; i = i + 1)
            write_word(i, 8'hA0 + i);
        for (i = 0; i < 16; i = i + 1)
            read_check(i, 8'hA0 + i);

        // Overwrite an interior address and the two boundary addresses.
        write_word(4'd3, 8'h55);
        write_word(4'd0, 8'h00);
        write_word(4'd15, 8'hFF);

        // Verify overwritten data and preservation of all other locations.
        for (i = 0; i < 16; i = i + 1) begin
            case (i)
                0: read_check(i, 8'h00);
                3: read_check(i, 8'h55);
                15: read_check(i, 8'hFF);
                default: read_check(i, 8'hA0 + i);
            endcase
        end

        if (errors == 0)
            $display("TEST PASS: all single-port RAM checks passed.");
        else
            $display("TEST FAIL: %0d errors.", errors);
        $finish;
    end
endmodule
