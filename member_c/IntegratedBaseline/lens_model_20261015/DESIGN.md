# Synthetic lens-model reference design

Current implemented scope: independent Python Brown k1/k2/p1/p2 float reference and executable fixed integer model. No existing B files are edited. Real camera calibration, numeric RTL, runtime hardware profile loading and board acceptance remain to be completed; synthetic coefficients are never real calibration.

Chosen approach: scalar standard-library float64 oracle and explicit signed Q34.30 arithmetic, with immutable profile and per-frame H/profile snapshots. Synthetic unit vectors can validate future RTL before real calibration is available; actual camera acceptance still requires measured parameters and held-out images.

Mapping: destination pixel -> optional H -> ideal undistorted camera pixel -> normalize by fx/fy/cx/cy -> forward Brown distortion -> raw camera pixel. H must be fitted in the undistorted domain; current B H fitted to raw distorted corners cannot be reused unchanged. Pixel centers are integers, x right, y down; H is row-major. Output reports raw source coordinates and inside flag; sampling is deliberately separate. Invalid inputs reject explicitly.

Tests precede implementation: analytic identity/radial/tangential/sign cases; independently expanded polynomial reference; H order; boundary rejection; frozen frame snapshots; synthetic JSON loader and dimensions. Integer tests add signed nearest-even ties, zero-lens exact identity bypass, explicit numeric rejection, signed bounds, and 5000 comparisons on a declared synthetic operating set. This never implies an RTL pass or a global error proof.
