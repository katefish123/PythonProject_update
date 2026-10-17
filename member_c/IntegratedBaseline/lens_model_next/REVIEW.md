# Independent review

Reviewer inspected actual source read-only under requesting-code-review. Found one P2: a profile sealed for one runtime mode could commit after the runtime mode changed. Reproduced ACTIVE_PROFILE_MODE_CHANGED_BUT_STILL_VALID in bank_runtime_red. Fixed by continuously qualifying active validity with current dimensions/mode, rechecking pending at frame commit and rejecting mismatches. bank_runtime_green and final bank test passed. Pending coefficients remain immutable; previous complete active data remains stored while invalid for the changed mode.

Follow-up review found no additional Critical/Important issue in reviewed arithmetic, bank or H-to-Brown snapshot logic. It flagged that the then-existing projective H family had zero Brown coefficients. Coverage was extended: family5 now has all four Brown terms plus a nonzero projective H prepared by raw-corner inversion; composed_inverse_green and final composed test pass exact coordinates/pixels. Software inverse preparation has separate5 tests; local convergence is not physical calibration or global inverse uniqueness.

Review and all qualification statements are limited to the synthetic sequential baseline. No PDS, hardware performance, real calibration or enterprise acceptance is claimed. V5C stays frozen.

Final read-only review of corner_preparation.py, its tests, vector generation and scope found no Critical/Important issue. It confirmed the Brown Jacobian/damped Newton update, explicit singular/nonconvergence rejection, recovered known ideal points and wrong-raw-H negative control. Combined inverse/H/Brown coverage uses one known synthetic quadrilateral and its sampled destinations; it is not a global inverse-domain proof. Current Python source hashes match the evidence receipt.
