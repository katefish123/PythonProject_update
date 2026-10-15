# UI spatial quad cache

`ddr_quad_tile_cache` stores64 fully associative64x4-pixel tiles (64KiB data), keyed by immutable source bank base plus32-bit frame generation. A quad crossing tile boundaries protects all its existing hit ways before replacement. It fetches four aligned64-word rows through `cmd_block`; each returned2048-bit block contains eight256-bit native DDR beats. The native engine must honor source writes by invalidating its own address-tagged block cache.

The RAM has exactly two synchronous ports. Common hit quads read top and bottom DDR words in parallel. Crossing an eight-word boundary requires a second read cycle. Input lookup, RAM access and response use separate elastic stages. Response data stays stable while stalled. Faults are sticky until shared cache/engine hard reset; source generations survive soft processor aborts outside this module.

Supported parameters: source width multiple64, height multiple4, dimensions<=4096, aligned source bases and no28-bit word-address overflow; LINES power of2 and>=4. Production values1920x1080 and64ways. This is a source gather unit, not an HDMI controller or complete camera throughput result.

Fresh unit evidence:
- Legacy scalar cache:64 warm quads,512 UI cycles, exact RGB then expected throughput assertion failure (`red_serial`).
- New pipeline:64 warm quads,71 UI cycles including drain overhead.
- `verified64b`:397 exact quad packets,128 block commands, stalls, held-payload stability, DDR-word/tile/row/four-tile boundaries, nearest, last pixel clamp, outside black/no reads, bank change, bank reuse with new generation, watchdog, wrong response type, invalid coordinate and shared reset. Compile/simulation Errors0 Warnings0.
- Reduced8-way case exercises more replacement pressure; run `run_tests.ps1` without `-DefaultLines`.

Default-size synthesis/timing belongs to the integrated board candidate and is not implied by these unit tests.
