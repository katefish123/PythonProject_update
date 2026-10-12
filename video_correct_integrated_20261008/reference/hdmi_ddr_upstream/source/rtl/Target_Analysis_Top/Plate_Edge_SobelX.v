module Plate_Edge_SobelX #(
    parameter IMG_WIDTH = 1920,
    parameter IMG_HEIGHT = 1080,
    parameter EDGE_TH   = 80,
    parameter WEAK_EDGE_TH = 56,
    parameter DARK_Y_TH = 96
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       vs_in,
    input  wire       de_in,
    input  wire [7:0] y_in,

    output reg        vs_out,
    output reg        de_out,
    output reg        edge_bin_out
);

    wire       matrix_vs;
    wire       matrix_de;
    wire [7:0] matrix11;
    wire [7:0] matrix12;
    wire [7:0] matrix13;
    wire [7:0] matrix21;
    wire [7:0] matrix22;
    wire [7:0] matrix23;
    wire [7:0] matrix31;
    wire [7:0] matrix32;
    wire [7:0] matrix33;

    reg        matrix_vs_d0;
    reg        matrix_de_d0;

    wire [10:0] gx_left;
    wire [10:0] gx_right;
    wire signed [11:0] gx_diff;
    wire [11:0] gx_abs;
    wire [10:0] gy_top;
    wire [10:0] gy_bottom;
    wire signed [11:0] gy_diff;
    wire [11:0] gy_abs;
    wire [12:0] edge_sum;

    matrix_3x3 #(
        .IMG_WIDTH  (IMG_WIDTH),
        .IMG_HEIGHT (IMG_HEIGHT)
    ) u_matrix_3x3_sobel (
        .video_clk  (clk),
        .rst_n      (rst_n),
        .video_vs   (vs_in),
        .video_de   (de_in),
        .video_data (y_in),

        .matrix_de  (matrix_de),
        .matrix_vs  (matrix_vs),
        .matrix11   (matrix11),
        .matrix12   (matrix12),
        .matrix13   (matrix13),
        .matrix21   (matrix21),
        .matrix22   (matrix22),
        .matrix23   (matrix23),
        .matrix31   (matrix31),
        .matrix32   (matrix32),
        .matrix33   (matrix33)
    );

    assign gx_left  = matrix11 + {matrix21, 1'b0} + matrix31;
    assign gx_right = matrix13 + {matrix23, 1'b0} + matrix33;
    assign gx_diff  = $signed({1'b0, gx_right}) - $signed({1'b0, gx_left});
    assign gx_abs   = gx_diff[11] ? (~gx_diff + 12'd1) : gx_diff[11:0];
    assign gy_top    = matrix11 + {matrix12, 1'b0} + matrix13;
    assign gy_bottom = matrix31 + {matrix32, 1'b0} + matrix33;
    assign gy_diff   = $signed({1'b0, gy_bottom}) - $signed({1'b0, gy_top});
    assign gy_abs    = gy_diff[11] ? (~gy_diff + 12'd1) : gy_diff[11:0];
    assign edge_sum  = {1'b0, gx_abs} + {1'b0, gy_abs};

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            matrix_vs_d0 <= 1'b0;
            matrix_de_d0 <= 1'b0;
            vs_out       <= 1'b0;
            de_out       <= 1'b0;
            edge_bin_out <= 1'b0;
        end
        else begin
            matrix_vs_d0 <= matrix_vs;
            matrix_de_d0 <= matrix_de;

            vs_out <= matrix_vs_d0;
            de_out <= matrix_de_d0;

            if(matrix_de_d0)
                edge_bin_out <= (edge_sum >= EDGE_TH) ||
                                ((matrix22 <= DARK_Y_TH) && (edge_sum >= WEAK_EDGE_TH));
            else
                edge_bin_out <= 1'b0;
        end
    end

endmodule
