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
