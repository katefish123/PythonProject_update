# DDR display block reads

The new display reader requests aligned64-pixel result blocks instead of eight separate8-pixel public commands. The engine returns all eight completed native beats through the arbiter-owned block-response bus. It retains ID, LAST, timeout, cache invalidation and single-command ownership checks. A result cache hit also returns the whole block; final-beat forwarding includes the current native beat.

The two synchronous line buffers and row-completion mailbox remain. Every row is acknowledged only after every local beat is stored. The pixel-side bank changes only at frame boundaries. Output widths not divisible by64 retain the one-beat compatibility mode.

`run_tests.ps1` passes six tests: complete result block data plus legacy word, result read-ahead, source prefetch, source capture burst and explicit source-block behavior. The pre-change engine fails the new DISPLAY_BLOCK_REQUIRED check. Complete generated-board native DDR/HDMI tests live in ../continuous_system_test.

Measured full-HD-source12-image experiment (v4): every9953280 corrected pixel and19906560 HDMI window pixels matched; processing fell from roughly19.1ms to17.5ms under the same memory contention. Publication remained about33.5ms; this does not establish60 distinct corrected frames/s. The subsequent balanced outer arbiter reduced processing to about17.05ms.

These snapshots are not timing/hardware accepted. Later cache-fill/retirement variants remain separate and do not mutate the baseline evidence.
