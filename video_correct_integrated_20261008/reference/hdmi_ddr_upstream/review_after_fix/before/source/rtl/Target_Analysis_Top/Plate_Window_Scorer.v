module Plate_Window_Scorer #(
    parameter IMG_WIDTH=1920,
    parameter IMG_HEIGHT=1080,
    parameter X_BITS=12,
    parameter Y_BITS=12,

    parameter SEARCH_LEFT=120,
    parameter SEARCH_RIGHT=120,
    parameter SEARCH_TOP=620,
    parameter SEARCH_BOTTOM=24,

    parameter WIN_W=32,
    parameter ROW_SCORE_TH=40,
    parameter COLOR_MIN_SUM=6,
    parameter EDGE_MIN_SUM=8,
    parameter EDGE_MAX_SUM=24,
    parameter X_TOL=48,
    parameter MIN_BAND_ROWS=8,
    parameter MAX_BAND_ROWS=20,
    parameter ROI_W=224,
    parameter ROI_H=80,
    parameter COLOR_WEIGHT=10,
    parameter PEAK_BIN_TH=2,
    parameter PEAK_MIN=3,
    parameter PEAK_MAX=7,
    parameter SMOOTH_SHIFT=2,
    parameter MISS_HOLD_FRAMES=6,
    parameter LOCK_X_RADIUS=160,
    parameter LOCK_Y_RADIUS=72,
    parameter SWITCH_MARGIN=100,
    parameter SWITCH_X_RADIUS=96,
    parameter SWITCH_Y_RADIUS=48,
    parameter SCALE_SWITCH_MARGIN=120,
    parameter KEEP_SCALE_BIAS=24,
    parameter COLOR_RATIO_NUM=2,
    parameter COLOR_RATIO_DEN=1,
    parameter BAND_MIN_STRONG_ROWS=5,
    parameter BAND_MAX_X_SPAN=64,
    parameter BAND_MIN_AVG_SCORE=56,
    parameter LOCK_CONF_MAX=15,
    parameter LOCK_CONF_SEARCH_TH=5,
    parameter LOST_CONFIRM_FRAMES=10,
    parameter integer CENTER_BIAS_X=0,
    parameter integer CENTER_BIAS_Y=0,
    parameter WEAK_COLOR_MIN_SUM=2,
    parameter WEAK_COLOR_RATIO_NUM=4,
    parameter WEAK_COLOR_RATIO_DEN=1,
    parameter SCORE_GAIN_XS=8,
    parameter SCORE_GAIN_S=5,
    parameter SCORE_GAIN_M=4,
    parameter SCORE_GAIN_L=3,
    parameter COLOR_HARD_MIN_XS=3,
    parameter COLOR_HARD_MIN_S=4,
    parameter COLOR_HARD_MIN_M=5,
    parameter COLOR_HARD_MIN_L=6,
    parameter COLOR_BAND_HARD_ROWS=3,
    parameter VSYNC_ACTIVE_HIGH=1'b1,

    // 搜索态/跟踪态门槛
    parameter SEARCH_EDGE_MIN         = 4,
    parameter SEARCH_COLOR_MIN        = 1,
    parameter SEARCH_LOOSE_EDGE_MIN   = 2,
    parameter SEARCH_LOOSE_COLOR_MIN  = 0,

    parameter TRACK_EDGE_MIN          = 2,
    parameter TRACK_COLOR_MIN         = 0,
    parameter TRACK_LOOSE_EDGE_MIN    = 1,
    parameter TRACK_LOOSE_COLOR_MIN   = 0,

    // 跟踪态局部搜索窗
    parameter TRACK_PAD_X             = 280,
    parameter TRACK_PAD_Y             = 140,

    // 远候选切换
    parameter FAR_CONFIRM_FRAMES      = 10,
    parameter FORCE_SWITCH_LOST_FRAMES= 60,
    parameter COLOR_SWITCH_MARGIN_STRONG = 8,

    // 行宽来源：颜色主导 + 小扩边
    parameter EDGE_COLOR_PAD          = 24,
    parameter LOCK_CONF_INC          = 2,
    parameter LOCK_CONF_DEC          = 1,
    parameter HOLD_EXPAND_X          = 12,
    parameter HOLD_EXPAND_Y          = 6,
    parameter HOLD_EXPAND_MAX_X      = 420,
    parameter HOLD_EXPAND_MAX_Y      = 220,
    parameter MOTION_STEP_X          = 72,
    parameter MOTION_STEP_Y          = 36,
    parameter SIZE_STEP_X            = 96,
    parameter SIZE_STEP_Y            = 48,

    // 轻量输入扩张
    parameter EDGE_EXPAND_LEN         = 2,
    parameter COLOR_EXPAND_LEN        = 1
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              bin_vsync,
    input  wire              bin_de,
    input  wire              bin_data,
    input  wire              color_hit_in,
    output reg               roi_valid,
    output reg [X_BITS-1:0]  roi_x1,
    output reg [Y_BITS-1:0]  roi_y1,
    output reg [X_BITS-1:0]  roi_x2,
    output reg [Y_BITS-1:0]  roi_y2,
    output reg [X_BITS-1:0]  roi_w,
    output reg [Y_BITS-1:0]  roi_h,
    output reg [31:0]        roi_area,
    output reg               roi_frame_done
);

    localparam [11:0] GLOBAL_X_MIN = SEARCH_LEFT;
    localparam [11:0] GLOBAL_X_MAX = IMG_WIDTH  - SEARCH_RIGHT  - 1;
    localparam [11:0] GLOBAL_Y_MIN = SEARCH_TOP;
    localparam [11:0] GLOBAL_Y_MAX = IMG_HEIGHT - SEARCH_BOTTOM - 1;
    localparam [11:0] MOTION_STEP_X_W = MOTION_STEP_X;
    localparam [11:0] MOTION_STEP_Y_W = MOTION_STEP_Y;
    localparam [11:0] SIZE_STEP_X_W   = SIZE_STEP_X;
    localparam [11:0] SIZE_STEP_Y_W   = SIZE_STEP_Y;
    localparam [11:0] TRACK_PAD_X_W   = TRACK_PAD_X;
    localparam [11:0] TRACK_PAD_Y_W   = TRACK_PAD_Y;
    localparam [11:0] HOLD_EXPAND_X_W = HOLD_EXPAND_X;
    localparam [11:0] HOLD_EXPAND_Y_W = HOLD_EXPAND_Y;
    localparam [11:0] HOLD_EXPAND_MAX_X_W = HOLD_EXPAND_MAX_X;
    localparam [11:0] HOLD_EXPAND_MAX_Y_W = HOLD_EXPAND_MAX_Y;
    localparam [4:0]  LOCK_CONF_INC_W = LOCK_CONF_INC;
    localparam [4:0]  LOCK_CONF_DEC_W = LOCK_CONF_DEC;
    localparam [4:0]  LOCK_CONF_MAX_W = LOCK_CONF_MAX;

    // 输入轻量扩张：边缘和颜色分路
    reg edge_d1, edge_d2;
    reg color_d1;

    wire edge_hit_expand;
    wire color_hit_expand;

    assign edge_hit_expand  = bin_data     | edge_d1 | edge_d2;
    assign color_hit_expand = color_hit_in | color_d1;

    // 候选框输出
    wire        raw_valid;
    wire [11:0] raw_xmin;
    wire [11:0] raw_ymin;
    wire [11:0] raw_xmax;
    wire [11:0] raw_ymax;
    wire [23:0] raw_score;
    wire [15:0] raw_color_sum;

    // normalize 后候选框
    wire        norm_valid;
    wire [11:0] norm_xmin;
    wire [11:0] norm_ymin;
    wire [11:0] norm_xmax;
    wire [11:0] norm_ymax;

    // 帧同步
    reg  bin_vsync_d;
    reg  frame_armed_top;
    reg  frame_eval_top;
    wire frame_edge;
    wire frame_event_top;

    assign frame_edge      = bin_vsync ^ bin_vsync_d;
    assign frame_event_top = frame_edge && frame_armed_top;

    // 跟踪状态
    reg         track_locked;
    reg [5:0]   track_lost_cnt;
    reg [4:0]   lock_conf;
    reg [11:0]  hold_expand_x;
    reg [11:0]  hold_expand_y;

    reg [11:0]  lock_x1;
    reg [11:0]  lock_y1;
    reg [11:0]  lock_x2;
    reg [11:0]  lock_y2;
    reg [23:0]  lock_score;
    reg [15:0]  lock_color_sum;

    // 远候选确认
    reg         far_pending_valid;
    reg [3:0]   far_pending_cnt;
    reg [11:0]  far_x1;
    reg [11:0]  far_y1;
    reg [11:0]  far_x2;
    reg [11:0]  far_y2;
    reg [23:0]  far_score;
    reg [15:0]  far_color_sum;

    function [11:0] step_limit12;
        input [11:0] cur;
        input [11:0] target;
        input [11:0] step;
        reg [12:0] cur_plus_step;
    begin
        cur_plus_step = {1'b0, cur} + {1'b0, step};
        if(target > cur)
            step_limit12 = (cur_plus_step >= {1'b0, target}) ? target : cur_plus_step[11:0];
        else
            step_limit12 = ((cur - target) <= step) ? target : (cur - step);
    end
    endfunction

    function [11:0] expand_sat12;
        input [11:0] cur;
        input [11:0] step;
        input [11:0] max_val;
        reg [12:0] next_val;
    begin
        next_val = {1'b0, cur} + {1'b0, step};
        expand_sat12 = (next_val >= {1'b0, max_val}) ? max_val : next_val[11:0];
    end
    endfunction

    // 搜索态 / 跟踪态动态搜索窗
    wire [11:0] search_xmin_cur;
    wire [11:0] search_xmax_cur;
    wire [11:0] search_ymin_cur;
    wire [11:0] search_ymax_cur;

    wire use_local_search = track_locked && (track_lost_cnt < LOST_CONFIRM_FRAMES);

    wire [11:0] local_xmin_raw = (lock_x1 > TRACK_PAD_X_W) ? (lock_x1 - TRACK_PAD_X_W) : 12'd0;
    wire [11:0] local_ymin_raw = (lock_y1 > TRACK_PAD_Y_W) ? (lock_y1 - TRACK_PAD_Y_W) : 12'd0;
    wire [12:0] local_xmax_sum = {1'b0, lock_x2} + {1'b0, TRACK_PAD_X_W};
    wire [12:0] local_ymax_sum = {1'b0, lock_y2} + {1'b0, TRACK_PAD_Y_W};
    wire [11:0] local_xmax_raw = (local_xmax_sum < IMG_WIDTH ) ? local_xmax_sum[11:0] : (IMG_WIDTH  - 1);
    wire [11:0] local_ymax_raw = (local_ymax_sum < IMG_HEIGHT) ? local_ymax_sum[11:0] : (IMG_HEIGHT - 1);

    assign search_xmin_cur = use_local_search ? ((local_xmin_raw > GLOBAL_X_MIN) ? local_xmin_raw : GLOBAL_X_MIN) : GLOBAL_X_MIN;
    assign search_xmax_cur = use_local_search ? ((local_xmax_raw < GLOBAL_X_MAX) ? local_xmax_raw : GLOBAL_X_MAX) : GLOBAL_X_MAX;
    assign search_ymin_cur = use_local_search ? ((local_ymin_raw > GLOBAL_Y_MIN) ? local_ymin_raw : GLOBAL_Y_MIN) : GLOBAL_Y_MIN;
    assign search_ymax_cur = use_local_search ? ((local_ymax_raw < GLOBAL_Y_MAX) ? local_ymax_raw : GLOBAL_Y_MAX) : GLOBAL_Y_MAX;

    // 门槛随模式切换
    wire [7:0] strict_edge_min_cur  = use_local_search ? TRACK_EDGE_MIN        : SEARCH_EDGE_MIN;
    wire [7:0] strict_color_min_cur = use_local_search ? TRACK_COLOR_MIN       : SEARCH_COLOR_MIN;
    wire [7:0] loose_edge_min_cur   = use_local_search ? TRACK_LOOSE_EDGE_MIN  : SEARCH_LOOSE_EDGE_MIN;
    wire [7:0] loose_color_min_cur  = use_local_search ? TRACK_LOOSE_COLOR_MIN : SEARCH_LOOSE_COLOR_MIN;

    // bbox segment
    plate_bbox_segment_ref #(
        .IMG_WIDTH      (IMG_WIDTH),
        .IMG_HEIGHT     (IMG_HEIGHT),
        .W_MIN          (12'd12),
        .W_MAX          (12'd900),
        .H_MIN          (12'd4),
        .H_MAX          (12'd120),
        .LOOSE_W_MIN    (12'd16),
        .LOOSE_W_MAX    (12'd800),
        .X_PAD          (12'd20),
        .Y_PAD          (12'd12),
        .COLOR_WEIGHT   (COLOR_WEIGHT),
        .EDGE_COLOR_PAD (EDGE_COLOR_PAD)
    ) u_plate_bbox_segment_ref (
        .clk              (clk),
        .rst_n            (rst_n),
        .in_vs            (bin_vsync),
        .in_de            (bin_de),
        .edge_hit_in      (edge_hit_expand),
        .color_hit_in     (color_hit_expand),
        .scan_xmin        (search_xmin_cur),
        .scan_xmax        (search_xmax_cur),
        .scan_ymin        (search_ymin_cur),
        .scan_ymax        (search_ymax_cur),
        .strict_edge_min  (strict_edge_min_cur),
        .strict_color_min (strict_color_min_cur),
        .loose_edge_min   (loose_edge_min_cur),
        .loose_color_min  (loose_color_min_cur),
        .bbox_valid       (raw_valid),
        .bbox_xmin        (raw_xmin),
        .bbox_ymin        (raw_ymin),
        .bbox_xmax        (raw_xmax),
        .bbox_ymax        (raw_ymax),
        .bbox_score       (raw_score),
        .bbox_color_sum   (raw_color_sum)
    );

    bbox_plate_normalize_ref #(
        .IMG_WIDTH     (IMG_WIDTH),
        .IMG_HEIGHT    (IMG_HEIGHT),
        .OUT_W_MIN     (12'd12),
        .OUT_H_MIN     (12'd4),
        .X_EXTRA       (12'd0),
        .Y_EXTRA       (12'd0)
    ) u_bbox_plate_normalize_ref (
        .in_valid  (raw_valid),
        .in_xmin   (raw_xmin),
        .in_ymin   (raw_ymin),
        .in_xmax   (raw_xmax),
        .in_ymax   (raw_ymax),
        .out_valid (norm_valid),
        .out_xmin  (norm_xmin),
        .out_ymin  (norm_ymin),
        .out_xmax  (norm_xmax),
        .out_ymax  (norm_ymax)
    );

    // 候选参数
    wire cand_valid = norm_valid && (norm_xmax >= norm_xmin) && (norm_ymax >= norm_ymin);
    wire [11:0] cand_w = cand_valid ? (norm_xmax - norm_xmin + 1'b1) : 12'd0;
    wire [11:0] cand_h = cand_valid ? (norm_ymax - norm_ymin + 1'b1) : 12'd0;

    wire [12:0] cand_cx = ({1'b0, norm_xmin} + {1'b0, norm_xmax}) >> 1;
    wire [12:0] cand_cy = ({1'b0, norm_ymin} + {1'b0, norm_ymax}) >> 1;
    wire [12:0] lock_cx = ({1'b0, lock_x1} + {1'b0, lock_x2}) >> 1;
    wire [12:0] lock_cy = ({1'b0, lock_y1} + {1'b0, lock_y2}) >> 1;

    wire [12:0] lock_dx = (cand_cx >= lock_cx) ? (cand_cx - lock_cx) : (lock_cx - cand_cx);
    wire [12:0] lock_dy = (cand_cy >= lock_cy) ? (cand_cy - lock_cy) : (lock_cy - cand_cy);

    wire cand_near_lock = (lock_dx <= LOCK_X_RADIUS) && (lock_dy <= LOCK_Y_RADIUS);

    wire [12:0] far_cx = ({1'b0, far_x1} + {1'b0, far_x2}) >> 1;
    wire [12:0] far_cy = ({1'b0, far_y1} + {1'b0, far_y2}) >> 1;
    wire [12:0] far_dx = (cand_cx >= far_cx) ? (cand_cx - far_cx) : (far_cx - cand_cx);
    wire [12:0] far_dy = (cand_cy >= far_cy) ? (cand_cy - far_cy) : (far_cy - cand_cy);
    wire cand_near_far_pending = (far_dx <= SWITCH_X_RADIUS) && (far_dy <= SWITCH_Y_RADIUS);

    // 平滑更新
    wire [11:0] smooth_x1 = (norm_xmin >= lock_x1) ?
                             (lock_x1 + ((norm_xmin - lock_x1) >> SMOOTH_SHIFT)) :
                             (lock_x1 - ((lock_x1 - norm_xmin) >> SMOOTH_SHIFT));
    wire [11:0] smooth_y1 = (norm_ymin >= lock_y1) ?
                             (lock_y1 + ((norm_ymin - lock_y1) >> SMOOTH_SHIFT)) :
                             (lock_y1 - ((lock_y1 - norm_ymin) >> SMOOTH_SHIFT));
    wire [11:0] smooth_x2 = (norm_xmax >= lock_x2) ?
                             (lock_x2 + ((norm_xmax - lock_x2) >> SMOOTH_SHIFT)) :
                             (lock_x2 - ((lock_x2 - norm_xmax) >> SMOOTH_SHIFT));
    wire [11:0] smooth_y2 = (norm_ymax >= lock_y2) ?
                             (lock_y2 + ((norm_ymax - lock_y2) >> SMOOTH_SHIFT)) :
                             (lock_y2 - ((lock_y2 - norm_ymax) >> SMOOTH_SHIFT));

    wire [11:0] smooth_w = (smooth_x2 >= smooth_x1) ? (smooth_x2 - smooth_x1 + 1'b1) : 12'd0;
    wire [11:0] smooth_h = (smooth_y2 >= smooth_y1) ? (smooth_y2 - smooth_y1 + 1'b1) : 12'd0;

    wire [11:0] lock_w = (lock_x2 >= lock_x1) ? (lock_x2 - lock_x1 + 1'b1) : 12'd0;
    wire [11:0] lock_h = (lock_y2 >= lock_y1) ? (lock_y2 - lock_y1 + 1'b1) : 12'd0;
    wire [11:0] limited_x1 = step_limit12(lock_x1, smooth_x1, MOTION_STEP_X_W);
    wire [11:0] limited_y1 = step_limit12(lock_y1, smooth_y1, MOTION_STEP_Y_W);
    wire [11:0] limited_x2 = step_limit12(lock_x2, smooth_x2, SIZE_STEP_X_W);
    wire [11:0] limited_y2 = step_limit12(lock_y2, smooth_y2, SIZE_STEP_Y_W);
    wire [11:0] limited_w  = (limited_x2 >= limited_x1) ? (limited_x2 - limited_x1 + 1'b1) : lock_w;
    wire [11:0] limited_h  = (limited_y2 >= limited_y1) ? (limited_y2 - limited_y1 + 1'b1) : lock_h;

    wire [11:0] hold_x1 = (lock_x1 > hold_expand_x) ? (lock_x1 - hold_expand_x) : 12'd0;
    wire [11:0] hold_y1 = (lock_y1 > hold_expand_y) ? (lock_y1 - hold_expand_y) : 12'd0;
    wire [12:0] hold_x2_sum = {1'b0, lock_x2} + {1'b0, hold_expand_x};
    wire [12:0] hold_y2_sum = {1'b0, lock_y2} + {1'b0, hold_expand_y};
    wire [11:0] hold_x2 = (hold_x2_sum < IMG_WIDTH ) ? hold_x2_sum[11:0] : (IMG_WIDTH  - 1);
    wire [11:0] hold_y2 = (hold_y2_sum < IMG_HEIGHT) ? hold_y2_sum[11:0] : (IMG_HEIGHT - 1);
    wire [11:0] hold_w  = (hold_x2 >= hold_x1) ? (hold_x2 - hold_x1 + 1'b1) : lock_w;
    wire [11:0] hold_h  = (hold_y2 >= hold_y1) ? (hold_y2 - hold_y1 + 1'b1) : lock_h;

    wire [23:0] switch_margin_conf = {19'd0, lock_conf} << 4;
    wire far_candidate_better =
        cand_valid &&
        !cand_near_lock &&
        (raw_score >= (lock_score + SWITCH_MARGIN + switch_margin_conf)) &&
        (raw_color_sum >= (lock_color_sum + COLOR_SWITCH_MARGIN_STRONG));

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            bin_vsync_d     <= 1'b0;
            frame_armed_top <= 1'b1;
            frame_eval_top  <= 1'b0;

            edge_d1  <= 1'b0;
            edge_d2  <= 1'b0;
            color_d1 <= 1'b0;

            track_locked    <= 1'b0;
            track_lost_cnt  <= 6'd0;
            lock_conf       <= 5'd0;
            hold_expand_x   <= 12'd0;
            hold_expand_y   <= 12'd0;
            lock_x1         <= 12'd0;
            lock_y1         <= 12'd0;
            lock_x2         <= 12'd0;
            lock_y2         <= 12'd0;
            lock_score      <= 24'd0;
            lock_color_sum  <= 16'd0;

            far_pending_valid <= 1'b0;
            far_pending_cnt   <= 4'd0;
            far_x1            <= 12'd0;
            far_y1            <= 12'd0;
            far_x2            <= 12'd0;
            far_y2            <= 12'd0;
            far_score         <= 24'd0;
            far_color_sum     <= 16'd0;

            roi_valid      <= 1'b0;
            roi_x1         <= {X_BITS{1'b0}};
            roi_y1         <= {Y_BITS{1'b0}};
            roi_x2         <= {X_BITS{1'b0}};
            roi_y2         <= {Y_BITS{1'b0}};
            roi_w          <= {X_BITS{1'b0}};
            roi_h          <= {Y_BITS{1'b0}};
            roi_area       <= 32'd0;
            roi_frame_done <= 1'b0;
        end
        else begin
            bin_vsync_d     <= bin_vsync;
            frame_eval_top  <= frame_event_top;
            roi_frame_done  <= frame_event_top;

            if(bin_de) begin
                frame_armed_top <= 1'b1;
                edge_d1  <= bin_data;
                edge_d2  <= edge_d1;
                color_d1 <= color_hit_in;
            end
            else begin
                edge_d1  <= 1'b0;
                edge_d2  <= 1'b0;
                color_d1 <= 1'b0;
            end

            if(frame_event_top)
                frame_armed_top <= 1'b0;

            if(frame_eval_top) begin
                if(!track_locked) begin
                    far_pending_valid <= 1'b0;
                    far_pending_cnt   <= 4'd0;

                    if(cand_valid) begin
                        track_locked   <= 1'b1;
                        track_lost_cnt <= 6'd0;
                        lock_conf      <= LOCK_CONF_INC_W;
                        hold_expand_x  <= 12'd0;
                        hold_expand_y  <= 12'd0;

                        lock_x1        <= norm_xmin;
                        lock_y1        <= norm_ymin;
                        lock_x2        <= norm_xmax;
                        lock_y2        <= norm_ymax;
                        lock_score     <= raw_score;
                        lock_color_sum <= raw_color_sum;

                        roi_valid <= 1'b1;
                        roi_x1    <= norm_xmin[X_BITS-1:0];
                        roi_y1    <= norm_ymin[Y_BITS-1:0];
                        roi_x2    <= norm_xmax[X_BITS-1:0];
                        roi_y2    <= norm_ymax[Y_BITS-1:0];
                        roi_w     <= cand_w[X_BITS-1:0];
                        roi_h     <= cand_h[Y_BITS-1:0];
                        roi_area  <= cand_w * cand_h;
                    end
                    else begin
                        roi_valid <= 1'b0;
                        roi_x1    <= {X_BITS{1'b0}};
                        roi_y1    <= {Y_BITS{1'b0}};
                        roi_x2    <= {X_BITS{1'b0}};
                        roi_y2    <= {Y_BITS{1'b0}};
                        roi_w     <= {X_BITS{1'b0}};
                        roi_h     <= {Y_BITS{1'b0}};
                        roi_area  <= 32'd0;
                    end
                end
                else begin
                    if(cand_valid && cand_near_lock) begin
                        // 近候选：正常平滑更新
                        track_lost_cnt <= 6'd0;
                        hold_expand_x  <= 12'd0;
                        hold_expand_y  <= 12'd0;
                        if(lock_conf + LOCK_CONF_INC_W >= LOCK_CONF_MAX_W)
                            lock_conf <= LOCK_CONF_MAX_W;
                        else
                            lock_conf <= lock_conf + LOCK_CONF_INC_W;

                        far_pending_valid <= 1'b0;
                        far_pending_cnt   <= 4'd0;

                        lock_x1        <= limited_x1;
                        lock_y1        <= limited_y1;
                        lock_x2        <= limited_x2;
                        lock_y2        <= limited_y2;
                        lock_score     <= raw_score;
                        lock_color_sum <= raw_color_sum;

                        roi_valid <= 1'b1;
                        roi_x1    <= limited_x1[X_BITS-1:0];
                        roi_y1    <= limited_y1[Y_BITS-1:0];
                        roi_x2    <= limited_x2[X_BITS-1:0];
                        roi_y2    <= limited_y2[Y_BITS-1:0];
                        roi_w     <= limited_w[X_BITS-1:0];
                        roi_h     <= limited_h[Y_BITS-1:0];
                        roi_area  <= limited_w * limited_h;
                    end
                    else if(track_lost_cnt < LOST_CONFIRM_FRAMES) begin
                        // 局部搜索阶段还没找到：先保持旧框
                        track_lost_cnt <= track_lost_cnt + 1'b1;

                        if(lock_conf > LOCK_CONF_DEC_W)
                            lock_conf <= lock_conf - LOCK_CONF_DEC_W;
                        else
                            lock_conf <= 5'd0;
                        hold_expand_x <= expand_sat12(hold_expand_x, HOLD_EXPAND_X_W, HOLD_EXPAND_MAX_X_W);
                        hold_expand_y <= expand_sat12(hold_expand_y, HOLD_EXPAND_Y_W, HOLD_EXPAND_MAX_Y_W);

                        roi_valid <= 1'b1;
                        roi_x1    <= hold_x1[X_BITS-1:0];
                        roi_y1    <= hold_y1[Y_BITS-1:0];
                        roi_x2    <= hold_x2[X_BITS-1:0];
                        roi_y2    <= hold_y2[Y_BITS-1:0];
                        roi_w     <= hold_w[X_BITS-1:0];
                        roi_h     <= hold_h[Y_BITS-1:0];
                        roi_area  <= hold_w * hold_h;
                    end
                    else begin
                        // 已进入重搜索态：允许全局远候选，但必须严格确认
                        if(far_candidate_better) begin
                            if(far_pending_valid && cand_near_far_pending) begin
                                far_x1        <= norm_xmin;
                                far_y1        <= norm_ymin;
                                far_x2        <= norm_xmax;
                                far_y2        <= norm_ymax;
                                far_score     <= raw_score;
                                far_color_sum <= raw_color_sum;

                                if((far_pending_cnt + 1'b1) >= FAR_CONFIRM_FRAMES || track_lost_cnt >= FORCE_SWITCH_LOST_FRAMES) begin
                                    track_lost_cnt <= 6'd0;
                                    lock_conf      <= LOCK_CONF_MAX_W;
                                    hold_expand_x  <= 12'd0;
                                    hold_expand_y  <= 12'd0;
                                    // 切换到远候选
                                    lock_x1        <= norm_xmin;
                                    lock_y1        <= norm_ymin;
                                    lock_x2        <= norm_xmax;
                                    lock_y2        <= norm_ymax;
                                    lock_score     <= raw_score;
                                    lock_color_sum <= raw_color_sum;

                                    far_pending_valid <= 1'b0;
                                    far_pending_cnt   <= 4'd0;

                                    roi_valid <= 1'b1;
                                    roi_x1    <= norm_xmin[X_BITS-1:0];
                                    roi_y1    <= norm_ymin[Y_BITS-1:0];
                                    roi_x2    <= norm_xmax[X_BITS-1:0];
                                    roi_y2    <= norm_ymax[Y_BITS-1:0];
                                    roi_w     <= cand_w[X_BITS-1:0];
                                    roi_h     <= cand_h[Y_BITS-1:0];
                                    roi_area  <= cand_w * cand_h;
                                end
                                else begin
                                    far_pending_cnt <= far_pending_cnt + 1'b1;

                                    if(track_lost_cnt < FORCE_SWITCH_LOST_FRAMES)
                                        track_lost_cnt <= track_lost_cnt + 1'b1;
                                    hold_expand_x <= expand_sat12(hold_expand_x, HOLD_EXPAND_X_W, HOLD_EXPAND_MAX_X_W);
                                    hold_expand_y <= expand_sat12(hold_expand_y, HOLD_EXPAND_Y_W, HOLD_EXPAND_MAX_Y_W);

                                    roi_valid <= 1'b1;
                                    roi_x1    <= hold_x1[X_BITS-1:0];
                                    roi_y1    <= hold_y1[Y_BITS-1:0];
                                    roi_x2    <= hold_x2[X_BITS-1:0];
                                    roi_y2    <= hold_y2[Y_BITS-1:0];
                                    roi_w     <= hold_w[X_BITS-1:0];
                                    roi_h     <= hold_h[Y_BITS-1:0];
                                    roi_area  <= hold_w * hold_h;
                                end
                            end
                            else begin
                                far_pending_valid <= 1'b1;
                                far_pending_cnt   <= 4'd1;
                                far_x1            <= norm_xmin;
                                far_y1            <= norm_ymin;
                                far_x2            <= norm_xmax;
                                far_y2            <= norm_ymax;
                                far_score         <= raw_score;
                                far_color_sum     <= raw_color_sum;

                                if(track_lost_cnt < FORCE_SWITCH_LOST_FRAMES)
                                    track_lost_cnt <= track_lost_cnt + 1'b1;
                                hold_expand_x <= expand_sat12(hold_expand_x, HOLD_EXPAND_X_W, HOLD_EXPAND_MAX_X_W);
                                hold_expand_y <= expand_sat12(hold_expand_y, HOLD_EXPAND_Y_W, HOLD_EXPAND_MAX_Y_W);

                                roi_valid <= 1'b1;
                                roi_x1    <= hold_x1[X_BITS-1:0];
                                roi_y1    <= hold_y1[Y_BITS-1:0];
                                roi_x2    <= hold_x2[X_BITS-1:0];
                                roi_y2    <= hold_y2[Y_BITS-1:0];
                                roi_w     <= hold_w[X_BITS-1:0];
                                roi_h     <= hold_h[Y_BITS-1:0];
                                roi_area  <= hold_w * hold_h;
                            end
                        end
                        else if(track_lost_cnt < FORCE_SWITCH_LOST_FRAMES) begin
                            // 继续保持旧框，等待更可靠候选
                            far_pending_valid <= 1'b0;
                            far_pending_cnt   <= 4'd0;
                            track_lost_cnt    <= track_lost_cnt + 1'b1;
                            hold_expand_x <= expand_sat12(hold_expand_x, HOLD_EXPAND_X_W, HOLD_EXPAND_MAX_X_W);
                            hold_expand_y <= expand_sat12(hold_expand_y, HOLD_EXPAND_Y_W, HOLD_EXPAND_MAX_Y_W);

                            roi_valid <= 1'b1;
                            roi_x1    <= hold_x1[X_BITS-1:0];
                            roi_y1    <= hold_y1[Y_BITS-1:0];
                            roi_x2    <= hold_x2[X_BITS-1:0];
                            roi_y2    <= hold_y2[Y_BITS-1:0];
                            roi_w     <= hold_w[X_BITS-1:0];
                            roi_h     <= hold_h[Y_BITS-1:0];
                            roi_area  <= hold_w * hold_h;
                        end
                        else begin
                            // 真正丢失
                            track_locked      <= 1'b0;
                            track_lost_cnt    <= 6'd0;
                            lock_conf         <= 5'd0;
                            hold_expand_x     <= 12'd0;
                            hold_expand_y     <= 12'd0;
                            far_pending_valid <= 1'b0;
                            far_pending_cnt   <= 4'd0;

                            roi_valid <= 1'b0;
                            roi_x1    <= {X_BITS{1'b0}};
                            roi_y1    <= {Y_BITS{1'b0}};
                            roi_x2    <= {X_BITS{1'b0}};
                            roi_y2    <= {Y_BITS{1'b0}};
                            roi_w     <= {X_BITS{1'b0}};
                            roi_h     <= {Y_BITS{1'b0}};
                            roi_area  <= 32'd0;
                        end
                    end
                end
            end
        end
    end

endmodule


module plate_bbox_segment_ref #(
    parameter IMG_WIDTH      = 1920,
    parameter IMG_HEIGHT     = 1080,
    parameter W_MIN          = 12'd12,
    parameter W_MAX          = 12'd640,
    parameter H_MIN          = 12'd4,
    parameter H_MAX          = 12'd120,
    parameter LOOSE_W_MIN    = 12'd16,
    parameter LOOSE_W_MAX    = 12'd520,
    parameter X_PAD          = 12'd12,
    parameter Y_PAD          = 12'd8,
    parameter COLOR_WEIGHT   = 10,
    parameter EDGE_COLOR_PAD = 10
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_vs,
    input  wire        in_de,
    input  wire        edge_hit_in,
    input  wire        color_hit_in,

    input  wire [11:0] scan_xmin,
    input  wire [11:0] scan_xmax,
    input  wire [11:0] scan_ymin,
    input  wire [11:0] scan_ymax,

    input  wire [7:0]  strict_edge_min,
    input  wire [7:0]  strict_color_min,
    input  wire [7:0]  loose_edge_min,
    input  wire [7:0]  loose_color_min,

    output reg         bbox_valid,
    output reg  [11:0] bbox_xmin,
    output reg  [11:0] bbox_ymin,
    output reg  [11:0] bbox_xmax,
    output reg  [11:0] bbox_ymax,
    output reg  [23:0] bbox_score,
    output reg  [15:0] bbox_color_sum
);

    localparam [11:0] X_LAST = IMG_WIDTH  - 1;
    localparam [11:0] Y_LAST = IMG_HEIGHT - 1;

    reg        vs_d1;
    reg        frame_armed;
    reg        de_d1;
    reg [11:0] x_cnt;
    reg [11:0] y_cnt;

    reg [11:0] row_edge_sum;
    reg [11:0] row_color_sum;
    reg        row_has_pixel;

    reg [11:0] row_any_xmin;
    reg [11:0] row_any_xmax;

    reg        row_color_found;
    reg [11:0] row_color_xmin;
    reg [11:0] row_color_xmax;

    reg        seg_active;
    reg [11:0] seg_xmin;
    reg [11:0] seg_xmax;
    reg [11:0] seg_ymin;
    reg [11:0] seg_ymax;
    reg [23:0] seg_score;
    reg [15:0] seg_color_sum;

    reg        best_found;
    reg [11:0] best_xmin;
    reg [11:0] best_xmax;
    reg [11:0] best_ymin;
    reg [11:0] best_ymax;
    reg [23:0] best_score;
    reg [15:0] best_color_sum;

    reg        best_loose_row_found;
    reg [23:0] best_loose_row_score;
    reg [15:0] best_loose_row_color_sum;
    reg [11:0] best_loose_row_xmin;
    reg [11:0] best_loose_row_xmax;
    reg [11:0] best_loose_row_y;
    reg [11:0] best_loose_row_w;

    wire frame_edge  = in_vs ^ vs_d1;
    wire frame_event = frame_edge && frame_armed;

    wire search_valid = (x_cnt >= scan_xmin) && (x_cnt <= scan_xmax) &&
                        (y_cnt >= scan_ymin) && (y_cnt <= scan_ymax);

    wire pixel_any   = in_de && search_valid && (edge_hit_in || color_hit_in);
    wire pixel_edge  = in_de && search_valid && edge_hit_in;
    wire pixel_color = in_de && search_valid && color_hit_in;

    // 宽度来源：颜色范围主导，边缘只做小扩边
    wire [11:0] row_core_xmin = row_color_found ? row_color_xmin : row_any_xmin;
    wire [11:0] row_core_xmax = row_color_found ? row_color_xmax : row_any_xmax;

    wire [11:0] row_box_xmin =
        (row_core_xmin > EDGE_COLOR_PAD) ? (row_core_xmin - EDGE_COLOR_PAD) : 12'd0;

    wire [11:0] row_box_xmax =
        (row_core_xmax + EDGE_COLOR_PAD < X_LAST) ? (row_core_xmax + EDGE_COLOR_PAD) : X_LAST;

    wire [11:0] row_w =
        (row_box_xmax >= row_box_xmin) ? (row_box_xmax - row_box_xmin + 1'b1) : 12'd0;

    wire row_strict_ok =
        row_has_pixel &&
        (row_color_sum >= strict_color_min) &&
        (row_edge_sum  >= strict_edge_min)  &&
        (row_w >= W_MIN) &&
        (row_w <= W_MAX);

    wire row_loose_ok =
        row_has_pixel &&
        (row_color_sum >= loose_color_min) &&
        (row_edge_sum  >= loose_edge_min)  &&
        (row_w >= LOOSE_W_MIN) &&
        (row_w <= LOOSE_W_MAX);

    wire [23:0] row_strict_score = {12'd0, row_edge_sum} + (row_color_sum * COLOR_WEIGHT);
    wire [23:0] row_loose_score  = {12'd0, row_edge_sum} + (row_color_sum * COLOR_WEIGHT);

    wire [11:0] seg_w = (seg_xmax >= seg_xmin) ? (seg_xmax - seg_xmin + 1'b1) : 12'd0;
    wire [11:0] seg_h = (seg_ymax >= seg_ymin) ? (seg_ymax - seg_ymin + 1'b1) : 12'd0;
    wire [15:0] seg_w16 = {4'd0, seg_w};
    wire [15:0] seg_h16 = {4'd0, seg_h};

    wire [11:0] loose_bbox_xmin =
        (best_loose_row_xmin > (X_PAD + 12'd24)) ?
        (best_loose_row_xmin - X_PAD - 12'd24) : 12'd0;
    wire [12:0] loose_bbox_xmax_sum =
        {1'b0, best_loose_row_xmax} + {1'b0, X_PAD} + 13'd24;
    wire [11:0] loose_bbox_xmax =
        (loose_bbox_xmax_sum < {1'b0, X_LAST}) ? loose_bbox_xmax_sum[11:0] : X_LAST;
    wire [11:0] loose_bbox_ymin =
        (best_loose_row_y > 12'd28) ? (best_loose_row_y - 12'd28) : 12'd0;
    wire [12:0] loose_bbox_ymax_sum = {1'b0, best_loose_row_y} + 13'd28;
    wire [11:0] loose_bbox_ymax =
        (loose_bbox_ymax_sum < {1'b0, Y_LAST}) ? loose_bbox_ymax_sum[11:0] : Y_LAST;
    wire [12:0] loose_bbox_width =
        {1'b0, loose_bbox_xmax} - {1'b0, loose_bbox_xmin} + 13'd1;
    wire [12:0] loose_bbox_height =
        {1'b0, loose_bbox_ymax} - {1'b0, loose_bbox_ymin} + 13'd1;
    wire [16:0] loose_height_x10 =
        ({4'd0, loose_bbox_height} << 3) + ({4'd0, loose_bbox_height} << 1);
    wire loose_aspect_ok =
        ({4'd0, loose_bbox_width} <= loose_height_x10);

    wire seg_ok =
        (seg_w >= W_MIN) && (seg_w <= W_MAX) &&
        (seg_h >= H_MIN) && (seg_h <= H_MAX) &&
        (seg_w16 >= (seg_h16 << 1)) &&
        (seg_w16 <= (seg_h16 << 5));

    wire active_seg_better =
        seg_active &&
        seg_ok &&
        ((!best_found) || (seg_score > best_score));

    wire strict_found = active_seg_better || best_found;

    wire [11:0] strict_xmin = active_seg_better ? seg_xmin      : best_xmin;
    wire [11:0] strict_xmax = active_seg_better ? seg_xmax      : best_xmax;
    wire [11:0] strict_ymin = active_seg_better ? seg_ymin      : best_ymin;
    wire [11:0] strict_ymax = active_seg_better ? seg_ymax      : best_ymax;
    wire [23:0] strict_score = active_seg_better ? seg_score     : best_score;
    wire [15:0] strict_color = active_seg_better ? seg_color_sum : best_color_sum;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            vs_d1 <= 1'b0;
            frame_armed <= 1'b1;
            de_d1 <= 1'b0;
            x_cnt <= 12'd0;
            y_cnt <= 12'd0;

            row_edge_sum <= 12'd0;
            row_color_sum <= 12'd0;
            row_has_pixel <= 1'b0;
            row_any_xmin <= 12'hfff;
            row_any_xmax <= 12'd0;
            row_color_found <= 1'b0;
            row_color_xmin <= 12'hfff;
            row_color_xmax <= 12'd0;

            seg_active <= 1'b0;
            seg_xmin <= 12'd0;
            seg_xmax <= 12'd0;
            seg_ymin <= 12'd0;
            seg_ymax <= 12'd0;
            seg_score <= 24'd0;
            seg_color_sum <= 16'd0;

            best_found <= 1'b0;
            best_xmin <= 12'd0;
            best_xmax <= 12'd0;
            best_ymin <= 12'd0;
            best_ymax <= 12'd0;
            best_score <= 24'd0;
            best_color_sum <= 16'd0;

            best_loose_row_found <= 1'b0;
            best_loose_row_score <= 24'd0;
            best_loose_row_color_sum <= 16'd0;
            best_loose_row_xmin <= 12'd0;
            best_loose_row_xmax <= 12'd0;
            best_loose_row_y <= 12'd0;
            best_loose_row_w <= 12'd0;

            bbox_valid <= 1'b0;
            bbox_xmin <= 12'd0;
            bbox_ymin <= 12'd0;
            bbox_xmax <= 12'd0;
            bbox_ymax <= 12'd0;
            bbox_score <= 24'd0;
            bbox_color_sum <= 16'd0;
        end
        else begin
            vs_d1 <= in_vs;
            de_d1 <= in_de;

            if(in_de)
                frame_armed <= 1'b1;

            if(frame_event) begin
                frame_armed <= 1'b0;

                if(strict_found) begin
                    bbox_valid <= 1'b1;
                    bbox_xmin  <= (strict_xmin > X_PAD) ? (strict_xmin - X_PAD) : 12'd0;
                    bbox_xmax  <= (strict_xmax + X_PAD < X_LAST) ? (strict_xmax + X_PAD) : X_LAST;
                    bbox_ymin  <= (strict_ymin > Y_PAD) ? (strict_ymin - Y_PAD) : 12'd0;
                    bbox_ymax  <= (strict_ymax + Y_PAD < Y_LAST) ? (strict_ymax + Y_PAD) : Y_LAST;
                    bbox_score <= strict_score;
                    bbox_color_sum <= strict_color;
                end
                else if(best_loose_row_found && loose_aspect_ok) begin
                    bbox_valid <= 1'b1;
                    bbox_xmin  <= loose_bbox_xmin;
                    bbox_xmax  <= loose_bbox_xmax;
                    bbox_ymin  <= loose_bbox_ymin;
                    bbox_ymax  <= loose_bbox_ymax;
                    bbox_score <= best_loose_row_score;
                    bbox_color_sum <= best_loose_row_color_sum;
                end
                else begin
                    bbox_valid <= 1'b0;
                    bbox_xmin <= 12'd0;
                    bbox_ymin <= 12'd0;
                    bbox_xmax <= 12'd0;
                    bbox_ymax <= 12'd0;
                    bbox_score <= 24'd0;
                    bbox_color_sum <= 16'd0;
                end

                x_cnt <= 12'd0;
                y_cnt <= 12'd0;

                row_edge_sum <= 12'd0;
                row_color_sum <= 12'd0;
                row_has_pixel <= 1'b0;
                row_any_xmin <= 12'hfff;
                row_any_xmax <= 12'd0;
                row_color_found <= 1'b0;
                row_color_xmin <= 12'hfff;
                row_color_xmax <= 12'd0;

                seg_active <= 1'b0;
                seg_xmin <= 12'd0;
                seg_xmax <= 12'd0;
                seg_ymin <= 12'd0;
                seg_ymax <= 12'd0;
                seg_score <= 24'd0;
                seg_color_sum <= 16'd0;

                best_found <= 1'b0;
                best_xmin <= 12'd0;
                best_xmax <= 12'd0;
                best_ymin <= 12'd0;
                best_ymax <= 12'd0;
                best_score <= 24'd0;
                best_color_sum <= 16'd0;

                best_loose_row_found <= 1'b0;
                best_loose_row_score <= 24'd0;
                best_loose_row_color_sum <= 16'd0;
                best_loose_row_xmin <= 12'd0;
                best_loose_row_xmax <= 12'd0;
                best_loose_row_y <= 12'd0;
                best_loose_row_w <= 12'd0;
            end
            else begin
                if(in_de) begin
                    if(pixel_any) begin
                        row_has_pixel <= 1'b1;
                        if(x_cnt < row_any_xmin) row_any_xmin <= x_cnt;
                        if(x_cnt > row_any_xmax) row_any_xmax <= x_cnt;
                    end

                    if(pixel_edge)
                        row_edge_sum <= row_edge_sum + 1'b1;

                    if(pixel_color) begin
                        row_color_sum <= row_color_sum + 1'b1;

                        if(!row_color_found) begin
                            row_color_found <= 1'b1;
                            row_color_xmin  <= x_cnt;
                            row_color_xmax  <= x_cnt;
                        end
                        else begin
                            if(x_cnt < row_color_xmin) row_color_xmin <= x_cnt;
                            if(x_cnt > row_color_xmax) row_color_xmax <= x_cnt;
                        end
                    end

                    x_cnt <= x_cnt + 1'b1;
                end

                if(de_d1 && !in_de) begin
                    if(row_strict_ok) begin
                        if(!seg_active) begin
                            seg_active    <= 1'b1;
                            seg_xmin      <= row_box_xmin;
                            seg_xmax      <= row_box_xmax;
                            seg_ymin      <= y_cnt;
                            seg_ymax      <= y_cnt;
                            seg_score     <= row_strict_score;
                            seg_color_sum <= row_color_sum;
                        end
                        else begin
                            if(row_box_xmin < seg_xmin) seg_xmin <= row_box_xmin;
                            if(row_box_xmax > seg_xmax) seg_xmax <= row_box_xmax;
                            seg_ymax      <= y_cnt;
                            seg_score     <= seg_score + row_strict_score;
                            seg_color_sum <= seg_color_sum + row_color_sum;
                        end
                    end
                    else if(seg_active) begin
                        if(seg_ok && ((!best_found) || (seg_score > best_score))) begin
                            best_found     <= 1'b1;
                            best_xmin      <= seg_xmin;
                            best_xmax      <= seg_xmax;
                            best_ymin      <= seg_ymin;
                            best_ymax      <= seg_ymax;
                            best_score     <= seg_score;
                            best_color_sum <= seg_color_sum;
                        end

                        seg_active    <= 1'b0;
                        seg_xmin      <= 12'd0;
                        seg_xmax      <= 12'd0;
                        seg_ymin      <= 12'd0;
                        seg_ymax      <= 12'd0;
                        seg_score     <= 24'd0;
                        seg_color_sum <= 16'd0;
                    end

                    if(row_loose_ok) begin
                        // loose fallback：分数优先 / 颜色优先 / 宽度最后约束
                        if((!best_loose_row_found) ||
                           (row_loose_score > best_loose_row_score) ||
                           ((row_loose_score == best_loose_row_score) && (row_color_sum > best_loose_row_color_sum)) ||
                           ((row_loose_score == best_loose_row_score) && (row_color_sum == best_loose_row_color_sum) && (row_w < best_loose_row_w))) begin
                            best_loose_row_found     <= 1'b1;
                            best_loose_row_score     <= row_loose_score;
                            best_loose_row_color_sum <= row_color_sum;
                            best_loose_row_xmin      <= row_box_xmin;
                            best_loose_row_xmax      <= row_box_xmax;
                            best_loose_row_y         <= y_cnt;
                            best_loose_row_w         <= row_w;
                        end
                    end

                    row_edge_sum <= 12'd0;
                    row_color_sum <= 12'd0;
                    row_has_pixel <= 1'b0;
                    row_any_xmin <= 12'hfff;
                    row_any_xmax <= 12'd0;
                    row_color_found <= 1'b0;
                    row_color_xmin <= 12'hfff;
                    row_color_xmax <= 12'd0;
                    x_cnt <= 12'd0;
                    y_cnt <= y_cnt + 1'b1;
                end
            end
        end
    end

endmodule


module bbox_plate_normalize_ref #(
    parameter IMG_WIDTH  = 1920,
    parameter IMG_HEIGHT = 1080,
    parameter OUT_W_MIN  = 12'd80,
    parameter OUT_H_MIN  = 12'd25,
    parameter X_EXTRA    = 12'd10,
    parameter Y_EXTRA    = 12'd8
)(
    input  wire        in_valid,
    input  wire [11:0] in_xmin,
    input  wire [11:0] in_ymin,
    input  wire [11:0] in_xmax,
    input  wire [11:0] in_ymax,
    output reg         out_valid,
    output reg  [11:0] out_xmin,
    output reg  [11:0] out_ymin,
    output reg  [11:0] out_xmax,
    output reg  [11:0] out_ymax
);

    localparam [11:0] X_LAST = IMG_WIDTH  - 1;
    localparam [11:0] Y_LAST = IMG_HEIGHT - 1;

    wire coords_ok = (in_xmax >= in_xmin) && (in_ymax >= in_ymin);
    wire [11:0] in_w = coords_ok ? (in_xmax - in_xmin + 1'b1) : 12'd0;
    wire [11:0] in_h = coords_ok ? (in_ymax - in_ymin + 1'b1) : 12'd0;
    wire size_ok = in_valid && coords_ok &&
                   (in_w >= OUT_W_MIN) && (in_h >= OUT_H_MIN);
    wire [12:0] xmax_sum = {1'b0, in_xmax} + {1'b0, X_EXTRA};
    wire [12:0] ymax_sum = {1'b0, in_ymax} + {1'b0, Y_EXTRA};

    always @(*) begin
        out_valid = 1'b0;
        out_xmin = 12'd0;
        out_ymin = 12'd0;
        out_xmax = 12'd0;
        out_ymax = 12'd0;


        if(size_ok) begin
            out_valid = 1'b1;
            out_xmin = (in_xmin > X_EXTRA) ? (in_xmin - X_EXTRA) : 12'd0;
            out_xmax = (xmax_sum < {1'b0, X_LAST}) ? xmax_sum[11:0] : X_LAST;
            out_ymin = (in_ymin > Y_EXTRA) ? (in_ymin - Y_EXTRA) : 12'd0;
            out_ymax = (ymax_sum < {1'b0, Y_LAST}) ? ymax_sum[11:0] : Y_LAST;
        end
    end

endmodule
