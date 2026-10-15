# Continuous video integration

`video_correct_ddr_continuous_core.v` joins source admission/geometry, streamed B correction, complete native-write retirement and frame-boundary HDMI publication. Sources keep their bank/generation immutable until release. Result banks cannot be reused until the display acknowledges its new bank. Processing errors release/count once; persistent path faults remain visible outside processing.

Default DDR word regions are source0=0, source1=0x800000, result0=0x200000, result1=0x400000, BIST=0x600000. A static elaboration check rejects overlapping configured regions. The source image is1920x1080; result storage768x1080 with765 active portrait samples/row.

All domain reset inputs and the external native engine must share asynchronous hard-reset assertion. Locally synchronized releases may differ. Soft abort drains accepted writes/reads instead of resetting transaction ownership. Independent resets are unsupported. The board top derives all local resets from one app_reset_async.

Telemetry records admission, processing, publication and display generation, common millisecond capture timestamps, displayed-image source age, source drops and per-reason rejects. AGE is source age of the displayed corrected result, including capture; it is not a measured shutter-to-photon delay. A bad marker frame retains the prior complete image. The overlay exposes HELD age instead of labeling repeated HDMI scanout as new video.

`prepare_board.py` constructs the base continuous-capture/result-burst candidate and installs the independent telemetry overlay. The repository-level `prepare_current.py` applies later display-block, fair-arbitration, retirement and57.115MHz processing optimizations in separate output snapshots. No generator permits hardware replacement.
