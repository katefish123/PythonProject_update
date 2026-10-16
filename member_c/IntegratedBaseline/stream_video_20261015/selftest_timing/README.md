# DDR self-test timing split

The final V4K physical timing report identifies UI setup WNS -2.792 ns from
the engine response selection through a 256-bit equality reduction to
`core/selftest/passed`. This replacement keeps the pattern, reserved addresses,
write/read ordering and sticky failure contract. A read response now captures
eight independent 32-bit equality results; the following UI cycle reduces those
eight registered bits and advances the read index or final status. No timing
exception is introduced. This adds one UI cycle per self-test read, before any
video transaction can start.

`run_tests.ps1` checks 516 cases: normal/restart, every single-bit error in the
first and final beat, a middle-beat error, an incorrect read response type,
command backpressure and stable final status. The explicit response-to-status
latency check fails on the original V4K source with
`RESPONSE_COMPARE_NOT_PIPELINED`. Physical improvement requires a fresh PDS run;
unit simulation alone cannot establish setup slack.

The continuous candidate generator installs this file at
`rtl/memory/ddr_self_test.v` and includes its SHA in `stream_sources.json`.
Original A snapshots are preserved.
