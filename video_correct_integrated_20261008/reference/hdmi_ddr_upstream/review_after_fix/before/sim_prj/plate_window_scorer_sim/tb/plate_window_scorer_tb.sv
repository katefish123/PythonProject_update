`timescale 1ns/1ps

module plate_window_scorer_tb;

    localparam integer IMG_WIDTH  = 1920;
    localparam integer IMG_HEIGHT = 1080;
    localparam real    CLK_HALF_NS = 3.367;
    localparam integer FIXED_SEED = 32'h5A17_2026;

    localparam integer LINE_EMPTY  = 0;
    localparam integer LINE_STRICT = 1;
    localparam integer LINE_LOOSE  = 2;

    reg clk;
    reg rst_n;
    reg bin_vsync;
    reg bin_de;
    reg bin_data;
    reg color_hit_in;

    wire        roi_valid;
    wire [11:0] roi_x1;
    wire [11:0] roi_y1;
    wire [11:0] roi_x2;
    wire [11:0] roi_y2;
    wire [11:0] roi_w;
    wire [11:0] roi_h;
    wire [31:0] roi_area;
    wire        roi_frame_done;

    integer fail_count;
    integer seed_state;
    integer case_fail_start;
    string  current_case;

    reg monitor_stable;
    reg monitor_valid;
    reg [11:0] monitor_x1;
    reg [11:0] monitor_y1;
    reg [11:0] monitor_x2;
    reg [11:0] monitor_y2;

    always #(CLK_HALF_NS) clk = ~clk;

    Plate_Window_Scorer #(
        .IMG_WIDTH                  (1920),
        .IMG_HEIGHT                 (1080),
        .X_BITS                     (12),
        .Y_BITS                     (12),
        .SEARCH_LEFT                (16),
        .SEARCH_RIGHT               (16),
        .SEARCH_TOP                 (8),
        .SEARCH_BOTTOM              (8),
        .WIN_W                      (32),
        .ROW_SCORE_TH               (40),
        .COLOR_MIN_SUM              (6),
        .EDGE_MIN_SUM               (8),
        .EDGE_MAX_SUM               (24),
        .X_TOL                      (48),
        .MIN_BAND_ROWS              (8),
        .MAX_BAND_ROWS              (20),
        .ROI_W                      (224),
        .ROI_H                      (80),
        .COLOR_WEIGHT               (20),
        .PEAK_BIN_TH                (2),
        .PEAK_MIN                   (3),
        .PEAK_MAX                   (7),
        .COLOR_RATIO_NUM            (2),
        .COLOR_RATIO_DEN            (1),
        .BAND_MIN_STRONG_ROWS       (5),
        .BAND_MAX_X_SPAN            (64),
        .BAND_MIN_AVG_SCORE         (56),
        .SMOOTH_SHIFT               (4),
        .MISS_HOLD_FRAMES           (20),
        .LOCK_X_RADIUS              (360),
        .LOCK_Y_RADIUS              (180),
        .SWITCH_MARGIN              (380),
        .SWITCH_X_RADIUS            (160),
        .SWITCH_Y_RADIUS            (96),
        .LOST_CONFIRM_FRAMES        (20),
        .SEARCH_EDGE_MIN            (4),
        .SEARCH_COLOR_MIN           (1),
        .SEARCH_LOOSE_EDGE_MIN      (2),
        .SEARCH_LOOSE_COLOR_MIN     (1),
        .TRACK_EDGE_MIN             (2),
        .TRACK_COLOR_MIN            (1),
        .TRACK_LOOSE_EDGE_MIN       (1),
        .TRACK_LOOSE_COLOR_MIN      (1),
        .TRACK_PAD_X                (200),
        .TRACK_PAD_Y                (90),
        .FAR_CONFIRM_FRAMES         (12),
        .FORCE_SWITCH_LOST_FRAMES   (20),
        .COLOR_SWITCH_MARGIN_STRONG (6),
        .EDGE_COLOR_PAD             (8)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .bin_vsync      (bin_vsync),
        .bin_de         (bin_de),
        .bin_data       (bin_data),
        .color_hit_in   (color_hit_in),
        .roi_valid      (roi_valid),
        .roi_x1         (roi_x1),
        .roi_y1         (roi_y1),
        .roi_x2         (roi_x2),
        .roi_y2         (roi_y2),
        .roi_w          (roi_w),
        .roi_h          (roi_h),
        .roi_area       (roi_area),
        .roi_frame_done (roi_frame_done)
    );

    task automatic fail_value;
        input string field_name;
        input [63:0] expected;
        input [63:0] actual;
        begin
            fail_count = fail_count + 1;
            $display("FAIL case=%s field=%s expected=%0d actual=%0d time=%0t",
                     current_case, field_name, expected, actual, $time);
        end
    endtask

    task automatic check_value;
        input string field_name;
        input [63:0] expected;
        input [63:0] actual;
        begin
            if (actual !== expected)
                fail_value(field_name, expected, actual);
        end
    endtask

    task automatic begin_case;
        input string case_name;
        begin
            current_case = case_name;
            case_fail_start = fail_count;
            monitor_stable = 1'b0;
            rst_n = 1'b0;
            bin_vsync = 1'b0;
            bin_de = 1'b0;
            bin_data = 1'b0;
            color_hit_in = 1'b0;
            repeat (4) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
            #1;
            check_value("reset.roi_valid", 0, roi_valid);
            check_value("reset.roi_frame_done", 0, roi_frame_done);
            $display("CASE_START %s seed=0x%08x time=%0t", current_case, FIXED_SEED, $time);
        end
    endtask

    task automatic end_case;
        begin
            if (fail_count == case_fail_start)
                $display("PASS case=%s time=%0t", current_case, $time);
            else
                $display("FAIL case=%s failures=%0d time=%0t",
                         current_case, fail_count - case_fail_start, $time);
        end
    endtask

    task automatic drive_active_line;
        input integer line_kind;
        integer x;
        begin
            for (x = 0; x < IMG_WIDTH; x = x + 1) begin
                @(negedge clk);
                bin_de = 1'b1;
                case (line_kind)
                    LINE_STRICT: begin
                        bin_data     = (x >= 300) && (x <= 359);
                        color_hit_in = (x >= 300) && (x <= 359);
                    end
                    LINE_LOOSE: begin
                        bin_data     = (x == 500);
                        color_hit_in = (x == 500);
                    end
                    default: begin
                        bin_data     = 1'b0;
                        color_hit_in = 1'b0;
                    end
                endcase
            end

            @(negedge clk);
            bin_de = 1'b0;
            bin_data = 1'b0;
            color_hit_in = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic drive_frame;
        input integer scenario;
        integer y;
        integer kind;
        begin
            for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
                kind = LINE_EMPTY;
                case (scenario)
                    1: if ((y >= 300) && (y <= 303)) kind = LINE_STRICT;
                    2: begin
                        if ((y >= 300) && (y <= 303)) kind = LINE_STRICT;
                        if ((y >= 400) && (y <= 405)) kind = LINE_STRICT;
                    end
                    3: begin
                        if ((y >= 300) && (y <= 305)) kind = LINE_STRICT;
                        if ((y >= 400) && (y <= 403)) kind = LINE_STRICT;
                    end
                    4: if (y == 350) kind = LINE_LOOSE;
                    5: begin
                        if ((y >= 300) && (y <= 303)) kind = LINE_STRICT;
                        if (y == 500) kind = LINE_LOOSE;
                    end
                    default: kind = LINE_EMPTY;
                endcase
                drive_active_line(kind);
            end
        end
    endtask

    task automatic check_raw_and_norm;
        input integer expected_valid;
        input integer raw_x1_e;
        input integer raw_y1_e;
        input integer raw_x2_e;
        input integer raw_y2_e;
        input integer raw_score_e;
        input integer raw_color_e;
        input integer norm_x1_e;
        input integer norm_y1_e;
        input integer norm_x2_e;
        input integer norm_y2_e;
        begin
            check_value("raw_valid", expected_valid, dut.raw_valid);
            check_value("norm_valid", expected_valid, dut.norm_valid);
            if (expected_valid) begin
                check_value("raw_xmin", raw_x1_e, dut.raw_xmin);
                check_value("raw_ymin", raw_y1_e, dut.raw_ymin);
                check_value("raw_xmax", raw_x2_e, dut.raw_xmax);
                check_value("raw_ymax", raw_y2_e, dut.raw_ymax);
                check_value("raw_score", raw_score_e, dut.raw_score);
                check_value("raw_color_sum", raw_color_e, dut.raw_color_sum);
                check_value("norm_xmin", norm_x1_e, dut.norm_xmin);
                check_value("norm_ymin", norm_y1_e, dut.norm_ymin);
                check_value("norm_xmax", norm_x2_e, dut.norm_xmax);
                check_value("norm_ymax", norm_y2_e, dut.norm_ymax);
            end
        end
    endtask

    task automatic end_frame_and_check;
        input integer expected_valid;
        input integer raw_x1_e;
        input integer raw_y1_e;
        input integer raw_x2_e;
        input integer raw_y2_e;
        input integer raw_score_e;
        input integer raw_color_e;
        input integer final_x1_e;
        input integer final_y1_e;
        input integer final_x2_e;
        input integer final_y2_e;
        input integer final_w_e;
        input integer final_h_e;
        input integer final_area_e;
        reg old_valid;
        reg [11:0] old_x1;
        reg [11:0] old_y1;
        reg [11:0] old_x2;
        reg [11:0] old_y2;
        begin
            old_valid = roi_valid;
            old_x1 = roi_x1;
            old_y1 = roi_y1;
            old_x2 = roi_x2;
            old_y2 = roi_y2;

            @(negedge clk);
            bin_vsync = ~bin_vsync;

            // P0: frame_event is consumed; bbox is committed internally.
            @(posedge clk);
            #1;
            check_value("frame_event.roi_frame_done", 1, roi_frame_done);
            check_value("frame_event.roi_valid_unchanged", old_valid, roi_valid);
            check_value("frame_event.roi_x1_unchanged", old_x1, roi_x1);
            check_value("frame_event.roi_y1_unchanged", old_y1, roi_y1);
            check_value("frame_event.roi_x2_unchanged", old_x2, roi_x2);
            check_value("frame_event.roi_y2_unchanged", old_y2, roi_y2);
            check_raw_and_norm(expected_valid,
                               raw_x1_e, raw_y1_e, raw_x2_e, raw_y2_e,
                               raw_score_e, raw_color_e,
                               final_x1_e, final_y1_e, final_x2_e, final_y2_e);
            monitor_stable = 1'b0;

            // P1: delayed frame_eval_top updates the public ROI outputs.
            @(posedge clk);
            #1;
            check_value("commit.roi_frame_done", 0, roi_frame_done);
            check_value("commit.roi_valid", expected_valid, roi_valid);
            if (expected_valid) begin
                check_value("commit.roi_x1", final_x1_e, roi_x1);
                check_value("commit.roi_y1", final_y1_e, roi_y1);
                check_value("commit.roi_x2", final_x2_e, roi_x2);
                check_value("commit.roi_y2", final_y2_e, roi_y2);
                check_value("commit.roi_w", final_w_e, roi_w);
                check_value("commit.roi_h", final_h_e, roi_h);
                check_value("commit.roi_area", final_area_e, roi_area);
            end

            repeat (3) @(posedge clk);
            #1;
            check_value("post_commit.roi_valid", expected_valid, roi_valid);
            if (expected_valid) begin
                check_value("post_commit.roi_x1", final_x1_e, roi_x1);
                check_value("post_commit.roi_y1", final_y1_e, roi_y1);
                check_value("post_commit.roi_x2", final_x2_e, roi_x2);
                check_value("post_commit.roi_y2", final_y2_e, roi_y2);
            end
        end
    endtask

    always @(negedge clk) begin
        if (monitor_stable &&
            ((roi_valid !== monitor_valid) ||
             (roi_x1 !== monitor_x1) || (roi_y1 !== monitor_y1) ||
             (roi_x2 !== monitor_x2) || (roi_y2 !== monitor_y2))) begin
            fail_count = fail_count + 1;
            $display("FAIL case=%s field=mid_frame_stability expected=%0d:(%0d,%0d)-(%0d,%0d) actual=%0d:(%0d,%0d)-(%0d,%0d) time=%0t",
                     current_case,
                     monitor_valid, monitor_x1, monitor_y1, monitor_x2, monitor_y2,
                     roi_valid, roi_x1, roi_y1, roi_x2, roi_y2, $time);
            monitor_stable = 1'b0;
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        bin_vsync = 1'b0;
        bin_de = 1'b0;
        bin_data = 1'b0;
        color_hit_in = 1'b0;
        fail_count = 0;
        monitor_stable = 1'b0;
        seed_state = FIXED_SEED;
        seed_state = $urandom(seed_state);

        begin_case("S-00 empty frame");
        drive_frame(0);
        end_frame_and_check(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        end_case();

        // Strict row: 62 expanded edge pixels + 61 expanded color pixels.
        // Score per row = 62 + 61*20 = 1282.
        begin_case("S-01 one strict candidate");
        drive_frame(1);
        end_frame_and_check(1,
                            272, 288, 388, 315, 5128, 244,
                            272, 288, 388, 315, 117, 28, 3276);
        end_case();

        begin_case("S-02A later candidate higher");
        drive_frame(2);
        end_frame_and_check(1,
                            272, 388, 388, 417, 7692, 366,
                            272, 388, 388, 417, 117, 30, 3510);
        end_case();

        begin_case("S-02B earlier candidate higher");
        drive_frame(3);
        end_frame_and_check(1,
                            272, 288, 388, 317, 7692, 366,
                            272, 288, 388, 317, 117, 30, 3510);
        end_case();

        // One source hit expands to 3 edge pixels and 2 color pixels.
        // It fails strict edge>=4 but passes loose edge>=2.
        begin_case("S-03 loose fallback");
        drive_frame(4);
        end_frame_and_check(1,
                            448, 322, 553, 378, 43, 2,
                            448, 322, 553, 378, 106, 57, 6042);
        end_case();

        begin_case("S-04 strict priority and stable commit");
        monitor_valid = roi_valid;
        monitor_x1 = roi_x1;
        monitor_y1 = roi_y1;
        monitor_x2 = roi_x2;
        monitor_y2 = roi_y2;
        monitor_stable = 1'b1;
        drive_frame(5);
        end_frame_and_check(1,
                            272, 288, 388, 315, 5128, 244,
                            272, 288, 388, 315, 117, 28, 3276);
        end_case();

        if (fail_count == 0) begin
            $display("A02R1_RESULT PASS cases=6 logical_groups=5 seed=0x%08x time=%0t",
                     FIXED_SEED, $time);
            $finish;
        end
        else begin
            $display("A02R1_RESULT FAIL failures=%0d seed=0x%08x time=%0t",
                     fail_count, FIXED_SEED, $time);
            $finish;
        end
    end

endmodule
