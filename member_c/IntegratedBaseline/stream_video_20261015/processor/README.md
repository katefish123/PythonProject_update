# Streaming processor interface

`frame_processor_stream.v` uses one clock and a public active-low hard reset.
Parameters: SRC_W=1920, SRC_H=1080, OUT_W=768 (physical storage stride),
OUT_H=1080, ACTIVE_W=765, ACTIVE_X=1, FIXED_IDENTITY=0,
TIMEOUT_CYCLES=300000000. Compile with SystemVerilog enabled.

Control inputs: clk, rst_n, start, abort, nearest, input_geometry_valid,
input_corners[95:0] = {x0,y0,x1,y1,x2,y2,x3,y3}, each coordinate 12 bits.
Start is accepted only in IDLE. Geometry/mode latch on accepted start.
Outputs: busy, done, error, failure_reason[3:0], cycles[31:0],
completed_pixels[31:0], geometry_valid. done/error are pulses.
Failure reasons: 3 missing geometry, 4 solver rejection, 5 watchdog,
11 coordinate/response/output order, count, or queue invariant violation.
Abort returns to IDLE and flushes math/queues, with no error/done pulse.
Generation advances on every accepted start, including rejected starts,
and resets only on public rst_n. Do not connect a session soft reset to rst_n;
use abort. Start during busy is ignored. Hold abort low when starting.

Request ready/valid: q_valid, q_ready, q_inside, q_nearest,
q_addr00/q_addr10/q_addr01/q_addr11[23:0], q_tag[23:0],
q_fx/q_fy[7:0], q_generation[31:0]. Address units are RGB888 source pixel
indices, excluding external bank/base. Tags are physical {row[11:0],col[11:0]}.
For padding, q_inside=0; addresses remain don't-care (no DDR read needed).
q payload is stable while stalled. q_generation is the current frame generation.

Response ready/valid: r_valid, r_ready, r_inside,
r_p00/r_p10/r_p01/r_p11[23:0], r_tag[23:0], r_fx/r_fy[7:0],
r_generation[31:0]. Return accepted requests strictly in order and preserve
metadata. Old-generation responses, and responses while IDLE/SOLVE, are drained
without reaching the B interpolator. Hold the response payload while stalled.

Writer ready/valid: write_valid, write_ready, write_addr[23:0], write_rgb[23:0].
Address is contiguous physical output ordinal [0,OUT_W*OUT_H). done is emitted
only when the final write has been accepted. The enclosing owner must also wait
for destination DDR drain before publishing. Output payload is stable while stalled.

Physical x is clamped to logical [0,ACTIVE_W-1] before entering B; padding gets
q_inside=0. The corner adapter is instantiated with OUT_W=ACTIVE_W. Original
B solver, coordinate, and interpolation modules are referenced without edits.
Coordinate credits and descriptor queue are 256; output reservations and pixel
queue are 64, including interpolation stages, so downstream stalls cannot overrun
B's pipeline without ready signals. Responses are credited until actual write acceptance.

# Verification

Run `run_tests.ps1 -Suffix <unique>` for identity and add `-Solver` for the original
C corner adapter plus original B solver. Runs write compile/simulation logs and
source hashes to D:/FPGA/output/c_stream_processor_unit_20261015_<unique>.
The runner explicitly checks for Fatal/Error text and the PASS marker because
ModelSim may return exit zero even after a Verilog $fatal.

The 16x24 physical fixture has active width13, left padding1/right padding2.
It checks every output against software bilinear arithmetic, identity coordinates,
nearest metadata, padding black, source-out-of-bounds black (identity), affine
and trapezoid corners (solver), stalls exceeding the output queue capacity,
384 pixels exceeding coordinate credits, abort/restart generations and late stale
responses, tag corruption/recovery and watchdog. Solver additionally checks missing
and rejected geometry. Observed 106 consecutive accepted writes in both modes.
These are reduced-size simulation results, not full-resolution board/DDR throughput.

Test-first fixture was written before RTL but its initial failing run was omitted;
this is not strict TDD. A deliberate padding-removal mutant subsequently fails the
real padding assertion (pixel0 nonblack), documenting sensitivity to that bug.
`padding_mutant.txt` is solely the negative test input, never an integration source.
