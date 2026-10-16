# V4R engine complete-block validation

Exact measured V4Q seed29 path: completion_crossing/fifo/wr_release[0] through nested command ownership/address muxes, result_block_safe and illegal-command validation to engine/fault_reason[1]/CE. Slack -0.155ns,10 logic levels, logic1.610ns and route5.972ns. See summary.json and the bounded timing excerpt.

Only complete-block range combinational logic changed. An aligned64-word block fits [BASE,BASE+WORDS) iff its22-bit tag lies in [ceil(BASE/64),floor((BASE+WORDS)/64)). Constants use32-bit unsigned arithmetic, preserving nonaligned and empty/short regions and endpoints beyond28-bit command addresses. Supported WORDS are nonnegative signed integers through2^31-1. Result read-ahead reuses this result_block_safe signal with unchanged read/source-block qualifiers. Ordinary source word region membership is unchanged.

No FSM, native interface, fault/fault_reason update, response cycle, command ownership, image size, cache or beat-consumption logic changed. Illegal commands still fault on their accepting edge without AW/AR. ST_RSP still retires the old response and accepts the next command on the same edge. No extra command cycle or diagnostic fault delay was added.

The old code fails the new structural timing guard for per-request complete-span arithmetic. Old and new code both pass the semantic baseline:12 configurations and296064 directed/random address+flag checks, including unaligned BASE/WORDS,0/1/63/64/65,near/cross28-bit end,max positive integer WORDS,and write/source flags. This is an equivalent timing refactor; no old functional bug is claimed. Final candidate also passes native result burst protocol (normal/same-edge AW-W,stalls,bad last/ID,midburst timeout,illegal result commands,sticky faults/reset) and all seven original turnaround/native regressions. All final runs have zero errors/warnings and immutable before/after source hashes.

No full60/PDS/board run was started. Root must bind the new SHA into a snapshot and measure physical timing and complete-system throughput. Functional equivalence does not itself establish timing closure.
