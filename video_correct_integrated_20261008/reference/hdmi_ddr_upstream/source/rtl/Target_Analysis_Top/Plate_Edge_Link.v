module Plate_Edge_Link #(
    parameter LINK_LEN = 5
)(
    input  wire clk,
    input  wire rst_n,
    input  wire vs_in,
    input  wire de_in,
    input  wire edge_bin_in,

    output reg  vs_out,
    output reg  de_out,
    output reg  edge_bin_out
);

    reg [LINK_LEN-1:0] edge_shift;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            edge_shift   <= {LINK_LEN{1'b0}};
            vs_out       <= 1'b0;
            de_out       <= 1'b0;
            edge_bin_out <= 1'b0;
        end
        else begin
            vs_out <= vs_in;
            de_out <= de_in;

            if(de_in) begin
                edge_shift   <= {edge_shift[LINK_LEN-2:0], edge_bin_in};
                edge_bin_out <= |{edge_shift[LINK_LEN-2:0], edge_bin_in};
            end
            else begin
                edge_shift   <= {LINK_LEN{1'b0}};
                edge_bin_out <= 1'b0;
            end
        end
    end

endmodule
