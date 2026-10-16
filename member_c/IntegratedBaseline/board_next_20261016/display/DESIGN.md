# One-VTC RAW / CORRECTED DDR display candidate

Approved interface, 2026-10-16. This isolated candidate derives from frozen S `ddr_result_display_block64.v`; frozen RTL and B are unchanged. Root owns publication policy, source-bank leases and grant-qualified command sideband routing.

One display instance and one VTC serve the1920x1080 canvas. RAW reads a full1920x1080 source bank at1:1. CORRECTED reads a768x1080 result bank at1:1, centered horizontally, retaining765 active columns plus its three stored black padding columns. No preview downsampling, stretching or marker/H dependency participates in RAW scanout.

`publish_raw` is a bundled payload with `publish_bank`, held through ACK; the existing toggle handshake changes mode only at frame_start. `display_raw` reports the PIX-locked mode. PIX->UI row requests hold mode/bank/internal-generation/row through the row acknowledgement. Stored-line metadata matches all four fields. UI request mode controls source/result base, stride and row length, and drives `cmd_source_block`; root must qualify this sideband by actual arbiter grant. Native rows comprise30 RAW or12 CORRECTED64-word commands and240/96 packed RAM beats.

Existing OUT_W/H, SCALE, BASE0/1 describe corrected storage. New SRC_W/H and SOURCE_BASE0/1 describe raw storage. The supported contract is SCALE=1, equal source/result height, widths divisible64, both windows fitting the active canvas. RAM capacity is max(SRC_W,OUT_W)/8 entries per parity buffer. Publication and row mailboxes retain the original shared-hard-reset contract.

Optional PIX outputs `scan_frame_pulse` and `image_swap_pulse` expose scan boundaries and actual accepted publications for external accounting. They do not alter ACK behavior. A repeated scan does not cause a swap pulse.

Tests first fail with a wrapper around frozen S (RAW publication remains CORRECTED). The isolated candidate must then pass alternating RAW banks, CORRECTED banks, mode round trips, moving RGB24 sequences, addresses/stride/block boundaries, command stalls, late old-mode responses, reset, exact pixel coordinates and first/last pixels. Small tests use different RAW/CORRECTED widths; native tests use1920-wide source rows and the765+padding corrected layout. No full-system/PDS/hardware qualification is implied.
