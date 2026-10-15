# Continuous native source capture (candidate, integration pending)

`continuous_source_path.v` replaces the request-toggle source capture boundary.
Existing snapshot capture, session modules, current board v2 and B math were not
modified. This directory is an isolated candidate source path; root owns the
result-bank session, correction pipeline and HDMI publication integration.

## Required sources

Compile the five `continuous_*.v` files in this directory, the existing
`bridge/async_packet_stream.v`, baseline `rtl/memory/async_packet_fifo.v`,
`rtl/algo/marker_detector.v` and `vendor/b/rtl/unsigned_div_seq.v`.
`build_modules.py` regenerates the geometry adapter/top wrapper only; it copies
parameter names from baseline geometry but leaves B detector math unchanged.

Default parameters: IN_W=SRC_W=1920, IN_H=SRC_H=1080, BURST_BEATS=8,
DATA_FIFO_ADDR_BITS=10 (1024 packets), FIFO_ADDR_BITS=9 (selected marker events),
SOURCE_BASE0=0, SOURCE_BASE1=0x0800000, PROC_CYCLES_PER_MS=54000.
Marker threshold, ROI and MIN/MAX parameters match existing capture_geometry.
The source must be native resolution; dimensions must match and width be divisible
by8. Total pixels must be divisible by64 for complete8-beat capture bursts.

## Top interface

Inputs rx_clk/proc_clk/ui_clk, one shared hard rst_n, enabled, rx_vs, rx_de,
rx_rgb[23:0]. enabled is synchronized internally into RX. Asserting rst_n resets
all source identities, queues, joins, timestamps and ownership. The same hard reset
must reset the native DDR command engine. There is no session/abort soft reset.
Disabling enabled stops admission at subsequent VS edges; admitted frames remain
owned until their final VS validation and accepted writes retire.

Proc descriptor ready/valid outputs: frame_valid, frame_bank,
frame_generation[31:0], frame_corners[95:0], frame_geometry_valid,
frame_capture_ms[31:0]. Input frame_ready. Corners pack TL/TR/BR/BL as twelve-bit
{x0,y0,x1,y1,x2,y2,x3,y3}. Descriptor payload remains fixed while stalled.
Only a frame with final valid RX shape, every expected DDR burst acknowledged and
valid matching geometry gets a descriptor. frame_geometry_valid is therefore1
whenever frame_valid=1. Consuming a descriptor locks that bank for the processor.

Proc release pulse inputs: release_valid, release_bank,
release_generation[31:0]. Release after corresponding processor done or abort.
A mismatching/stale generation, duplicate release, release of an unconsumed ready
frame, or release of a free bank is ignored and sets sticky fault. Matching release
returns credit through the proc->RX FIFO. It cannot overwrite another generation.
The parent must preserve processor generation rules for any old source reads that
remain after a processor abort. This path does not reset the quad/cache pipeline.

UI command outputs: cmd_valid, cmd_write=1, cmd_addr[27:0], cmd_wdata[255:0],
cmd_wstrb[31:0]=0xffffffff, cmd_burst_data[2047:0]. Input cmd_ready.
Addresses count32-bit RGB words and are aligned64 words. Eight256-bit beats carry
64 source pixels, with a zero high byte in every RGB888 word. Payload stays fixed
while stalled. Inputs rsp_valid/rsp_write acknowledge the complete accepted
8-beat command. The native engine must have CAPTURE_BURST_BEATS=8 and route one
write response after all physical beats retire. No source-block read flag is set
for these capture writes. A bad write response is a sticky protocol fault.

Telemetry (proc domain): admitted_frames[31:0], dropped_frames[31:0],
rejected_frames[31:0], last_failure_reason[3:0], reject_reason_counts[511:0], fault.
Admitted counts bank-allocated RX frames; dropped counts enabled VS arrivals with
no free bank. Both RX counters cross as registered Gray values through3 FF stages.
Rejected counts admitted frames rejected after writer+geometry join. Reasons12
shape/VS validation,13 source FIFO overflow,14 writer order/protocol,15 pixel count,
3 marker geometry. reason r count is reject_reason_counts[r*32+:32]. Simultaneous
two-bank rejects increment total and reason buckets twice, even for the same r.
fault marks ownership/protocol violations, not ordinary invalid frames or overrun.

## Timestamp contract

