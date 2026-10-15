# Main-B lens correction compliance audit — 2026-10-15

Remote: https://github.com/katefish123/PythonProject_update.git
Live `git ls-remote --heads` main-B: **4106f3babb65096927d365bbab55f070b90325e2**.
Commit date: 2026-10-12 19:26:42 +0800. Subject `fina_v3`; body describes black corner detection with unchanged interface.
Snapshot: `D:/FPGA/output/b_audit_20261015` (depth-one partial sparse clone).
No production worktree, existing A snapshot, board, OBS, or external chats changed/accessed.

## Scope and version distinction

Inspected tracked `final/` docs, RTL, Python, scripts, simulations, JSON config/evidence, and both small tracked archives:
- `member_b_perspective_black.zip` (2,229,140 bytes), newest black-marker variant, 327 archive entries.
- `member_b_perspective_final.zip` (1,747,555 bytes), earlier RGB-marker variant, 545 archive entries including Mac metadata.

Extracted relevant text only to `archive_text/`; `archive_inventory.json` preserves complete archive entry lists and archive hashes. No large simulation databases or vector/image sets extracted. All archive text/source/config filenames scanned for calibration/lens/intrinsic/distortion names; none found. Source searches for k1/k2/p1/p2, radial/tangential, calibration, intrinsics, undistortion also inspected. P1/P2 hits are corner identities; lowercase p1 is a synthetic quadrilateral, not tangential p1. `fx/fy` are interpolation fractions, not focal lengths.

