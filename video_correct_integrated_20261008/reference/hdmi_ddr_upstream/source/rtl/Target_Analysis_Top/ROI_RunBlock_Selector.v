  module ROI_RunBlock_Selector #(
      parameter IMG_WIDTH   = 1920,
      parameter IMG_HEIGHT  = 1080,
      parameter X_BITS      = 12,
      parameter Y_BITS      = 12,

      parameter MIN_W       = 12,
      parameter MAX_W       = 1400,
      parameter MIN_H       = 3,
      parameter MAX_H       = 600,

      parameter MIN_AREA    = 20,
      parameter MAX_AREA    = 500000,

      parameter MIN_RATIO_X100    = 250,
      parameter MAX_RATIO_X100    = 600,
      parameter TARGET_RATIO_X100 = 400,
      parameter MIN_FILL_X100     = 10,
      parameter MAX_FILL_X100     = 100,   // kept for compatibility, not used
      parameter FIXED_ROI_ENABLE  = 1,
      parameter FIXED_ROI_W       = 256,
      parameter FIXED_ROI_H       = 96,

      parameter VSYNC_ACTIVE_HIGH = 1'b1,

      parameter MAX_BLOCKS         = 16,
      parameter MIN_RUN_LEN        = 2,
      parameter MERGE_GAP_X        = 16,
      parameter BORDER_MARGIN      = 4,
      parameter IGNORE_LEFT        = 120,
      parameter IGNORE_RIGHT       = 120,
      parameter IGNORE_TOP         = 540,
      parameter EDGE_REJECT_MARGIN = 24,

      parameter SMOOTH_SHIFT       = 2,
      parameter MISS_HOLD_FRAMES   = 6,
      parameter TRACK_DIST_MAX     = 480,

      // kept only for top-level compatibility, not used in current logic
      parameter CENTER_INIT_HALF_W   = 240,
      parameter CENTER_INIT_HALF_H   = 140,
      parameter FALLBACK_WAIT_FRAMES = 2
  )(
      input  wire                 clk,
      input  wire                 rst_n,

      input  wire                 bin_vsync,
      input  wire                 bin_de,
      input  wire                 bin_data,

      output reg                  roi_valid,
      output reg [X_BITS-1:0]     roi_x1,
      output reg [Y_BITS-1:0]     roi_y1,
      output reg [X_BITS-1:0]     roi_x2,
      output reg [Y_BITS-1:0]     roi_y2,

      output reg [X_BITS-1:0]     roi_w,
      output reg [Y_BITS-1:0]     roi_h,
      output reg [31:0]           roi_area,
      output reg                  roi_frame_done
  );

      localparam [X_BITS-1:0] IMG_CX = IMG_WIDTH  / 2;
      localparam [Y_BITS-1:0] IMG_CY = IMG_HEIGHT / 2;

      reg bin_vsync_d;
      reg bin_de_d;

      wire frame_start;
      assign frame_start = VSYNC_ACTIVE_HIGH ?
                           (~bin_vsync_d & bin_vsync) :
                           ( bin_vsync_d & ~bin_vsync);

      reg [X_BITS-1:0] x_cnt;
      reg [Y_BITS-1:0] y_cnt;

      wire in_count_window;
      assign in_count_window =
          (x_cnt >= BORDER_MARGIN + IGNORE_LEFT) &&
          (x_cnt <= IMG_WIDTH  - BORDER_MARGIN - IGNORE_RIGHT - 1) &&
          (y_cnt >= BORDER_MARGIN + IGNORE_TOP) &&
          (y_cnt <= IMG_HEIGHT - BORDER_MARGIN - 1);

      reg              run_active;
      reg [X_BITS-1:0] run_x1;

      reg              blk_valid     [0:MAX_BLOCKS-1];
      reg [X_BITS-1:0] blk_x1        [0:MAX_BLOCKS-1];
      reg [X_BITS-1:0] blk_x2        [0:MAX_BLOCKS-1];
      reg [Y_BITS-1:0] blk_y1        [0:MAX_BLOCKS-1];
      reg [Y_BITS-1:0] blk_y2        [0:MAX_BLOCKS-1];
      reg [Y_BITS-1:0] blk_last_y    [0:MAX_BLOCKS-1];
      reg [31:0]       blk_pixel_cnt [0:MAX_BLOCKS-1];

      integer i;
      integer k;
      integer best_idx;
      integer match_idx;
      integer free_idx;

      reg              near_found;
      reg [31:0]       best_pixel_cnt;
      reg [31:0]       best_dist;
      reg [31:0]       best_ratio_err;
      reg [31:0]       best_fill_margin;
      reg [Y_BITS-1:0] best_cy;
      reg              better_cand;

      reg [X_BITS-1:0] cand_w;
      reg [Y_BITS-1:0] cand_h;
      reg [31:0]       cand_bbox_area;
      reg [31:0]       ratio_lhs;
      reg [31:0]       ratio_rhs_min;
      reg [31:0]       ratio_rhs_max;
      reg [31:0]       ratio_target_lhs;
      reg [31:0]       ratio_err;
      reg [31:0]       fill_lhs;
      reg [31:0]       fill_rhs_min;
      reg [31:0]       fill_margin;
      reg              border_ok;
      reg              ratio_ok;
      reg              fill_ok;
      reg              cand_ok;

      reg [X_BITS-1:0] cand_cx;
      reg [Y_BITS-1:0] cand_cy;
      reg [X_BITS-1:0] prev_cx;
      reg [Y_BITS-1:0] prev_cy;
      reg [31:0]       dist_x;
      reg [31:0]       dist_y;
      reg [31:0]       cand_dist;

      reg [31:0]       center_dist_x;
      reg [31:0]       center_dist_y;
      reg [31:0]       center_dist;

      reg [X_BITS-1:0] raw_x1;
      reg [Y_BITS-1:0] raw_y1;
      reg [X_BITS-1:0] raw_x2;
      reg [Y_BITS-1:0] raw_y2;
      reg [31:0]       raw_area;
      reg [X_BITS-1:0] raw_cx;
      reg [Y_BITS-1:0] raw_cy;

      reg [X_BITS-1:0] next_x1;
      reg [Y_BITS-1:0] next_y1;
      reg [X_BITS-1:0] next_x2;
      reg [Y_BITS-1:0] next_y2;
      reg [31:0]       next_area;

      reg [31:0]       sum_x1;
      reg [31:0]       sum_y1;
      reg [31:0]       sum_x2;
      reg [31:0]       sum_y2;
      reg [33:0]       sum_area;

      reg [X_BITS:0]   run_len;
      reg [3:0]        miss_hold_cnt;
      integer          fixed_x1_i;
      integer          fixed_y1_i;
      integer          fixed_x2_i;
      integer          fixed_y2_i;

      task process_run;
          input [X_BITS-1:0] px1;
          input [X_BITS-1:0] px2;
          input [Y_BITS-1:0] py;
      begin
          if(px2 >= px1) begin
              run_len = px2 - px1 + 1'b1;

              if(run_len >= MIN_RUN_LEN) begin
                  match_idx = -1;
                  free_idx  = -1;

                  for(k = 0; k < MAX_BLOCKS; k = k + 1) begin
                      if(blk_valid[k]) begin
                          if((match_idx == -1) &&
                             (
                                 (blk_last_y[k] == py) ||
                                 ((py != 0) && (blk_last_y[k] == py - 1))
                             ) &&
                             ({1'b0, px1} <= ({1'b0, blk_x2[k]} + MERGE_GAP_X)) &&
                             (({1'b0, px2} + MERGE_GAP_X) >= {1'b0, blk_x1[k]})) begin
                              match_idx = k;
                          end
                      end
                      else if(free_idx == -1) begin
                          free_idx = k;
                      end
                  end

                  if(match_idx != -1) begin
                      if(px1 < blk_x1[match_idx])
                          blk_x1[match_idx] <= px1;
                      if(px2 > blk_x2[match_idx])
                          blk_x2[match_idx] <= px2;
                      if(py < blk_y1[match_idx])
                          blk_y1[match_idx] <= py;
                      if(py > blk_y2[match_idx])
                          blk_y2[match_idx] <= py;

                      blk_last_y[match_idx]    <= py;
                      blk_pixel_cnt[match_idx] <= blk_pixel_cnt[match_idx] + run_len;
                  end
                  else if(free_idx != -1) begin
                      blk_valid[free_idx]     <= 1'b1;
                      blk_x1[free_idx]        <= px1;
                      blk_x2[free_idx]        <= px2;
                      blk_y1[free_idx]        <= py;
                      blk_y2[free_idx]        <= py;
                      blk_last_y[free_idx]    <= py;
                      blk_pixel_cnt[free_idx] <= run_len;
                  end
              end
          end
      end
      endtask

      always @(posedge clk or negedge rst_n) begin
          if(!rst_n) begin
              bin_vsync_d    <= 1'b0;
              bin_de_d       <= 1'b0;

              x_cnt          <= {X_BITS{1'b0}};
              y_cnt          <= {Y_BITS{1'b0}};
              run_active     <= 1'b0;
              run_x1         <= {X_BITS{1'b0}};

              roi_valid      <= 1'b0;
              roi_x1         <= {X_BITS{1'b0}};
              roi_y1         <= {Y_BITS{1'b0}};
              roi_x2         <= {X_BITS{1'b0}};
              roi_y2         <= {Y_BITS{1'b0}};
              roi_w          <= {X_BITS{1'b0}};
              roi_h          <= {Y_BITS{1'b0}};
              roi_area       <= 32'd0;
              roi_frame_done <= 1'b0;

              miss_hold_cnt  <= 4'd0;

              for(i = 0; i < MAX_BLOCKS; i = i + 1) begin
                  blk_valid[i]     <= 1'b0;
                  blk_x1[i]        <= {X_BITS{1'b0}};
                  blk_x2[i]        <= {X_BITS{1'b0}};
                  blk_y1[i]        <= {Y_BITS{1'b0}};
                  blk_y2[i]        <= {Y_BITS{1'b0}};
                  blk_last_y[i]    <= {Y_BITS{1'b0}};
                  blk_pixel_cnt[i] <= 32'd0;
              end
          end
          else begin
              bin_vsync_d    <= bin_vsync;
              bin_de_d       <= bin_de;
              roi_frame_done <= 1'b0;

              if(frame_start) begin
                  roi_frame_done <= 1'b1;

                  best_idx       = -1;
                  best_pixel_cnt = 32'd0;
                  best_dist      = 32'hFFFF_FFFF;
                  best_ratio_err = 32'hFFFF_FFFF;
                  best_fill_margin = 32'd0;
                  best_cy        = {Y_BITS{1'b0}};
                  near_found     = 1'b0;

                  prev_cx = (roi_x1 + roi_x2) >> 1;
                  prev_cy = (roi_y1 + roi_y2) >> 1;

                  for(i = 0; i < MAX_BLOCKS; i = i + 1) begin
                      if(blk_valid[i]) begin
                          cand_w         = blk_x2[i] - blk_x1[i] + 1'b1;
                          cand_h         = blk_y2[i] - blk_y1[i] + 1'b1;
                          cand_bbox_area = cand_w * cand_h;

                          border_ok =
                              (blk_x1[i] >= EDGE_REJECT_MARGIN) &&
                              (blk_y1[i] >= EDGE_REJECT_MARGIN) &&
                              (blk_x2[i] <= IMG_WIDTH  - EDGE_REJECT_MARGIN - 1) &&
                              (blk_y2[i] <= IMG_HEIGHT - EDGE_REJECT_MARGIN - 1);

                          ratio_lhs     = cand_w * 32'd100;
                          ratio_rhs_min = MIN_RATIO_X100 * cand_h;
                          ratio_rhs_max = MAX_RATIO_X100 * cand_h;
                          ratio_target_lhs = TARGET_RATIO_X100 * cand_h;

                          ratio_ok =
                              (cand_bbox_area != 0) &&
                              (ratio_lhs >= ratio_rhs_min) &&
                              (ratio_lhs <= ratio_rhs_max);

                          fill_lhs     = blk_pixel_cnt[i] * 32'd100;
                          fill_rhs_min = MIN_FILL_X100 * cand_bbox_area;

                          fill_ok =
                              (cand_bbox_area != 0) &&
                              (fill_lhs >= fill_rhs_min);

                          if(ratio_lhs >= ratio_target_lhs)
                              ratio_err = ratio_lhs - ratio_target_lhs;
                          else
                              ratio_err = ratio_target_lhs - ratio_lhs;

                          fill_margin = fill_lhs - fill_rhs_min;

                          cand_ok =
                              border_ok &&
                              ratio_ok &&
                              fill_ok &&
                              (cand_w >= MIN_W) &&
                              (cand_w <= MAX_W) &&
                              (cand_h >= MIN_H) &&
                              (cand_h <= MAX_H) &&
                              (blk_pixel_cnt[i] >= MIN_AREA) &&
                              (blk_pixel_cnt[i] <= MAX_AREA);

                          if(cand_ok) begin
                              cand_cx = (blk_x1[i] + blk_x2[i]) >> 1;
                              cand_cy = (blk_y1[i] + blk_y2[i]) >> 1;

                              if(cand_cx >= prev_cx)
                                  dist_x = cand_cx - prev_cx;
                              else
                                  dist_x = prev_cx - cand_cx;

                              if(cand_cy >= prev_cy)
                                  dist_y = cand_cy - prev_cy;
                              else
                                  dist_y = prev_cy - cand_cy;

                              cand_dist = dist_x + dist_y;

                              if(cand_cx >= IMG_CX)
                                  center_dist_x = cand_cx - IMG_CX;
                              else
                                  center_dist_x = IMG_CX - cand_cx;

                              if(cand_cy >= IMG_CY)
                                  center_dist_y = cand_cy - IMG_CY;
                              else
                                  center_dist_y = IMG_CY - cand_cy;

                              center_dist = center_dist_x + center_dist_y;

                              if(roi_valid && (cand_dist <= TRACK_DIST_MAX)) begin
                                  better_cand = 1'b0;

                                  if(!near_found)
                                      better_cand = 1'b1;
                                  else if(cand_dist < best_dist)
                                      better_cand = 1'b1;
                                  else if(cand_dist == best_dist) begin
                                      if(ratio_err < best_ratio_err)
                                          better_cand = 1'b1;
                                      else if(ratio_err == best_ratio_err) begin
                                          if(fill_margin > best_fill_margin)
                                              better_cand = 1'b1;
                                          else if(fill_margin == best_fill_margin) begin
                                              if(blk_pixel_cnt[i] > best_pixel_cnt)
                                                  better_cand = 1'b1;
                                          end
                                      end
                                  end

                                  if(better_cand) begin
                                      near_found     = 1'b1;
                                      best_idx       = i;
                                      best_dist      = cand_dist;
                                      best_pixel_cnt = blk_pixel_cnt[i];
                                      best_ratio_err = ratio_err;
                                      best_fill_margin = fill_margin;
                                      best_cy        = cand_cy;
                                  end
                              end
                              else if(!roi_valid) begin
                                  better_cand = 1'b0;

                                  if(best_idx == -1)
                                      better_cand = 1'b1;
                                  else if(ratio_err < best_ratio_err)
                                      better_cand = 1'b1;
                                  else if(ratio_err == best_ratio_err) begin
                                      if(fill_margin > best_fill_margin)
                                          better_cand = 1'b1;
                                      else if(fill_margin == best_fill_margin) begin
                                          if(blk_pixel_cnt[i] > best_pixel_cnt)
                                              better_cand = 1'b1;
                                          else if(blk_pixel_cnt[i] == best_pixel_cnt) begin
                                              if(cand_cy > best_cy)
                                                  better_cand = 1'b1;
                                              else if(cand_cy == best_cy) begin
                                                  if(center_dist < best_dist)
                                                      better_cand = 1'b1;
                                              end
                                          end
                                      end
                                  end

                                  if(better_cand) begin
                                      best_idx       = i;
                                      best_dist      = center_dist;
                                      best_pixel_cnt = blk_pixel_cnt[i];
                                      best_ratio_err = ratio_err;
                                      best_fill_margin = fill_margin;
                                      best_cy        = cand_cy;
                                  end
                              end
                          end
                      end
                  end

                  if(best_idx != -1) begin
                      raw_cx   = (blk_x1[best_idx] + blk_x2[best_idx]) >> 1;
                      raw_cy   = (blk_y1[best_idx] + blk_y2[best_idx]) >> 1;

                      if(FIXED_ROI_ENABLE) begin
                          fixed_x1_i = raw_cx - (FIXED_ROI_W / 2);
                          fixed_y1_i = raw_cy - (FIXED_ROI_H / 2);

                          if(fixed_x1_i < 0)
                              fixed_x1_i = 0;
                          if(fixed_y1_i < 0)
                              fixed_y1_i = 0;

                          fixed_x2_i = fixed_x1_i + FIXED_ROI_W - 1;
                          fixed_y2_i = fixed_y1_i + FIXED_ROI_H - 1;

                          if(fixed_x2_i > (IMG_WIDTH - 1)) begin
                              fixed_x2_i = IMG_WIDTH - 1;
                              fixed_x1_i = fixed_x2_i - FIXED_ROI_W + 1;
                              if(fixed_x1_i < 0)
                                  fixed_x1_i = 0;
                          end

                          if(fixed_y2_i > (IMG_HEIGHT - 1)) begin
                              fixed_y2_i = IMG_HEIGHT - 1;
                              fixed_y1_i = fixed_y2_i - FIXED_ROI_H + 1;
                              if(fixed_y1_i < 0)
                                  fixed_y1_i = 0;
                          end

                          raw_x1 = fixed_x1_i[X_BITS-1:0];
                          raw_y1 = fixed_y1_i[Y_BITS-1:0];
                          raw_x2 = fixed_x2_i[X_BITS-1:0];
                          raw_y2 = fixed_y2_i[Y_BITS-1:0];
                      end
                      else begin
                          raw_x1 = blk_x1[best_idx];
                          raw_y1 = blk_y1[best_idx];
                          raw_x2 = blk_x2[best_idx];
                          raw_y2 = blk_y2[best_idx];
                      end

                      raw_area = blk_pixel_cnt[best_idx];

                      if(roi_valid) begin
                          sum_x1   = (roi_x1 * ((1 << SMOOTH_SHIFT) - 1)) + raw_x1;
                          sum_y1   = (roi_y1 * ((1 << SMOOTH_SHIFT) - 1)) + raw_y1;
                          sum_x2   = (roi_x2 * ((1 << SMOOTH_SHIFT) - 1)) + raw_x2;
                          sum_y2   = (roi_y2 * ((1 << SMOOTH_SHIFT) - 1)) + raw_y2;
                          sum_area = (roi_area * ((1 << SMOOTH_SHIFT) - 1)) + raw_area;

                          next_x1   = sum_x1   >> SMOOTH_SHIFT;
                          next_y1   = sum_y1   >> SMOOTH_SHIFT;
                          next_x2   = sum_x2   >> SMOOTH_SHIFT;
                          next_y2   = sum_y2   >> SMOOTH_SHIFT;
                          next_area = sum_area >> SMOOTH_SHIFT;
                      end
                      else begin
                          next_x1   = raw_x1;
                          next_y1   = raw_y1;
                          next_x2   = raw_x2;
                          next_y2   = raw_y2;
                          next_area = raw_area;
                      end

                      roi_valid <= 1'b1;
                      roi_x1    <= next_x1;
                      roi_y1    <= next_y1;
                      roi_x2    <= next_x2;
                      roi_y2    <= next_y2;
                      roi_w     <= next_x2 - next_x1 + 1'b1;
                      roi_h     <= next_y2 - next_y1 + 1'b1;
                      roi_area  <= next_area;

                      miss_hold_cnt <= 4'd0;
                  end
                  else begin
                      if(roi_valid && (miss_hold_cnt < MISS_HOLD_FRAMES)) begin
                          roi_valid <= 1'b1;
                          roi_x1    <= roi_x1;
                          roi_y1    <= roi_y1;
                          roi_x2    <= roi_x2;
                          roi_y2    <= roi_y2;
                          roi_w     <= roi_w;
                          roi_h     <= roi_h;
                          roi_area  <= roi_area;
                          miss_hold_cnt <= miss_hold_cnt + 1'b1;
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
                          miss_hold_cnt <= 4'd0;
                      end
                  end

                  x_cnt      <= {X_BITS{1'b0}};
                  y_cnt      <= {Y_BITS{1'b0}};
                  run_active <= 1'b0;
                  run_x1     <= {X_BITS{1'b0}};

                  for(i = 0; i < MAX_BLOCKS; i = i + 1) begin
                      blk_valid[i]     <= 1'b0;
                      blk_x1[i]        <= {X_BITS{1'b0}};
                      blk_x2[i]        <= {X_BITS{1'b0}};
                      blk_y1[i]        <= {Y_BITS{1'b0}};
                      blk_y2[i]        <= {Y_BITS{1'b0}};
                      blk_last_y[i]    <= {Y_BITS{1'b0}};
                      blk_pixel_cnt[i] <= 32'd0;
                  end
              end
              else begin
                  if(bin_de) begin
                      if(bin_data && in_count_window) begin
                          if(!run_active) begin
                              if(x_cnt == IMG_WIDTH - 1) begin
                                  process_run(x_cnt, x_cnt, y_cnt);
                                  run_active <= 1'b0;
                              end
                              else begin
                                  run_active <= 1'b1;
                                  run_x1     <= x_cnt;
                              end
                          end
                          else begin
                              if(x_cnt == IMG_WIDTH - 1) begin
                                  process_run(run_x1, x_cnt, y_cnt);
                                  run_active <= 1'b0;
                              end
                          end
                      end
                      else begin
                          if(run_active) begin
                              process_run(run_x1, x_cnt - 1'b1, y_cnt);
                              run_active <= 1'b0;
                          end
                      end

                      if(x_cnt == IMG_WIDTH - 1)
                          x_cnt <= {X_BITS{1'b0}};
                      else
                          x_cnt <= x_cnt + 1'b1;
                  end

                  if(bin_de_d && !bin_de) begin
                      if(run_active && (x_cnt != 0))
                          process_run(run_x1, x_cnt - 1'b1, y_cnt);

                      x_cnt <= {X_BITS{1'b0}};
                      if(y_cnt != IMG_HEIGHT - 1)
                          y_cnt <= y_cnt + 1'b1;

                      run_active <= 1'b0;
                  end
              end
          end
      end

  endmodule
