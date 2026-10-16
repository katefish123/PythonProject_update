# Top status text timing split

V4L's final PIX failure is a single path from the display VTC vertical counter
through the status glyph ROM and horizontal bit selection to `status_view/rgb`:
setup slack -0.243 ns. This module adds a 160-bit glyph row register before the
existing RGB register. All 448 glyph constants, the interface, status snapshot
at scan_start, colors, coordinates and output latency are preserved.

The established VTC changes y at the start of each timing line, 192 PIX clocks
before the first active pixel. The row register settles during this leading
blank. Equivalence therefore depends on that raster contract; arbitrary y
jumps during active video or immediate active video after reset are unsupported.

`run_tests.ps1` compares the original and replacement over all 32 status values
using the full 2200-by-1125 VTC mapping. It checks 3,932,160 visible status pixels,
75,267,840 blank pixels, all glyph rows, mid-frame live status changes, frame
snapshots and reset. The structural checker rejects the original unregistered
ROM path. Archived hashes and logs are in `evidence/`.

The generator installs only `status_overlay.v` at `rtl/video/status_overlay.v`.
The original source is a golden reference and must not be compiled alongside
the replacement under its unchanged module name. Physical timing remains a
separate PDS result; functional equivalence is not timing closure.
