// 8-bit counter with active-low asynchronous reset and enable control.
module counter_en_rst (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    output reg  [7:0] count
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            count <= 8'd0;
        else if (en)
            count <= count + 8'd1;
    end

endmodule
