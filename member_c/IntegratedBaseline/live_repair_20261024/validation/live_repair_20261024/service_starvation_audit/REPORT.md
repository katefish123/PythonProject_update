# Shared DDR service regression — exact c129 production RTL

The adverse run reproduces a first successful RAW publication followed by FIFO overflow, reason-13 rejection, display underrun, and no subsequent publication. The same camera stimulus under fast DDR service passes three publications and all 552,960 checked display pixels. No production RTL, package, hardware, or PDS was changed.

## Actual observations

| Observation | control_2 | adverse |
|---|---:|---:|
| Successful publication / PIX image ID | 3 / 3 | 1 / 1 |
| RX overflow close reason 13 | 0 | 3 |
| Manager rejection reasons 12 / 13 / 14 / 15 | 0 / 0 / 0 / 0 | 0 / 3 / 0 / 0 |
| FIFO peak | 2 | 1024 |
| FIFO queue-not-ready sampled cycles after first publication | 0 | 844 |
| Display pixel mismatches | 0 | 834825 |
| Display underrun sticky | 0 | 1 |
| Engine fault / source fault | 0 / 0000 | 0 / 0000 |

Adverse summary: physical frames=9, admitted=5, dropped=3, rejected=3. First publication occurs at 2.290423 ms; first display mismatch occurs at 2.300776 ms. RX closes generations 2, 3, and 4 with reason 13. No reasons 12, 14, or 15 are asserted. Accepted capture transactions=2606, display transactions=7462; longest continuous capture-valid/not-ready wait=322 UI cycles. There are 930 delayed read and 338 delayed write transactions. Compilation has zero errors/warnings. The adverse simulator has exactly one deliberate fatal, `SERVICE_STARVATION_REPRO`, and zero warnings at 9.240464 ms. Its process returns zero because the batch script quits after the fatal; this is a reproduced design failure, not a passing functional run.

## Stimulus and interpretation

This bench uses the real continuous core, BIST, capture RX, 1024-entry FIFO, 8-beat capture writer, managers, display client with existing priority arbitration, and production DDR engine. All 45 production sources match the formal package qualification hashes. The package bitstream SHA256 is `c12913626e11352f5fbeefe468c63bfd52718209212561d4ca727ad741f65c22`.

To keep the regression small, camera and output dimensions are 128x1080 and requested mode is RAW. UI, RX/PIX, and processor clocks retain the original bench periods (8 ns, approximately 6.734007 ns, approximately 17.508074 ns). Camera blanking is HS/HB/HF=4/8/16, VS/VB/VF=2/4/4. The original pixel pattern/golden comparison is retained. The bench collects mismatches after the first failure to preserve rejection evidence. BIST completes normally before capture.

The control model serves the first read beat after 4 UI cycles and begins writes without added delay. The adverse run is identical until the first actual publication. In each subsequent camera frame's upper active half, newly accepted AR and AW transactions wait 320 UI cycles before the first R or W beat; the lower half restores fast service. Each transaction captures its delay at address acceptance. These waits remain below the engine watchdog limit. The RAM model has no PHY or calibration behavior.

This hypothetical clustered service schedule proves that the actual RTL can lose further publications through recoverable RX overflow while both hard-fault outputs remain zero. It does not establish the actual board's latency distribution, reproduce corrected-mode processing, explain the independent missing HUD observation, or quantify fullHD throughput. The board's previously reported first-beat maxima alone do not establish the frequency or clustering modeled here. No fix is claimed.

The cause chain agrees with production RTL: `continuous_capture_rx.v` line 89 latches overflow when a data packet lacks queue space; line 38 gives overflow reason 13. `manager_raw.v` lines 29–30 preserve a nonzero writer rejection reason, and lines 61–62 increment its histogram. Such rejected frames return their bank and do not require a permanent source fault.

## Reproduction and bindings

Run `prepare_service_bench.py` to regenerate the independent bench. Run `run_service.py control_LABEL` and then `run_service.py adverse_LABEL` with distinct new labels; the runner invokes the actual ModelSim vlib/vlog/vsim programs and refuses existing output directories. The existing verified runs are `control_2/` and `adverse/`. They contain copied production RTL, generated bench, full command arguments, return codes, and three complete logs. Run `finalize.py` for offline source/log/argv validation and root `verification.json` regeneration; it starts no simulation.

The `control/` directory preserves an initial independent bench declaration-order compilation failure. It is excluded from successful evidence. It was corrected only in the bench generator before either verified run. No production RTL or golden pixel values were changed to obtain these results.
