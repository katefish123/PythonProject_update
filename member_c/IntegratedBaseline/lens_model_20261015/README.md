# Synthetic lens-model infrastructure

2026-10-17: these original independent Python models are reused unchanged by [the separate numeric RTL baseline](../lens_model_next/README.md). That new directory adds synthetic coordinate/parameter/H-composition tests; it is not integrated into V5C and has no real-camera/video-throughput/PDS acceptance. Historical scope statements below refer to this20261015 software directory.

**Synthetic only. No real camera calibration, RTL lens implementation, or hardware acceptance. Existing B files are untouched.**

`lens_golden.py` is a scalar standard-library float64 reference for normalized Brown radial k1/k2 and tangential p1/p2 distortion. Explicit fx/fy/cx/cy are mandatory. `FrameMap` captures an immutable profile/H snapshot; optional H maps destination pixels to the undistorted camera plane before forward distortion maps to raw source pixels. `Mapped.inside` uses strict source pixel-center bounds, including negative outputs. Resampling is a separate concern.

Run from this folder:

```text
python -B -m unittest -v test_lens_golden.py
```

Minimal usage:

```python
from lens_golden import FrameMap, load_profile
profile = load_profile("synthetic_profile.json", expected_size=(640, 480))
frame = FrameMap(profile)
raw = frame.map(100, 100)
print(raw.x, raw.y, raw.inside)
```

The JSON is deliberately named synthetic and cannot be treated as measured calibration. Loading requires exact fields and source size. `provenance="measured"` is rejected by this initial infrastructure. Changing crop/resize/orientation requires an explicit transformed K and validated profile, not a silent size override.

`lens_fixed.py` adds signed Q34.30 integer arithmetic, nearest-even rounding, explicit numeric rejection, signed bounds and zero-lens exact identity bypass. `FIXED_NUMERIC_DESIGN.md` records the contract and limits. Run `python -B verify_models.py`:17 tests,600 independent polynomial cases and5000 fixed/float comparisons, maximum sample error0.00753098925907 source pixel. This is not a full-envelope proof or an RTL result.

`verification.json` and `test_results.log` bind software results to source hashes. No dense image remap, inverse undistortion point solver, automatic calibration, B integration, hardware profile bank or board test is implemented. Numeric RTL and real-camera acceptance remain pending.
