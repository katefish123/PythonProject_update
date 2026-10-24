# B V2 lens-only hardware experiment

User explicitly requested programming and confirmed R50/18mm/native1920x1080 plus powered board/JTAG/capture. This authorizes a temporary CRAM lens trial after integration checks and final PDS timing. Preserve original B ZIP and frozen V5C; never label the trial as final calibration or paper-boundary correction.

Reuse exact V5C capture,frame ownership,DDR cache/engine,writer,HDMI display and recovery. In a separate candidate, use B's delivered static lens_autocrop_instance for full1920x1080 output,including its bound trial calibration/effective H. Source admission bypasses marker qualification ONLY for this lens-only mode,still requiring complete DDR capture acknowledgement. Replace the fixed-map processor branch while retaining bounded request credits,ordered responses,tag checks,source generations and completion-after-writer-drain.

Default is corrected lens trial; hold KEY1 for untouched RAW comparison,KEY2 selects nearest interpolation. Same16:9 output,one source sample; global autocrop changes peripheral framing and does not implement the separate user paper-only/outside-identity requirement. Trial profile deploy_to_fpga=false provenance remains unchanged. No automatic paper detection,H fitting or old-marker erasure is claimed.

Before programming: native ModelSim B eleven tests,full native synthetic camera→actual application DDR path→HDMI pixel comparison against B integer reference,source/result ownership checks,final exact-source PDS implementation and all final timing summaries. Program/Verify through existing JTAG workflow only,not Flash. Any failed mandatory check blocks programming and is reported with logs.
