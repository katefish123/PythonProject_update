# Timing-prefetch evidence

This archive separates the old combinational baseline from the frozen repaired RTL. `manifest.json` hashes every archived source/log and lists every source binding. Run the read-only `../../verify_timing_results.py` to check all hashes, successful-run markers, exact expected failures, runtime source hashes, and deterministic mutant transformations.

Positive logs are copied in full (all less than 64 KiB); raster_before uses E407D58F... rather than the repaired B9C84822... source. Both raster runs check 4,950,000 total timing coordinates and 16,656 ink pixels. unit_after2 covers held23.2s/recovery32ms, saturation, threshold, reset, mailbox stability, and 24 random ACK delays.

The three negative tests were rerun with frozen current RTL and current benches. Before/after SHA256 records verify these sources and the runner did not change. Every mutant is archived and reconstructed from one exact source transformation during verification. Logs intentionally contain exactly one Fatal and `Errors: 1, Warnings: 0`; mutation_result.txt records that the intended failure was caught. Detailed expected failures and their meaning are in each manifest case. These are successful negative tests, not failures of the production RTL.

Current run_tests.ps1 hash is an archive-time snapshot; only RTL and bench were contemporaneously hashed in the older positive runs. Old evidence files in the parent directory are preserved and excluded. The old routed failure excerpt documents the reason for the repair; these simulations do not establish repaired physical timing closure.
