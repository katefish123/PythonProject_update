# Executable fixed-point software contract — RTL pending

Status: `lens_fixed.py` implements this integer contract; `verify_models.py` records17 passing float/integer tests. No numeric RTL, synthesis/resource result, calibrated camera, measured camera residual, or hardware acceptance is supplied. Synthetic coefficients must never be copied to a camera as calibration.

## Model and envelope

Brown k1/k2 radial and p1/p2 tangential model with zero skew, no k3/rational denominator/thin-prism/fisheye terms. Scalar float reference accepts source sizes 2..4096; fx,fy in [1,65536] pixels; cx in [0,width-1], cy in [0,height-1]; abs(k1,k2)<=1; abs(p1,p2)<=0.25; normalized abs(x,y)<=4. These are engineering test bounds, not a physical invertibility guarantee. Negative radial factor/folds can occur within this broad synthetic envelope: forward remap remains defined; inverse calibration/optimization requires a separate monotonicity policy.

Optional H is row-major destination -> undistorted camera pixels and is applied before the lens polynomial. Do not feed current B's raw-corner H into this stage unchanged. Raw detected corners need separately validated inverse undistortion before H fitting. No inverse-point solver or calibration estimator is implemented here. Output is raw source pixel coordinates and strict center-inclusive inside flag, without image sampling.

## Candidate arithmetic

Software baseline: signed64-bit Q34.30 storage;34 integer bits include sign. Range [-2^33,2^33-2^-30]. Python integers model signed128-bit products/division numerators, with explicit checks before rounding into64-bit storage. Integer additions are checked before storage. There is no FPGA resource or throughput claim; narrowing requires further range/error analysis.

Encode fx,fy,cx,cy,k1,k2,p1,p2 and H as Q34.30 by round-to-nearest, ties-to-even. Product of Q30 values is Q60; round once by 30 bits before Q30 storage. Add/subtract Q30 without rounding; check signed range. Division (normalization/H): compute (signed numerator_q << 30)/denominator_q in a sufficiently widened signed operation, round to nearest ties-to-even using signed quotient/remainder, then check range. Never implement negative rounding with an unsigned shift. No saturation/wrap: reject invalid/overflow as an explicit invalid mapping, preserve the destination tag and emit the integration-defined black sample.

Proposed fixed H envelope: unsigned 12-bit destination x,y; each H coefficient abs<=65536; positive denominator >=1/16. This is deliberately stricter than the independent float oracle's >1e-12 denominator, and is not B's H format. Tests must classify numeric-envelope rejection separately from true source-boundary rejection. Source bounds are checked before conversion to unsigned addresses; optional final 1/256-pixel coordinate format must keep signed out-of-frame values until inside decision.

## Range checks

For normalized abs(x,y)<=4, r2<=32; r4<=1024; abs(radial)<=1057. Either tangential coordinate contribution has abs<=24. Thus abs(xd,yd)<=4*1057+24=4252; projected raw coordinates have abs<65536*4252+4096<2^29. These polynomial/projection storage ranges fit Q34.30. Full H division can exceed its storage range before the normalized-domain check, so widened quotient range checks remain necessary. Compute intermediate polynomial products in 128 bits, reject before narrowing. These are magnitude bounds, not an error guarantee.

## Error budget and acceptance gates

Future RTL target: max abs(raw_source_fixed-raw_source_float)<=0.125 source pixel per axis on a declared accepted operating set. Signed Q*.8 floor conversion adds <1/256 pixel. The5000 current integer/float samples have maximum error0.00753098925907 source pixel. This sample result is not a full-envelope proof, RTL result or real lens residual. H division/polynomial sensitivity amplify coefficient quantization; near sampling boundaries RGB/inside may differ.

Measured set: `test_synthetic_operating_set_error`,40 synthetic profiles×125 integer destinations;1920×1080, fx913.7/fy901.55/cx960.25/cy539.75; k1±0.3,k2±0.15,p1/p2±0.01; H scale0.9..1.1,cross terms±0.02,translation±20,projective terms±0.00002. Boundary agreement is asserted when the float boundary distance exceeds coordinate error. Exact zero-lens identity bypass retains integer image edges without reprojecting quantized normalized coordinates.

Before accepting RTL: broaden extrema/near-denominator/negative/edge sweeps, compare actual RTL coordinates/tags against both models and derive a bound over the chosen real operating domain. Verify resource/timing and actual calibration residual separately. The integer model does not sample images or issue DDR requests; real calibration error is outside this synthetic error budget.

## Parameter and frame consistency

FrameMap stores a frozen Profile and copies H into an immutable tuple. A producer creates a new FrameMap only at the software destination-frame boundary and retains the old object for every in-flight request from that frame. This isolates references from external list mutation; it is not a running frame controller or hardware commit bank.

Future hardware needs validate-complete pending bank + atomic active-bank switch, profile hash/version, H/profile association, reset/partial-write/commit-collision tests, and old in-flight request ownership. Existing B pending/active logic commits only H. No connection to B, camera controls, DDR, display timing, or RTL parameter loading is made here.
