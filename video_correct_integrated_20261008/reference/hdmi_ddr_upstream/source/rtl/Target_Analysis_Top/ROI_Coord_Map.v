module ROI_Coord_Map #(
    parameter PROC_WIDTH  = 1920,
    parameter PROC_HEIGHT = 1080,
    parameter SRC_WIDTH   = 1920,
    parameter SRC_HEIGHT  = 1080,
    parameter X_BITS      = 12,
    parameter Y_BITS      = 12
)(
    input  wire                 clk,
    input  wire                 rst_n,

    input  wire                 roi_valid_in,
    input  wire [X_BITS-1:0]    roi_x1_in,
    input  wire [Y_BITS-1:0]    roi_y1_in,
    input  wire [X_BITS-1:0]    roi_x2_in,
    input  wire [Y_BITS-1:0]    roi_y2_in,

    output reg                  roi_valid_out,
    output reg [X_BITS-1:0]     roi_x1_out,
    output reg [Y_BITS-1:0]     roi_y1_out,
    output reg [X_BITS-1:0]     roi_x2_out,
    output reg [Y_BITS-1:0]     roi_y2_out
);

    integer x1_map, y1_map, x2_map, y2_map;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            roi_valid_out <= 1'b0;
            roi_x1_out    <= {X_BITS{1'b0}};
            roi_y1_out    <= {Y_BITS{1'b0}};
            roi_x2_out    <= {X_BITS{1'b0}};
            roi_y2_out    <= {Y_BITS{1'b0}};
        end
        else begin
            roi_valid_out <= roi_valid_in;

            x1_map = (roi_x1_in * SRC_WIDTH ) / PROC_WIDTH;
            y1_map = (roi_y1_in * SRC_HEIGHT) / PROC_HEIGHT;
            x2_map = ((roi_x2_in + 1) * SRC_WIDTH ) / PROC_WIDTH - 1;
            y2_map = ((roi_y2_in + 1) * SRC_HEIGHT) / PROC_HEIGHT - 1;

            if(x1_map < 0) x1_map = 0;
            if(y1_map < 0) y1_map = 0;
            if(x2_map >= SRC_WIDTH ) x2_map = SRC_WIDTH -1;
            if(y2_map >= SRC_HEIGHT) y2_map = SRC_HEIGHT-1;

            roi_x1_out <= x1_map[X_BITS-1:0];
            roi_y1_out <= y1_map[Y_BITS-1:0];
            roi_x2_out <= x2_map[X_BITS-1:0];
            roi_y2_out <= y2_map[Y_BITS-1:0];
        end
    end

endmodule