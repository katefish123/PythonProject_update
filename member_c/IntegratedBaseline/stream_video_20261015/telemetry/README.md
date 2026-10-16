# Frame telemetry overlay (isolated source module)

`frame_telemetry_overlay.v` exposes the requested PROC-to-PIX telemetry interface. It has no dependencies and does not modify or instantiate image processing, solver, DDR, or preview logic. Add it to the parent project and composite `on ? rgb : existing_rgb` at the same PIX-domain coordinates. `x`/`y` are active-video coordinates (0-based); `scan_start` is a one-cycle pulse at the beginning of the output frame, before the first telemetry glyph. `scan_de`, `image_valid`, `scan_start`, `x`, and `y` belong to `pix_clk`. `image_valid` only gates the overlay; it is never sampled by PROC.

## Input semantics and displayed text

All 32-bit statistics and the 512-bit rejection vector belong to `proc_clk`. `displayed_frame_id` must identify the result actually selected for display; `display_age_ms` is its total age since BEGIN capture allocation, including capture time. The caller supplies that age; this module does not rebase age at publication. This makes a held, blurred old result visibly distinguishable from a fresh result. A new publication that is not displayed must not change the displayed ID/age pair.

The first row shows `AGE  000.0S` in green (`40ff80`) for age below 250 ms, and `HELD 023.2S` in orange (`ffb040`) for age at least 250 ms. Tenths are truncated, so 32 ms displays `000.0S`, 249 ms displays green `000.2S`, and 250 ms displays orange `000.2S`. Ages saturate at `999.9S`; they never wrap. Orange is an age indication, not a diagnosis of camera focus or a solver failure.

Subsequent rows show ten decimal digits, preserving the complete unsigned range 0..4294967295:

| Label | Input |
|---|---|
| FRAME | displayed_frame_id |
| PUB | published_frames (connect core good_frames) |
| CAP | admitted_frames (BEGIN allocations, not every sensor frame) |
| REJ | rejected_frames |
| MARK | reject_reason_counts[3*32 +: 32] |
| SHAPE | reject_reason_counts[12*32 +: 32] |
| OVER | reject_reason_counts[13*32 +: 32] |
| SOLVE | reject_reason_counts[4*32 +: 32] |

The row origins are y=80,112,144,176,208,240,272,304,336. Glyphs are a 5x7 uppercase/digit font scaled 2, using 16x16 cells with 32-pixel line pitch. The initial x is 16; numeric counters start at x=112. The entire decode region is x=16..271 and y=80..349, with the final possible ink x=265. It stays well clear of the portrait beginning at x=577 (logical width 765, storage width 768). `on=0` outside glyph ink and whenever image_valid or scan_de is low. `rgb` is only meaningful when `on=1`.

## Conversion and CDC

`PROC_CYCLES_PER_MS` defaults to 54000 for 54 MHz and must be positive. A free-running tick offers a snapshot each millisecond; occupied mailbox ticks are skipped. Nine parallel iterative double-dabble converters take 32 cycles followed by a mailbox commit cycle. There is no 32-bit divider/modulo in the pixel path, and cell/line decoding uses bit slices of power-of-two geometry.

The complete BCD snapshot and held flag form a 361-bit bundled mailbox. The source commits it and toggles request, then holds every bit unchanged until the receiver ACK returns through three PROC synchronizer flops. The request passes three PIX synchronizer flops. The receiver copies the stable mailbox to `shown` and ACKs only on `scan_start`; every telemetry value therefore remains unchanged for the whole displayed frame. The source cannot overwrite a pending snapshot. A stopped or delayed PIX clock backpressures telemetry without tearing. This is a one-entry mailbox: a held pending sample can be older than the newest available statistics by one output frame; output formatting does not increase camera refresh rate.

Reset both sides using the common hard reset, with deassertion managed appropriately for each clock domain. Independent resetting of just one side is unsupported because it can change a toggle epoch. The synchronizer registers carry ASYNC_REG attributes. Physical implementation must preserve the bundled-data assumption: request/ACK synchronizers must be recognized and the mailbox-to-shown data settling bounded relative to the three-stage request latency. Do not infer hardware CDC or 148.5 MHz timing closure from RTL simulation; those require the parent build's constraints and physical checks.

## Reproducible simulation evidence

Run `run_tests.ps1 -Suffix final` using ModelSim at `D:/softwares/modelsim/win64`. Logs and exact source hashes go to `D:/FPGA/output/c_frame_telemetry_20261015_final`.

