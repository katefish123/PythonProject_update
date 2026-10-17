`timescale 1ns/1ps
// Fixed 8-bit x 16 synchronous FIFO. Requests use pre-edge flags.
module sync_fifo (
    input wire clk,
    input wire rst_n,
    input wire wr_en,
    input wire [7:0] din,
    input wire rd_en,
    output reg [7:0] dout,
    output wire full,
    output wire empty,
    output reg [4:0] count
);
    reg [7:0] mem [0:15];
    reg [3:0] wr_ptr, rd_ptr;
    wire write_ok = wr_en && !full;
    wire read_ok = rd_en && !empty;
    assign full = (count == 5'd16);
    assign empty = (count == 5'd0);

    // Memory contents need no reset: count/pointers invalidate old entries.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 4'd0;
            rd_ptr <= 4'd0;
            count <= 5'd0;
            dout <= 8'd0;
        end else begin
            if (write_ok) begin
                mem[wr_ptr] <= din;
                wr_ptr <= wr_ptr + 4'd1;
            end
            if (read_ok) begin
                dout <= mem[rd_ptr];
                rd_ptr <= rd_ptr + 4'd1;
            end
            case ({write_ok, read_ok})
                2'b10: count <= count + 5'd1;
                2'b01: count <= count - 5'd1;
                default: count <= count;
            endcase
        end
    end
endmodule
