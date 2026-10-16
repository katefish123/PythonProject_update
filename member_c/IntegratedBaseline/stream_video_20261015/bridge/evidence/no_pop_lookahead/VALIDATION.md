# Remove downstream pop lookahead from FIFO reads

The V4M routed report has UI WNS -1.339 ns, starting at cache/tags[55][1]
and ending at bridge/requests/fifo/empty_reg through 11–12 logic levels.
The cache's combinational hit/ready decision fed the adapter's same-cycle pop
lookahead, then the FIFO read pointer/Gray/empty calculation.

The adapter now issues reads only when registered reserved count is below four.
It does not borrow capacity from a downstream pop in the current cycle. FIFO
data/valid are registered at the read edge and reach skid at the next edge;
the invariant is reserved = count + rd_valid. A fully stocked queue resumes
continuous output with count 4,3,2,2,..., or 3,3,2,2,... if one read is pending.
Removing the lookahead preserves order, capacity and one-packet-per-clock
steady throughput without adding a transaction stage.

Fresh original/candidate packet and quad-bridge regressions all pass with zero
errors/warnings. The candidate covers full/stalled output, stable payload,
asynchronous clocks, reset/restart, all 1024 ordered packets twice, 1600 quad
metadata packets and invalid-descriptor faults. Consecutive throughput is 796
packets in the stream test and 1334 in the quad test. The original routed
failure, source snapshots and exact log hashes are bound in binding.json.

An independent read-only review found no proven P1/P2. Continuous throughput
requires upstream data; initial filling and genuine FIFO exhaustion still
cause normal bubbles. This proof depends on the current FIFO read latency.
New full-system and physical PDS checks remain separate requirements.
