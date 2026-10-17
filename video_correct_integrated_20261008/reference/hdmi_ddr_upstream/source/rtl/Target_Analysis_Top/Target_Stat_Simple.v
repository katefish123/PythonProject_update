module Target_Stat_Simple #(
    parameter IMG_WIDTH  = 1920,
    parameter IMG_HEIGHT = 1080,
    parameter X_BITS     = 12,
    parameter Y_BITS     = 12,
    parameter VSYNC_ACTIVE_HIGH = 1'b1
)(
    input  wire                 clk,
    input  wire                 rst_n,

    input  wire                 per_frame_vsync,
    input  wire                 per_frame_de,
    input  wire                 per_img_bin,

    output reg                  frame_done,
    output reg                  target_found,

    output reg [X_BITS-1:0]     min_x,
    output reg [Y_BITS-1:0]     min_y,
    output reg [X_BITS-1:0]     max_x,
    output reg [Y_BITS-1:0]     max_y,
    output reg [31:0]           pixel_cnt
);

    reg per_frame_vsync_d;
    reg per_frame_de_d;

    wire frame_start;
    wire frame_end;

    assign frame_start = VSYNC_ACTIVE_HIGH ?
                         (~per_frame_vsync_d & per_frame_vsync) :
                         ( per_frame_vsync_d & ~per_frame_vsync);

    assign frame_end   = VSYNC_ACTIVE_HIGH ?
                         ( per_frame_vsync_d & ~per_frame_vsync) :
                         (~per_frame_vsync_d &  per_frame_vsync);

    reg [X_BITS-1:0] x_cnt;
    reg [Y_BITS-1:0] y_cnt;

    reg              found_r;
    reg [X_BITS-1:0] min_x_r, max_x_r;
    reg [Y_BITS-1:0] min_y_r, max_y_r;
    reg [31:0]       pixel_cnt_r;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            per_frame_vsync_d <= 1'b0;
            per_frame_de_d    <= 1'b0;

            x_cnt             <= {X_BITS{1'b0}};
            y_cnt             <= {Y_BITS{1'b0}};

            found_r           <= 1'b0;
            min_x_r           <= {X_BITS{1'b1}};
            min_y_r           <= {Y_BITS{1'b1}};
            max_x_r           <= {X_BITS{1'b0}};
            max_y_r           <= {Y_BITS{1'b0}};
            pixel_cnt_r       <= 32'd0;

            frame_done        <= 1'b0;
            target_found      <= 1'b0;
            min_x             <= {X_BITS{1'b0}};
            min_y             <= {Y_BITS{1'b0}};
            max_x             <= {X_BITS{1'b0}};
            max_y             <= {Y_BITS{1'b0}};
            pixel_cnt         <= 32'd0;
        end
        else begin
            per_frame_vsync_d <= per_frame_vsync;
            per_frame_de_d    <= per_frame_de;
            frame_done        <= 1'b0;

            // 新帧开始：清空当前帧统计
            if(frame_start) begin
                x_cnt       <= {X_BITS{1'b0}};
                y_cnt       <= {Y_BITS{1'b0}};

                found_r     <= 1'b0;
                min_x_r     <= {X_BITS{1'b1}};
                min_y_r     <= {Y_BITS{1'b1}};
                max_x_r     <= {X_BITS{1'b0}};
                max_y_r     <= {Y_BITS{1'b0}};
                pixel_cnt_r <= 32'd0;
            end
            else begin
                // 像素坐标计数
                if(per_frame_de) begin
                    if(per_img_bin) begin
                        if(!found_r) begin
                            found_r   <= 1'b1;
                            min_x_r   <= x_cnt;
                            max_x_r   <= x_cnt;
                            min_y_r   <= y_cnt;
                            max_y_r   <= y_cnt;
                            pixel_cnt_r <= 32'd1;
                        end
                        else begin
                            if(x_cnt < min_x_r) min_x_r <= x_cnt;
                            if(x_cnt > max_x_r) max_x_r <= x_cnt;
                            if(y_cnt < min_y_r) min_y_r <= y_cnt;
                            if(y_cnt > max_y_r) max_y_r <= y_cnt;
                            pixel_cnt_r <= pixel_cnt_r + 1'b1;
                        end
                    end

                    if(x_cnt == IMG_WIDTH-1)
                        x_cnt <= {X_BITS{1'b0}};
                    else
                        x_cnt <= x_cnt + 1'b1;
                end

                // 一行结束，行号 +1
                if(per_frame_de_d && !per_frame_de) begin
                    x_cnt <= {X_BITS{1'b0}};
                    if(y_cnt != IMG_HEIGHT-1)
                        y_cnt <= y_cnt + 1'b1;
                end
            end

            // 帧结束：锁存结果
            if(frame_end) begin
                frame_done   <= 1'b1;
                target_found <= found_r;
                min_x        <= found_r ? min_x_r : {X_BITS{1'b0}};
                min_y        <= found_r ? min_y_r : {Y_BITS{1'b0}};
                max_x        <= found_r ? max_x_r : {X_BITS{1'b0}};
                max_y        <= found_r ? max_y_r : {Y_BITS{1'b0}};
                pixel_cnt    <= found_r ? pixel_cnt_r : 32'd0;
            end
        end
    end

endmodule