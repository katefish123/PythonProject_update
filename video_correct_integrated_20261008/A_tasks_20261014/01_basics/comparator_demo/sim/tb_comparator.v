`timescale 1ns/1ps

module tb_comparator;
    reg  [7:0] a;
    reg  [7:0] b;
    wire       gt;
    wire       eq;
    wire       lt;

    integer i;
    integer j;
    integer errors;
    integer checks;
    reg [2:0] expected;

    comparator dut (
        .a(a), .b(b), .gt(gt), .eq(eq), .lt(lt)
    );

    // Explicit expected values provide easily inspected waveform examples.
    task check_case;
        input [7:0] test_a;
        input [7:0] test_b;
        input [2:0] result;
        begin
            a = test_a;
            b = test_b;
            #10;
            checks = checks + 1;
            if ({gt, eq, lt} !== result) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("FAIL a=%d b=%d actual=%b expected=%b",
                             a, b, {gt, eq, lt}, result);
            end
        end
    endtask

    initial begin
        a = 0;
        b = 0;
        errors = 0;
        checks = 0;

        check_case(8'd0,   8'd0,   3'b010);
        check_case(8'd10,  8'd20,  3'b001);
        check_case(8'd20,  8'd10,  3'b100);
        check_case(8'd100, 8'd100, 3'b010);
        check_case(8'd0,   8'd255, 3'b001);
        check_case(8'd255, 8'd0,   3'b100);
        check_case(8'd128, 8'd127, 3'b100);
        check_case(8'd127, 8'd128, 3'b001);

        // Independent ordering oracle based on integer subtraction.
        for (i = 0; i < 256; i = i + 1) begin
            for (j = 0; j < 256; j = j + 1) begin
                if ((i - j) > 0)
                    expected = 3'b100;
                else if ((i - j) == 0)
                    expected = 3'b010;
                else
                    expected = 3'b001;
                check_case(i, j, expected);
            end
        end

        if (errors == 0)
            $display("PASS: comparator, %0d checks, 0 errors.", checks);
        else
            $display("FAIL: comparator, %0d checks, %0d errors.", checks, errors);
        $finish;
    end
endmodule
