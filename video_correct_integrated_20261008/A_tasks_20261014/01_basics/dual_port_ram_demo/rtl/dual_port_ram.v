module dual_port_ram (
    input wire clk,
    input wire we,
    input wire [3:0] wr_addr,
    input wire [7:0] din,
    input wire re,
    input wire [3:0] rd_addr,
    output reg [7:0] dout
);
    reg [7:0] mem [0:15];

    always @(posedge clk) begin
        if (we)
            mem[wr_addr] <= din;
    end

    always @(posedge clk) begin
        if (re)
            dout <= mem[rd_addr];
    end
    // Same-address simultaneous read/write is excluded from this exercise.
    // Physical RAM collision behavior must be checked before hardware use.
endmodule
