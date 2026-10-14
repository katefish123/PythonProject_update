`timescale 1ns/1ps

module tb_mux2;
    reg  [7:0] a;
    reg  [7:0] b;
    reg        sel;
    wire [7:0] y;
    integer i;
    integer errors;

    mux2 dut (.a(a), .b(b), .sel(sel), .y(y));

    initial begin
        errors = 0;
        a = 8'h12;
        b = 8'hA5;
        sel = 0;
        #10;
        if (y !== a) errors = errors + 1;
        sel = 1;
        #10;
        if (y !== b) errors = errors + 1;

        // Sweep every byte value and check both selections.
        for (i = 0; i < 256; i = i + 1) begin
            a = i;
            b = 255 - i;
            sel = 0;
            #10;
            if (y !== a) begin
                errors = errors + 1;
                $display("FAIL sel=0 a=%h b=%h y=%h", a, b, y);
            end
            sel = 1;
            #10;
            if (y !== b) begin
                errors = errors + 1;
                $display("FAIL sel=1 a=%h b=%h y=%h", a, b, y);
            end
        end

        // Confirm changes on the unselected input do not alter y.
        a = 8'h3C;
        b = 8'h00;
        sel = 0;
        #10;
        b = 8'hFF;
        #10;
        if (y !== 8'h3C) errors = errors + 1;
        sel = 1;
        #10;
        a = 8'h00;
        #10;
        if (y !== 8'hFF) errors = errors + 1;

        if (errors == 0) $display("PASS: mux2 checks completed");
        else $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule
