# DDR internal fixture diagnostic build

This isolated project drives the production DDR capture and image-correction path from an on-chip 1920x1080 raster. It is intended for testing when the camera source is unavailable. The fixture is built only in this directory; the release DDR top, DDR IP, timing constraints, and correction core remain untouched.

The raster generator runs from the board's 27 MHz system clock and feeds the normal `ddr_snapshot_capture` interface. Every active input pixel is generated from the fixed 640x480 source mapping used by the capture sampler: `source_x = input_x / 3`, `source_y = ceil(input_y*4/9)` (the two terminal rows that reach 480 are clipped to 479 because they are not sampled by the source decimator). The source contains a grayscale 32-pixel checkerboard and four solid 8x8 markers only: red `(100,60)`, green `(540,90)`, yellow `(570,420)`, blue `(70,390)`. The asymmetric marker placement gives exact integer centroids under the RTL round-half-up centroid rule.

The golden source and expected 320x452 rectified image use the independent `vendor/b/python/brect.fixed.rectify_fixed` oracle, with corners checked by `golden.detect_markers`. The generated 1920x1080 preview images show the source raster and the expected result at the core's native 2x scale, centered in the active area. Generated assets and `fixture_metrics.json` are under `fixture/`.

This top sets HDMI `TX_FIRST=1` and its internal diagnostic `hdmi_ready` waits only for the transmitter's `tx_done`. It does not use the camera receiver or its initialization result, so this readiness rule is only valid for this fixture build. DDR initialization, the real DDR self-test, and the core's memory-fault gates remain enabled; the correction pipeline still must capture, write, process, and display the fixture through DDR.

Run `build_internal_fixture.ps1` to regenerate the golden files, run the ModelSim source-raster comparison, then synthesize, map, place, and route in the private `results/internal_fixture_ddr/` directory. The ModelSim check reports `test_passed=1` only after all 691,200 sampled active pixels match and all 480 source rows were covered. The PDS source list uses the preserved HDMI implementation from `reference/baselines/ddr_before_hdmi_startup_fix/rtl/hdmi/` and the standard DDR board constraints. The script never invokes a programmer or JTAG operation.

The expected HDMI image is [expected_hdmi_window_1920x1080.png](fixture/expected_hdmi_window_1920x1080.png); the raw expected rectified image is [expected_320x452.png](fixture/expected_320x452.png).
