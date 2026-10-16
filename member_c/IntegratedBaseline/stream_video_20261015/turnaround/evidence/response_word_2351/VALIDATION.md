# Response word acceptance boundary

V4L 2317 routed report: all three worst UI paths start at core/stream_path/cache/fill_tag[7] and end at engine/response_word[0..2]/CE. Each has -1.166 ns slack, 10 logic levels, 2.484 ns logic and 6.102 ns routing. The cone contains cache address calculation, both arbitration address muxes, engine tag comparison, cache_hit, then response-word CE. The complete measured paths and report SHA are preserved here.

Fix: every accepted command captures cmd_addr[5:3] into response_word, independently of hit/miss/legality. Neither cache-hit handling nor final R beat changes it. Single-outstanding ownership retains it for any miss. On an old-response/new-command shared edge, consumers retire the old index before the nonblocking update installs the new owner. No state, cycles, response kind, arbitration, writer, bank/epoch, native protocol, constraints or clocks changed.

Test-driven boundary check: the old engine fails RESPONSE_WORD_ACCEPT_BOUNDARY_REQUIRED expected=3 actual=0 on its first miss. The revised engine passes all seven native cases with zero errors/warnings. The test still alternates 24 source/result cache hits on consecutive UI edges, checks every full block and selected word, and requires no new AR. Original tests retain all native protocol, capture burst, source block, cache invalidation, fault, timeout and reset checks. Green source hashes match before/after.

The engine is frozen at SHA256 1c1018c60d12571a4f8478eb5f444a6a0e36266a984513e8436183bb83787805. Root must generate the combined snapshot, rerun full-system throughput and obtain a new routed timing report. These unit results do not establish timing closure, nor does the previous V4L system run bind this newer engine.
