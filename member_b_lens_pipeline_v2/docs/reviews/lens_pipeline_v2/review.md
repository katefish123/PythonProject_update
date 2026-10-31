# Lens pipeline V2 code review

Status: complete. Mode: report-only. Base: c6a9966094d49152b6214b3c4f0b2c7ffee56617.

Reviewed the 28 changed and explicitly included untracked deliverables. Local correctness, testing, maintainability, performance, API-contract and adversarial passes all completed. No external review route was used.

## Actionable Findings

| # | Severity | Location | Finding | Response |
| --- | --- | --- | --- | --- |
| 1 | P2 | scripts/test_lens.py:86 | Acceptance gate passes with the independent oracle skipped | Separate unconditional float/fixed accuracy assertions and make the full gate require the oracle or report an incomplete run. |

When cv2 is unavailable, skipTest bypasses both the OpenCV comparison and the float/fixed accuracy loop; run_checks.py accepts its successful exit, counts the skipped method, and can print ALL_CHECKS_PASS. A fresh independent validator confirmed this claim. Confidence: 75. The current cv2-present validation evidence remains valid.

## Coverage

Calibration reuse and metadata, quantization, RTL widths/shifts, II=1 and E0-to-E9 timing, reset/tag alignment, legacy compatibility, signed cache bounds, ordered cache responses, one interpolation pass, and delivery docs were reviewed. The recorded source hashes matched; ten RTL targets passed, including 530 lens coordinate vectors and 835 composed transactions. No applicable in-repository standards file was found. There were no failed reviewers, demoted findings, malformed returns, or validator drops. No plan-based settlement suppression was evaluated.

Native ModelSim, PDS synthesis, timing/resources, board performance and optical acceptance remain outside this review's evidence. No source, tests, results, vectors or git state were changed.

## Verdict

Ready with fixes. Address #1's acceptance reporting before treating runs without OpenCV as fully verified.

Actionable findings: #1 P2, scripts/test_lens.py:86, acceptance gate passes with the independent oracle skipped; gated_auto, suggested fix present, confidence 75.
