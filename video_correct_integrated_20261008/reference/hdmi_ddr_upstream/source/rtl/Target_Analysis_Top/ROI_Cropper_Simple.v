module ROI_Cropper_Simple #(
    parameter IMG_WIDTH  = 1920,
    parameter IMG_HEIGHT = 1080,
    parameter X_BITS     = 12,
    parameter Y_BITS     = 12,
    parameter VSYNC_ACTIVE_HIGH = 1'b1
)(
    input  wire                 clk,
    input  wire                 rst_n,

    input  wire                 src_vsync,
    input  wire                 src_de,
    input  wire [7:0]           src_r,
    input  wire [7:0]           src_g,
    input  wire [7:0]           src_b,

    input  wire                 roi_valid_in,
    input  wire [X_BITS-1:0]    roi_x1_in,
    input  wire [Y_BITS-1:0]    roi_y1_in,
    input  wire [X_BITS-1:0]    roi_x2_in,
    input  wire [Y_BITS-1:0]    roi_y2_in,

    output reg                  roi_frame_start,
    output reg                  roi_de,
    output reg [7:0]            roi_r,
    output reg [7:0]            roi_g,
    output reg [7:0]            roi_b,
    output reg [X_BITS-1:0]     roi_rel_x,
    output reg [Y_BITS-1:0]     roi_rel_y
);

    reg src_vsync_d;
    reg src_de_d;

    wire frame_start;
    assign frame_start = VSYNC_ACTIVE_HIGH ?
                         (~src_vsync_d & src_vsync) :
                         ( src_vsync_d & ~src_vsync);

    reg [X_BITS-1:0] x_cnt;
    reg [Y_BITS-1:0] y_cnt;

    // 每帧开始时锁存本帧使用的 ROI
    reg              roi_valid_act;
    reg [X_BITS-1:0] roi_x1_act, roi_x2_act;
    reg [Y_BITS-1:0] roi_y1_act, roi_y2_act;

    wire in_roi_now;
    assign in_roi_now = roi_valid_act &&
                        src_de &&
                        (x_cnt >= roi_x1_act) && (x_cnt <= roi_x2_act) &&
                        (y_cnt >= roi_y1_act) && (y_cnt <= roi_y2_act);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            src_vsync_d     <= 1'b0;
            src_de_d        <= 1'b0;
            x_cnt           <= {X_BITS{1'b0}};
            y_cnt           <= {Y_BITS{1'b0}};

            roi_valid_act   <= 1'b0;
            roi_x1_act      <= {X_BITS{1'b0}};
            roi_x2_act      <= {X_BITS{1'b0}};
            roi_y1_act      <= {Y_BITS{1'b0}};
            roi_y2_act      <= {Y_BITS{1'b0}};

            roi_frame_start <= 1'b0;
            roi_de          <= 1'b0;
            roi_r           <= 8'd0;
            roi_g           <= 8'd0;
            roi_b           <= 8'd0;
            roi_rel_x       <= {X_BITS{1'b0}};
            roi_rel_y       <= {Y_BITS{1'b0}};
        end
        else begin
            src_vsync_d     <= src_vsync;
            src_de_d        <= src_de;
            roi_frame_start <= 1'b0;
            roi_de          <= 1'b0;

            if(frame_start) begin
                x_cnt         <= {X_BITS{1'b0}};
                y_cnt         <= {Y_BITS{1'b0}};

                roi_valid_act <= roi_valid_in;
                roi_x1_act    <= roi_x1_in;
                roi_x2_act    <= roi_x2_in;
                roi_y1_act    <= roi_y1_in;
                roi_y2_act    <= roi_y2_in;
            end
            else begin
                if(src_de) begin
                    if(in_roi_now) begin
                        roi_de    <= 1'b1;
                        roi_r     <= src_r;
                        roi_g     <= src_g;
                        roi_b     <= src_b;
                        roi_rel_x <= x_cnt - roi_x1_act;
                        roi_rel_y <= y_cnt - roi_y1_act;

                        if((x_cnt == roi_x1_act) && (y_cnt == roi_y1_act))
                            roi_frame_start <= 1'b1;
                    end

                    if(x_cnt == IMG_WIDTH-1)
                        x_cnt <= {X_BITS{1'b0}};
                    else
                        x_cnt <= x_cnt + 1'b1;
                end

                if(src_de_d && !src_de) begin
                    x_cnt <= {X_BITS{1'b0}};
                    if(y_cnt != IMG_HEIGHT-1)
                        y_cnt <= y_cnt + 1'b1;
                end
            end
        end
    end

endmodule