A common-reset proc clock counter produces milliseconds using
PROC_CYCLES_PER_MS. The per-bank timestamp is captured when its authoritative
allocation BEGIN reaches the proc manager. It is retained through ready stalls and
processor ownership; it is not replaced by end-VS time. With the default54MHz
clock and54000 prescaler, the root can use its identically reset/prescaled ms clock
for unsigned published source age. This includes roughly the16.7ms native capture
interval, with BEGIN FIFO/CDC arrival latency and1ms quantization explicitly part
of its precision. FIFO overload can delay BEGIN; invalid overloaded frames never
produce good descriptors. There is no wall-clock/USB/HDMI optical latency claim.

## Ordering and safety

RX owns two bank bits from allocation until matching returned credits. Each VS
rising edge validates the previous admitted frame and independently allocates a
free bank for the next frame on that same edge. BEGIN/DATA/END320-bit packets hold
bank/generation/address/status/RGB. The local eight-entry queue permits two control
writes on a VS edge and reserves four entries for controls; DATA is dropped with
an invalid-frame mark when its reserve is exhausted. END remains queued under
FIFO-full. A third frame with both banks occupied is dropped in its entirety,
without overwriting either bank. Reuse waits for joined write ACK and geometry
retirement, including rejected frames.

Each BEGIN fans out atomically to UI capture packets and proc allocation events.
The marker adapter forwards selected black ROI pixels plus framing through its
own asynchronous FIFO and invokes the unchanged marker_detector. A matched RX
input tap cuts the capture-counter to ROI/FIFO timing path. Marker completion may
precede allocation when UI data is backpressured: the proc manager retains that
future result with ready=0 until matching BEGIN arrives. Last sampled pixel is
not frame completion; END waits for the next VS and rejects extra rows, wrong
width/height, incomplete words and overflowing frames.

## Verification and limits

`run_tests.ps1 -Suffix <unique> -Top tb_continuous_source` runs the reduced coupled
suite; add `-Native 1 -Frames 60` for1920x1080 native1080p60 raster source flow.
`-Top tb_continuous_manager` exercises joins, timestamps and credits independently.
The default legacy test intentionally fails: unmodified snapshot capture completes
only3 captures over6 valid frame boundaries, proving the alternate-VS admission
limit before the new design.

Reduced suite checks exact captured RGB and zero padding, all accepted8-beat
ACKs, six consecutive frames, immutable geometry/generation, malformed extra
height/short width/short height, retained END under FIFO-full, overrun drops,
matching/stale releases and shared hard reset. Manager suite additionally checks
future metadata before BEGIN, descriptor/timestamp stalls and reset, simultaneous
same/different reason counters and duplicate credit rejection. Native suite checks
all source pixels and marker descriptors at real1080p60 timing; it uses a mock
processor release after1ms and a burst-response memory contract model.

These are source-path tests. Full correction+HDMI/native DDR contention tests,
actual60 distinct corrected frame publication and PDS physical timing remain
integration requirements. Do not infer end-to-end60fps or board acceptance from
source capture alone.

## Frozen candidate evidence (2026-10-15)

- `c_continuous_capture_20261015_manager_telemetry`: PASS timestamp/reset,
  same/different rejection collisions, future metadata hold, stale/duplicate credits.
- `c_continuous_capture_20261015_reduced_overflow_restart`: PASS normal and all
  malformed/source-FIFO/selected-marker-FIFO/clock-stall/reset cases.
- `c_continuous_capture_20261015_native60_telemetry`: PASS60 distinct native frames,
  124416000 source pixels,1944000 burst8 commands and ACKs, zero drops/rejects.
- `c_continuous_capture_20261015_frozen_native6`: PASS from a precompile source
  snapshot of the final bench and same five RTL files; source_hashes.txt binds them.

All four runs compile and simulate with zero errors and zero warnings. Native60
used the same frozen RTL; reduced-only test cases were added to the bench while
that long run proceeded. The final snapshot run binds the exact final files.
Simulator `%t` descriptor stamps in the logs are picoseconds despite the original
printed time_ns label; verification.json normalizes interval numbers to ns.

`verification.json` records log/source hashes and explicitly leaves full corrected
HDMI60fps verification false. `verify_results.py` rechecks these results.
The runner now copies sources before compilation, so parallel test edits cannot
change the recorded sources of a running verification.
