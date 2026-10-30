`timescale 1ns / 1ps

module run_segment_detect #(
    parameter IMG_WIDTH   = 1920,
    parameter IMG_HEIGHT  = 1080,
    parameter X_BITS      = 12,
    parameter Y_BITS      = 12,
    parameter RUN_MIN_LEN = 12
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  bin_vsync,
    input  wire                  bin_de,
    input  wire                  color_hit_in,
    input  wire                  edge_hit_in,

    output reg                   run_valid,
    output reg  [X_BITS-1:0]     run_x1,
    output reg  [X_BITS-1:0]     run_x2,
    output reg  [Y_BITS-1:0]     run_y,
    output reg  [X_BITS-1:0]     run_width,
    output reg  [15:0]           run_color_count,
    output reg  [15:0]           run_edge_count,
    output reg                   frame_done
);

    reg                  bin_vsync_d;
    reg                  bin_de_d;
    reg [X_BITS-1:0]     x_cnt;
    reg [Y_BITS-1:0]     y_cnt;
    reg                  in_run;
    reg [X_BITS-1:0]     run_start_x;
    reg [X_BITS-1:0]     run_end_x;
    reg [15:0]           color_count;
    reg [15:0]           edge_count;

    wire                 frame_edge;
    wire                 line_end;
    wire [X_BITS-1:0]    current_x;
    wire [X_BITS-1:0]    current_run_width;

    localparam [X_BITS-1:0] RUN_MIN_LEN_W = RUN_MIN_LEN;

    assign frame_edge        = bin_vsync ^ bin_vsync_d;
    assign line_end          = bin_de_d && !bin_de;
    assign current_x         = bin_de_d ? x_cnt : {X_BITS{1'b0}};
    assign current_run_width = run_end_x - run_start_x + {{(X_BITS-1){1'b0}}, 1'b1};

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            bin_vsync_d     <= 1'b0;
            bin_de_d        <= 1'b0;
            x_cnt           <= {X_BITS{1'b0}};
            y_cnt           <= {Y_BITS{1'b0}};
            in_run          <= 1'b0;
            run_start_x     <= {X_BITS{1'b0}};
            run_end_x       <= {X_BITS{1'b0}};
            color_count     <= 16'd0;
            edge_count      <= 16'd0;
            run_valid       <= 1'b0;
            run_x1          <= {X_BITS{1'b0}};
            run_x2          <= {X_BITS{1'b0}};
            run_y           <= {Y_BITS{1'b0}};
            run_width       <= {X_BITS{1'b0}};
            run_color_count <= 16'd0;
            run_edge_count  <= 16'd0;
            frame_done      <= 1'b0;
        end
        else begin
            bin_vsync_d <= bin_vsync;
            bin_de_d    <= bin_de;
            run_valid   <= 1'b0;
            frame_done  <= frame_edge;

            if(frame_edge) begin
                x_cnt       <= {X_BITS{1'b0}};
                y_cnt       <= {Y_BITS{1'b0}};
                in_run      <= 1'b0;
                color_count <= 16'd0;
                edge_count  <= 16'd0;
            end
            else if(bin_de) begin
                if(!bin_de_d)
                    x_cnt <= {{(X_BITS-1){1'b0}}, 1'b1};
                else
                    x_cnt <= x_cnt + {{(X_BITS-1){1'b0}}, 1'b1};

                if(color_hit_in) begin
                    if(!in_run) begin
                        in_run      <= 1'b1;
                        run_start_x <= current_x;
                        run_end_x   <= current_x;
                        color_count <= 16'd1;
                        edge_count  <= edge_hit_in ? 16'd1 : 16'd0;
                    end
                    else begin
                        run_end_x   <= current_x;
                        if(color_count != 16'hFFFF)
                            color_count <= color_count + 1'b1;
                        if(edge_hit_in && edge_count != 16'hFFFF)
                            edge_count <= edge_count + 1'b1;
                    end
                end
                else if(in_run) begin
                    in_run <= 1'b0;
                    if(current_run_width >= RUN_MIN_LEN_W) begin
                        run_valid       <= 1'b1;
                        run_x1          <= run_start_x;
                        run_x2          <= run_end_x;
                        run_y           <= y_cnt;
                        run_width       <= current_run_width;
                        run_color_count <= color_count;
                        run_edge_count  <= edge_count;
                    end
                    color_count <= 16'd0;
                    edge_count  <= 16'd0;
                end
            end
            else if(line_end) begin
                x_cnt <= {X_BITS{1'b0}};
                if(y_cnt < (IMG_HEIGHT - 1))
                    y_cnt <= y_cnt + {{(Y_BITS-1){1'b0}}, 1'b1};
                else
                    y_cnt <= {Y_BITS{1'b0}};

                if(in_run) begin
                    in_run <= 1'b0;
                    if(current_run_width >= RUN_MIN_LEN_W) begin
                        run_valid       <= 1'b1;
                        run_x1          <= run_start_x;
                        run_x2          <= run_end_x;
                        run_y           <= y_cnt;
                        run_width       <= current_run_width;
                        run_color_count <= color_count;
                        run_edge_count  <= edge_count;
                    end
                end
                color_count <= 16'd0;
                edge_count  <= 16'd0;
            end
        end
    end

endmodule