In evidence below, **BLACK/** means the member `member_b_perspective_black/` inside the exact committed `member_b_perspective_black.zip`; local readable copy is `archive_text/member_b_perspective_black/member_b_perspective_black/`. This matters: tracked `final/` remains the older RGB-marker package, while the latest black implementation lives in ZIP.

## Findings and classification

| Requirement | Classification | Exact evidence |
| --- | --- | --- |
| Four-corner perspective correction | Implemented | BLACK/python/brect/golden.py:108-128 solves an independent 8x8 H system and applies rational H mapping. BLACK/rtl/perspective_coord.v:7,27 accepts nine H coefficients and computes three affine MACs followed by division. |
| Radial k1/k2 correction | Missing from all audited deliverables | BLACK/README.md:180 explicitly says lens distortion is not handled. BLACK/python/brect/golden.py:124-128 and :150-160 go directly H -> source sample; no radius polynomial. BLACK/rtl/perspective_coord.v:27 similarly has only H. Tracked final/README.md:96 explicitly excludes lens correction too. |
| Tangential p1/p2 correction | Missing from all audited deliverables | Same complete math paths above; no xy/r2 tangential terms or lens coefficient ports. P1/P2 in BLACK/rtl/b_rectifier.v:7-12 identify TR/BR ROIs. |
| Camera intrinsics K (fx/fy/cx/cy) | Missing from all audited deliverables | BLACK/rtl/b_rectifier.v:3-28 lists dimensions, statistics, black thresholds, ROIs, video/memory ports only. BLACK/python/brect/cli.py:20-32 loads threshold and ROI files only. No K input, principal point, focal length, image-size-calibrated profile, or normalization/projection stage. |
| Actual lens calibration provenance | Missing; real camera performance unverified | BLACK/examples/integration_config.json:94-108: camera_tuning.status=not_run, raw_rgb_sample_paths=[], exposure/white_balance/lighting=null. BLACK/docs/validation_record.md:125-136 real camera section is not_run/pending. BLACK/docs/provenance.json:3-20 documents rotation source hashes, board manual, prior conversation and delivery path, not a camera calibration. |
| Parameters loaded at runtime | Implemented only for software marker thresholds/ROIs; lens loading missing | BLACK/python/brect/cli.py:25-32 reads threshold and ROI JSON. BLACK/examples/integration_config.json:5-8 says record_only=true, rtl_reads_this_file=false; final hardware values require instance override and recompilation/synthesis. BLACK/docs/interfaces.md:40 explicitly identifies static compile/synthesis parameters. |
| Atomic frame-boundary commit | Implemented for H only; lens-bank commit missing | BLACK/rtl/b_rectifier.v:41-48 has nine solved/active/pending H values; :51-53 forwards pending for first pixel on commit; :68-74 atomically installs H on dst_frame_start and handles solve completion. BLACK/docs/interfaces.md:89-93 defines collision semantics and notes state is not a source-frame ID. No lens or K bank/version/write interface exists. |
| Independent lens-model golden | Missing | BLACK/python/brect/golden.py:108-128 is an independent homography reference only. BLACK/python/brect/fixed.py:29-67 mirrors H solver/map. BLACK/scripts/make_demo.py:25-39 synthesizes images solely using a homography inverse and black squares; :48 calls it Synthetic camera input. No calibrated camera or nonzero lens-distortion reference vectors. |
| FPGA/board validation for lens correction | Unverified and structurally unsupported | BLACK/results/verification.json:6-9 explicitly excludes PDS timing and board/camera/DDR/HDMI testing. Existing pass evidence validates H path/black detection, not a lens model. No audit-time RTL tests executed. |

The ZIP black `rtl/perspective_coord.v`, `rtl/perspective_core.v`, `rtl/homography_solver.v`, and `python/brect/fixed.py` are byte-equivalent to tracked final/ after newline normalization. Black detection is a real later feature, but it does not add lens correction. Four raw distorted corners can be aligned by H while lens-curved interior straight lines remain curved; a single planar homography is not a substitute for the missing nonlinear model.

## Minimum independent infrastructure to add (proposal, not implemented)

1. Versioned calibration profile, separate from marker tuning: camera/lens ID, sensor mode, width/height/crop/resize/orientation, K (fx,fy,cx,cy and declared skew assumption), k1,k2,p1,p2, model name, coordinate convention, units, provenance type (`synthetic` or `measured`), calibration capture hashes, target dimensions, observations used/excluded, estimator/version/settings, per-view and overall reprojection errors, profile hash. Never label a synthetic profile as real calibration.
2. Standalone float64 Brown-Conrady reference independent of fixed/RTL code. Normalize ideal undistorted pixels: x=(u-cx)/fx, y=(v-cy)/fy; r2=x*x+y*y; L=1+k1*r2+k2*r2*r2. Compute xd=x*L+2*p1*x*y+p2*(r2+2*x*x), yd=y*L+p1*(r2+2*y*y)+2*p2*x*y; project using K to the raw source coordinates. Handle invalid/nonfinite/out-of-range coordinates explicitly.
3. Define mapping direction and H domain first. For destination-to-raw-source sampling, use H from destination to the **undistorted** camera plane, then forward lens distortion to raw coordinates, then one final sampling stage. Current detected raw corners must first be undistorted by a separately validated iterative inverse before H solving. Otherwise add-lens-after-current-raw-H double-counts/misdefines corner geometry. The alternative is a declared full undistortion pass before all existing processing, at extra memory/bandwidth cost.
4. Independent nonzero synthetic coordinate/grid fixtures: zero distortion identity, radial-only barrel/pincushion, k2-only, p1-only, p2-only, all terms, off-center principal point, unequal focal lengths, corners/edges/center, negative/out-of-frame samples, size/crop mismatch rejection, H+lens composition. Assert each nonzero coefficient changes expected interior coordinates so an H-only implementation cannot pass. Check with an independent trusted projection implementation or precomputed high-precision values; keep golden equations separate from fixed quantization.
5. Fixed/RTL acceptance infrastructure: explicit coefficient formats/ranges/rounding and error budget in source pixels; compare RTL coordinates to independent float64 truth plus fixed model, then RGB sampling with declared tolerance. Include disable/bypass and zero-coefficient compatibility with current H path. Do not extend the current signed/positive coordinate assumptions silently.
6. Add explicit calibration load/validation and atomic pending/active bank for complete K+distortion profile (and H/profile association). Validate full bank before commit, carry profile/version with in-flight transactions or capture all coefficients per request, switch only at destination-frame boundary, and test partial write/reset/invalid profile/commit collision/stalled old requests. If compile-time-only is chosen instead, declare that contract and rebuild from the versioned profile; JSON must not be presented as controlling RTL.

## Practical conclusion

Latest main-B has genuine homography/perspective correction, black-marker ROI updates, software threshold/ROI loading, and atomic H commit. True radial/tangential camera-lens correction, intrinsics, real calibration provenance, and lens-profile loading/commit are absent from both expanded tracked source and the newest ZIP source. Existing camera tuning is explicitly not run. This conclusion is based directly on latest main-B, not a C snapshot.
