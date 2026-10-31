# 自动去黑边完成记录

Code review: complete. Run `20261022-174753-29335249`; receipt and six reviewer outcomes are in the adjacent run directory. The independent validator confirmed both findings. Cross-model review was disabled by the checkout configuration; the local adversarial review completed.

## Simplification

The reuse and efficiency passes found no justified changes. The quality pass moved the existing H-file parser into the shared viewport module so the hardware exporter no longer imports the image CLI, and removed an unused test import. These changes preserve parser behavior and were included in the final regression.

## Review fixes

| Finding | Resolution | Verification |
| --- | --- | --- |
| #1: default CLI command overwrites the historical uncropped comparison | README and integration guide now write to `results/lens_autocrop_demo`; defaults distinguish requested H from planned effective H and document `--border keep` | Targeted command/path inspection; `git diff --check` |
| #2: uniform fixture cannot detect an extra interpolation on the crop path | CLI acceptance uses patterned RGB edges, requires actual cropping, and compares both saved outputs exactly against one direct render from the original source with the planned effective H | Targeted CLI test and final complete regression |

Two disjoint fix batches were delegated, one for documentation and one for the acceptance test. Both findings are applied; none are skipped or deferred. No source arithmetic or datapath change was needed after review.

## Final validation

`python3 -B scripts/run_checks.py` completed with `ALL_CHECKS_PASS` after both fixes: 10 baseline Python checks, 8 lens checks with the OpenCV oracle, 7 viewport checks, all 11 RTL targets, and 11 Tcl script-control checks. The new actual-wrapper test passed 13,046 transactions with zero outside requests, both sampling modes, and reset flushing. The final report hashes the source files and all six consumed autocrop build inputs.

The native 1920×1080 image was rendered through both CLI models and the preview/masks were visually inspected. Full-grid float and exact fixed validity checks cover 2,073,600 output positions: 9,735 outside before planning and zero after planning. The real checkerboard's black squares remain unchanged as image content. The float/fixed RGB maximum channel difference is 1 in this example.

## Scope and operational validation

This is a local algorithm package, not a deployed board image. No additional operational monitoring is required for this local delivery. A/C demonstration files are outside the write-back manifest. The original B files are hash-checked and backed up before replacement.

Future board integration must use the bound configuration and match source/output dimensions; any calibration or H change requires replanning. PDS synthesis, native ModelSim execution, board frame rate/latency, and independent optical accuracy are not established by these tests. The supplied camera profile remains `deploy_to_fpga=false`.
