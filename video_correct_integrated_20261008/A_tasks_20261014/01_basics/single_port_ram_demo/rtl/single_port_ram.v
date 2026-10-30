module single_port_ram (
    input  wire       clk,
    input  wire       we,
    input  wire [3:0] addr,
    input  wire [7:0] din,
    output reg  [7:0] dout
);

    // 16 words, 8 bits per word. No initialization or reset.
    reg [7:0] mem [0:15];

    // Synchronous read/write. Output holds its value during writes.
    always @(posedge clk) begin
        if (we) begin
            mem[addr] <= din;
        end else begin
            dout <= mem[addr];
        end
    end

endmodule
