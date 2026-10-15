# Independent fixed-point integration fixtures

Run `python generate.py` to regenerate both sizes and all three variants.
Requires numpy and Pillow. Output defaults to this directory's `generated/`.
The generator never reads HDL requests, HDL output pixels, or simulation traces.

Sizes and corner order TL/TR/BR/BL:
- fullhd: source1920x1080, physical storage768x1080, logical765x1080, ACTIVE_X1.
  Corners (650,70),(1250,110),(1320,1010),(590,960).
  corners96=28a0464e206e5283f224e3c0.
- reduced: source128x48, physical storage32x48, logical29x48, ACTIVE_X1.
  Corners (34,4),(93,6),(103,42),(25,39).
  corners96=02200405d00606702a019027.

Each generated/<size>/variant0..2/ contains source.hex, expected_bilinear.hex,
expected_nearest.hex and matching PNGs, corners96.hex and metadata.json.
HEX is one six-digit RGB888 pixel per line, row-major with no header. Expected
HEX includes the physical left black column and two right black columns. Native
source has2073600 pixels; physical fullHD result has829440 pixels (logical826200).
Reduced source has6144 pixels and physical result1536 pixels.

Source is a native-resolution synthetic color/detail pattern matching the
integration bench's procedural source, with variant seeds11,29,43:
R=(addr+seed*13)%251; G=(addr//7+seed*29)%253; B=(addr//13+seed*41)%255.
The R component has pixel-level structure; other channels have different spatial
periods. Source patterns are distinct across variants. All variants share the
same nontrivial trapezoid within a size. A seed is source content identity; it
need not equal the processor's transport generation counter. There are no marker
detection assumptions: the external geometry input supplies the listed corners.
These charts check native detail/color paths, not camera optical sharpness or
subjective blur. No hardware acceptance or realtime result is claimed.

# Arithmetic audit

The existing inline_geometry_20261014/fixtures.py uses brect.fixed.solve_fixed,
then vectorizes the positive-coordinate inverse map and bilinear arithmetic.
This generator retains that integer model while making physical padding,
nearest mode, invalid-coordinate handling and source patterns explicit.
The B float model golden.py is used only by the legacy fixed module's input
validation; no float coefficients or float pixel samples enter this oracle.

Audited stages against original vendor/b/rtl:
1. homography_solver: compute determinant and g/k, divide each signed numerator
   separately with truncation toward zero, then compute each F24 H coefficient
   with the exact same ordered integer divisions. Validate convexity,40-bit H
   range, perspective envelope and all four denominator corners.
2. perspective_coord/scaled_div_pipe: compute signed64 MAC values, enforce positive
   denominator >2^20, nonnegative48-bit numerators, numerator/denominator<4096,
   then floor(256*numerator/denominator) to UQ12.8. Fixture coefficients/ranges
   fit signed64 including the temporary numerator*256; no wraparound occurs.
3. perspective_core: bilinear bounds inclusive at source last pixel, clipped
   right/bottom neighbor; nearest adds128 before shifting8 and uses one neighbor.
4. bilinear_interp: horizontal 256-weighted blends, then vertical blend and final
   right shift16, with no rounding. Intermediate ranges fit original16/24 bits.

Every generated H is compared exactly to the existing B scalar solve_fixed.
For every variant and method,1028 positions (corners plus deterministic random
pixels) are checked against scalar map_fixed/sample_fixed, totaling12336 checks
across6 fixture variants. All physical padding is independently asserted black.
Seven unit tests cover exact H translation, identity/padding, fractional blending,
nearest ties, invalid denominator, signed divide and degenerate corners. Initial
placeholder solver/reference failed real translation and physical-padding tests
before implementation. generated/manifest.json records input/reference source
hashes and metadata hashes; each metadata file records artifact SHA256 values.
