# C streaming correction development, 2026-10-15

This is an unqualified development candidate, not the board release.

The current corrected image has only 640x904 effective pixels on a 1920x1080 HDMI canvas. The new target is 765x1080 effective portrait pixels, keeping the existing portrait aspect to integer-pixel precision and letterboxing the sides. DDR stores 768x1080: one black pixel at the left and two at the right. This is 42.8% more effective samples, not a promise of restored camera focus or full-width 1920-pixel detail.

The other measured bottleneck is sequential four-pixel DDR reads, followed by interpolation and a blocking result write. The new path separates coordinate production, queued four-neighbour gathering, the unchanged B interpolation pipeline, and queued result writes.

## Ownership and contracts

- `processor/`: public hard reset, soft abort, persistent 32-bit generation, ordered physical output tags, logical solver width765. B RTL stays unchanged.
- `bridge/`: immutable source-bank base and generation per request; elastic asynchronous packet queues; no soft reset.
- `cache/`: UI-clock spatial cache, 64x4 pixel tiles, 64 ways. Each row fetch returns 64 32-bit source words (eight native DDR beats). Hit gathering uses two RAM read ports; a quad crossing an eight-word boundary uses a second read cycle. Requests protect all current-quad hit ways from eviction.
- `engine/`: explicit aligned source-block request and full 2048-bit return, preserving native DDR protocol checks and legacy command behavior.
- `writer/`: pack eight RGB pixels into one beat, queue writes across clocks, latch destination bank at frame start, publish only after all acknowledgements. Abort must drain already-owned writes.

## Required evidence

1. Failing throughput evidence for the old serial gather; passing pixel/metadata and backpressure tests for the new cache and bridges.
2. Independent identity and nontrivial geometry scoreboards, padding, stale generation and abort recovery.
3. Native DDR integration with full1920x1080 source and effective765x1080 result; report measured publication intervals, not HDMI scan frequency.
4. Re-run implementation and timing with the actual processing clock. A single 27MHz lane cannot process the target49.572M corrected pixels/s even ideally.
5. Preserve the frozen main-C handoff and board bitstream. No hardware-quality or60newframes/s claim until qualified measurement. Compare the same focused camera scene directly against corrected output to assess physical sharpness.