The test uses asynchronous 54 MHz / 148.5 MHz clocks and an accelerated 80-PROC-cycle update tick. It checks: held 23.2 s; recovery at 32 ms and changed frame ID; complete unsigned 32-bit decimal conversion; age saturation; exact 249/250 ms threshold; reason counter routing; no mid-frame update; stopped PIX with counter churn; 24 randomized frame ACK delays; common-reset recovery; all 8192 pixels in each complete held/fresh age-line region against an independent reference font; precise RGB; invalid-image/blanking gates; and sample no-overlap positions beyond x=560.

`run_mutations.ps1` creates two altered RTL copies only in its unique output folders. Removing the frame-boundary condition is caught by `snapshot applied mid-frame`. Removing ACK protection is caught by `mailbox changed without ACK`. Their expected failing simulation logs are evidence of negative-test sensitivity, not failing production RTL. The original test-first RED stub was also caught by `mailbox snapshot never arrived`.

These are simulation results only. No board programming, optics/sharpness acceptance, actual 60-new-frame/s claim, or other pipeline source modification is included.

## Integration snapshot latency

The actual system updates displayed ID/capture timestamp after DACK returns to PROC. This mailbox then samples both fields atomically and applies its snapshot at a later scan_start. During continuous60Hz image changes, FRAME/AGE normally refer to the previous displayed generation. Snapshot age is roughly16ms at the start of a scan and can approach33ms by its end. Values are coherent with each other but are not guaranteed to identify the image currently being scanned. Internal1ms resolution and displayed0.1s truncation are separate from this snapshot latency. Do not use this HUD for per-frame end-to-end latency measurement; system regressions use independent generation/publication/HDMI records.


## 2026-10-15 routed PIX path repair

The actual v4k routed report (`D:/FPGA/output/c_stream_board_v4k_20261015/build_unqualified_20261015_2240/report_timing/video_correct_ddr_top.rtr`, worst PIX path near line 1844) identifies the failing path: `core/display_reader/timing/v_cnt[4]/.../CLK` to `core/display_reader/rgb[8]/.../I5`, through scan_y and the HUD counter/character/font/pixel decode. Final routed WNS is -3.558 ns across 51 PIX endpoints (the earlier after_hold_fix summary was -3.455 ns/46). The path has ten logic levels, 9.829 ns data delay: 2.471 ns logic and 7.358 ns routing. This physical failure is the timing regression that motivated the change; a zero-delay RTL test cannot reproduce routed propagation delay.

The renderer now prefetches each character during the preceding 16 raster pixels. At x mod16=0 it registers row/column/vertical validity; at phase1 it registers the selected counter value; at phase2 it registers the character; at phase3 it registers its 35-bit glyph; at phase4 it registers the required 5-bit font row. At phase15 it loads that prepared row into the active pixel register for the next character cell. The final output path consists of a five-bit pixel mux plus horizontal/valid gating. All vertical decoding, BCD selection, ASCII selection, and font lookup end at registers. No output latency is added: glyph ink remains at the exact existing x/y positions, and the previous API and snapshot semantics are unchanged. No false-path or multicycle constraints were added.

The interface now explicitly requires a raster stream: x increases by one each PIX cycle and each active line traverses x=0..15 before the first glyph at x=16. Prefetch operates even when scan_de is low. Arbitrary coordinate jumps without scanning preceding pixels are unsupported. y must remain stable for the active line. Reset clears the prefetch state; the normal first sixteen pixels of any line rebuild it before ink can be shown.

`run_tests.ps1 -Suffix v4k_raster_after -Top tb_frame_telemetry_raster` scans two complete 2200x1125 timing frames at 148.5 MHz PIX and 54 MHz PROC. Both the original combinational renderer (`v4k_raster_before`) and the repaired renderer (`v4k_raster_after`) match an independent expected image at every coordinate: 4,950,000 checked timing pixels total, 16,656 ink pixels, all nine rows, held/fresh RGB, blanking, glyph boundaries, and the portrait exclusion region. `v4k_unit_after2` retains mailbox backpressure, reset, saturation, 249/250 ms boundary and 24 randomized ACK stall checks, now using sequential line scanning for pixel observations. Both runs report zero compiler/simulation warnings or errors. The added glyphoffset mutation deliberately shifts the glyph pixel selection and must fail the full-raster checker.

These tests verify coordinate preservation and protocol behavior. Root integration must rerun physical implementation to establish the repaired PIX slack and any remaining worst path. No timing-closure claim is made from these simulations.
