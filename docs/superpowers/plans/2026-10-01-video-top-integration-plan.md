# Video Top Integration Implementation Plan

## Task 1: Add a failing top-level integration test

- Create `02_simulation/tb_video_top.v` with reduced 14×7 timing parameters.
- Check blanking, sync/de, all four pattern selections, and internal VTC-to-TPG connections.
- Add `run_top_check.do`.
- Compile before `video_top.v` exists and confirm failure is specifically caused by the missing top module.

## Task 2: Implement the minimal synthesizable top module

- Create `01_design_code/video_top.v`.
- Centralize timing and pattern parameters.
- Instantiate `u_vtc` and `u_tpg` and connect internal counters.
- Run the new top-level test and confirm it passes without warnings.

## Task 3: Add compile-time signal-name protection

- Add `` `default_nettype none`` and a matching restoration to all three design files.
- Re-run the top-level test after the protection is enabled.

## Task 4: Verify regressions and document the result

- Re-run the existing TPG test.
- Re-run the existing complete 1080p-frame test.
- Update README, module documentation, and result summary.
- Review the complete diff and confirm that no pipeline, AXI, TMDS, audio, PLL, pin constraints, or MS7210 initialization was introduced.
