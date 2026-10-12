onerror {quit -code 2}

log /plate_window_scorer_tb/rst_n
log /plate_window_scorer_tb/bin_vsync
log /plate_window_scorer_tb/bin_de
log /plate_window_scorer_tb/bin_data
log /plate_window_scorer_tb/color_hit_in
log /plate_window_scorer_tb/roi_valid
log /plate_window_scorer_tb/roi_x1
log /plate_window_scorer_tb/roi_y1
log /plate_window_scorer_tb/roi_x2
log /plate_window_scorer_tb/roi_y2
log /plate_window_scorer_tb/roi_frame_done
log /plate_window_scorer_tb/dut/frame_event_top
log /plate_window_scorer_tb/dut/frame_eval_top
log /plate_window_scorer_tb/dut/raw_valid
log /plate_window_scorer_tb/dut/raw_xmin
log /plate_window_scorer_tb/dut/raw_ymin
log /plate_window_scorer_tb/dut/raw_xmax
log /plate_window_scorer_tb/dut/raw_ymax
log /plate_window_scorer_tb/dut/raw_score
log /plate_window_scorer_tb/dut/norm_valid
log /plate_window_scorer_tb/dut/norm_xmin
log /plate_window_scorer_tb/dut/norm_ymin
log /plate_window_scorer_tb/dut/norm_xmax
log /plate_window_scorer_tb/dut/norm_ymax
log /plate_window_scorer_tb/dut/track_locked
log /plate_window_scorer_tb/dut/lock_conf
log /plate_window_scorer_tb/dut/u_plate_bbox_segment_ref/seg_active
log /plate_window_scorer_tb/dut/u_plate_bbox_segment_ref/seg_score
log /plate_window_scorer_tb/dut/u_plate_bbox_segment_ref/best_found
log /plate_window_scorer_tb/dut/u_plate_bbox_segment_ref/best_score
log /plate_window_scorer_tb/dut/u_plate_bbox_segment_ref/best_loose_row_found
log /plate_window_scorer_tb/dut/u_plate_bbox_segment_ref/best_loose_row_score

run -all
quit -f
