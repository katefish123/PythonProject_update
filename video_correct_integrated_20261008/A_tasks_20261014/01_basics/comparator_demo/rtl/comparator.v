// 8-bit unsigned combinational comparator.
// No clock or reset is required.
module comparator (
    input  wire [7:0] a,
    input  wire [7:0] b,
    output wire       gt,
    output wire       eq,
    output wire       lt
);

    assign gt = (a > b);
    assign eq = (a == b);
    assign lt = (a < b);

endmodule
