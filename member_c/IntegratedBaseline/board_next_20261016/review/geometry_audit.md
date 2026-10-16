# Frozen S camera geometry audit — 2026-10-16

This audit concerns `D:/FPGA/output/c_stream_board_v4s_20261016`, not an unused RTL template. It does not establish that a photographed screen was running a particular bitstream.

## Finding: colored targets do not match the selected detector (P1)

The actual generated top (`diagnostics/ddr_camera_hires_prefetch_20261012/results/video_correct_ddr_top.v:99`) configures all three black-channel ranges to 0..64 and four fixed 102x102 source ROIs. `rtl/stream/continuous_capture_geometry.v:56` filters pixels using this black condition before forwarding contributions. `rtl/algo/marker_detector.v` applies the same gate and accepts 64..16384 pixels with span <=256.

Bright red, green, blue and yellow corner blocks therefore cannot serve as the intended markers under this configuration. A black background filling an entire ROI has 10404 pixels and span101, which passes both count and span gates. A background/lettering centroid can be mathematically valid while identifying the wrong quadrilateral.

The screenshot `C:/Users/Lenovo/AppData/Local/Temp/codex-clipboard-464238eb-ad39-4941-a8c1-a7bcea16f833.png` shows a tilted sheet and background under CORRECTED. **It is an output-screen screenshot, not the raw 1920x1080 source frame, and must not be used as an input pixel golden.** It cannot establish the four selected source centroids, raw RGB values, or per-frame H. No claim is made that the background explanation is proven for that individual frame.

## Mapping and display trace

The generated processor uses FIXED_IDENTITY=0. Its C adapter forwards P0/P1/P2/P3 as TL/TR/BR/BL into the unchanged B solver. `vendor/b/rtl/homography_solver.v` constructs a destination-to-source inverse H, and `perspective_coord.v` applies that H to each destination coordinate.

Logical destination corners (0,0), (764,0), (764,1079), (0,1079) correspond to the four source corners. Physical result columns1..765 contain these765 logical columns. Physical columns0,766,767 are black padding. This is a768x1080 result stride, not a1920-wide raw source.

The result writer captures RESULT_BASE0/1=0x0200000/0x0400000. The actual display reads those same result banks. After image_valid, its portrait branch uses DDR `pixel_q`; the preview branch is restricted to the pre-result pattern path. The selected generated RTL provides no evidence of a hidden RAW/preview substitution while showing CORRECTED.

CORRECTED (`top:90`) means image_valid/result publication, not geometric quality acceptance. The status path never checks paper edges, colored-marker correspondence, or grid alignment.

## Independent mathematical check and regression scope

`independent_geometry_oracle.py` solves eight projective point constraints with exact Fractions independently of B's closed-form solver or pixel/request traces. It separately evaluates a transcription of the actual Q24 equations against those constraints for all three existing fullHD fixture quadrilaterals. `geometry_oracle_results.json` records every endpoint and source-pixel error. The maximum axis errors are approximately0.068431,0.068728 and0.032809 source pixels. These checks support the angle order and inverse-map direction for those known points; they do not certify real-camera point extraction.

The full60 fixture pipeline has an independent Python/NumPy implementation with no RTL-address trace dependency. However it repeats the B equations and cross-checks with B's scalar reference. The fixture detector/source is black-marker based. The HDL regression compares source corner metadata, native result writes and displayed pixels to those fixtures. This is meaningful transaction/arithmetic validation, but **not an independent real-world colored-grid rectification acceptance test**. It does not establish that the actual physical sheet corners were found.

## Smallest corrective scope

Keep B solver/core unchanged. Correct the C geometry front end to classify the intended colored markers, place their ROIs around the actual source locations, and reject low-confidence/background occupancy rather than merely loosening the black threshold. Record source-frame corner coordinates and H alongside frame generation. Before claiming corrected geometry, verify four marker endpoints and internal grid horizontal/vertical alignment against an independent source/target chart. Distinguish result-ready status from geometric acceptance.

No production RTL, frozen bitstream, constraints or other agent-owned files were changed by this audit. No PDS, long regression or board programming was run.

## Added black-marker materials: do not conflate coordinate spaces

The later supplied `materials/original_black_chart.jpg` is the original1586x992 test file. `materials/board_black_chart_output.png` is a photograph/screenshot of the board output that also remains tilted under CORRECTED. The colored-target output screenshot is separately preserved as `materials/board_colored_chart_output.png`. Source paths and SHA256 are recorded in `software_black_chart_reference.json`. Neither board output is the raw1920x1080 camera input. Original JPG corner coordinates must not be substituted for camera coordinates.

The black-marker failure means a color mismatch alone is not a sufficient explanation. Wrong physical ROI/background centroids remain a concrete hypothesis requiring per-frame selected-point/H evidence. Actual source RGB, selected points and bank identity must be traced independently; the label proves none of them.

`software_black_chart_reference.py` finds four compact black connected components in the original JPG, orders TL/TR/BR/BL, and uses OpenCV's independent source-to-target homography to produce `software_black_chart_765x1080.png`. Every selected centroid maps within0.001 target pixel of its assigned output corner. This is **only a software reference for the original file**, not a camera-input or board-output golden. The target retains the existing765x1080 convention; the printed640x480 text is not evidence for a different target ratio. This four-point example does not certify the printed grid's metric construction or the board's physical geometry.
