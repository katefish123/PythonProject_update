# Plate_Window_Scorer A-02R1 baseline

This simulation directly instantiates the implementation RTL in
`source/rtl/Target_Analysis_Top/Plate_Window_Scorer.v`. It does not contain a
replacement or behavioral copy of the DUT.
## Pre-run implementation identity

Recorded before creating this simulation on 2026-07-11:

- `source/rtl` manifest: 37 files, SHA-256
  `42AC9FB82E043DEBA4E5EAF2AD9E8D978C5163AC6BCCEBF6DD3944B160B5A868`
- `Plate_Window_Scorer.v`: SHA-256
  `C2A38A2A3B0B4B547E112F3A415DF50E93006CCD719D00711534A07C8DC037F9`
- `HDMI_IN_DDR3_YCbCr_top.fdc`: SHA-256
  `2CFE392C23EC3F7440CD93A90054639FB34D9199CC0E10688DD44B8CCAC7DA9B`
- `HDMI_IN_DDR3_YCbCr.pds`: SHA-256
  `85E8DB5049486CF8FE8FEA3F06DC482B56CCCCD1E1ED734DF941937D217222EF`
- `impl.tcl`: SHA-256
  `E2CB29BE548E6E0A3C4903224EF8D56716EDF80DDA6AC43A1FCCBD24F1D1F99D`
- `HDMI_IN_DDR3_ROI_top.sbit`: SHA-256
  `B671BC60AA45EE19626AB1ED676184875FDD02A197EF487AE2F7A70D86B87D6C`

## Run

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\sim_prj\plate_window_scorer_sim\run.ps1
```

Exit code `0` means every self-check passed. Compile errors, simulator errors,
missing PASS markers, or any test failure return a non-zero exit code.

Outputs are recreated under `results/`:

- `compile.log`
- `sim.log`
- `run_summary.txt`
- `plate_window_scorer.wlf`

## Fixed configuration

- Clock period: 6.734 ns
- Image and DE raster: 1920 x 1080 active pixels
- Random seed: `0x5A172026`
- Scorer parameters: the values used by `HDMI_IN_DDR3_ROI_top`
- Every subcase asserts reset independently

The strict stimulus covers x=300..359. Input expansion produces 62 edge hits
and 61 color hits per row, so the independent expected row score is
`62 + 61*20 = 1282`. The strict raw box is expanded from x=292..368 to
x=272..388, then normalized to x=222..438.

The loose stimulus is one edge/color source hit at x=500. Expansion produces
three edge hits and two color hits. It fails strict edge>=4 and passes loose
edge>=2. Its raw fallback box is (448,322)-(553,378), and its normalized box is
(397,292)-(603,408).
## Independent expected results

All coordinates use the current RTL's inclusive endpoints.

| Case | Winning score / color sum | Raw bbox | Normalized and public ROI | w x h / area |
| --- | ---: | --- | --- | ---: |
| S-00 | 0 / 0 | invalid | invalid | 0 |
| S-01 | 5128 / 244 | (272,288)-(388,315) | (222,241)-(438,361) | 217x121 / 26257 |
| S-02A | 7692 / 366 | later: (272,388)-(388,417) | (222,342)-(438,462) | 217x121 / 26257 |
| S-02B | 7692 / 366 | earlier: (272,288)-(388,317) | (222,242)-(438,362) | 217x121 / 26257 |
| S-03 | 43 / 2 | (448,322)-(553,378) | (397,292)-(603,408) | 207x117 / 24219 |
| S-04 | 5128 / 244 | strict: (272,288)-(388,315) | (222,241)-(438,361) | 217x121 / 26257 |

The even normalized sizes in S-03 expose a current implementation detail:
`half_w = norm_w >> 1` and inclusive `center-half .. center+half` endpoints turn
an internal `norm_w=206`, `norm_h=116` into public dimensions 207x117. The
baseline records this behavior; it does not correct it.

At the first clock containing `frame_event`, the internal raw and normalized
candidate is checked while the public ROI must remain unchanged. The public ROI
is checked on the following clock, when delayed `frame_eval_top` commits it.

## Cases

- S-00: empty frame, no ROI.
- S-01: one four-row strict candidate.
- S-02A: later six-row candidate beats an earlier four-row candidate.
- S-02B: earlier six-row candidate beats a later four-row candidate.
- S-03: loose-only fallback.
- S-04: strict candidate has priority over a loose row; public ROI remains
  stable during the frame and updates only through the existing frame-event
  pipeline.

This baseline intentionally does not test tracking loss, far-target switching,
the top-level ROI coordinate CDC, scorer pipelining, Top-K, or multi-box output.
