# RX input diagnosis, 2026-10-23

Reuse the exact current qualified HDMI initialization. A standalone native1080p60 output displays atomic metrics sampled on both RX edges. No DDR or B algorithm participates. The low80bits are last-line width16, active lines16,pixels32,min-width16; next80bits are max-width16,period32,frame counter32. Rows1-2 are rising,3-4 falling,row5 RX FSM state/count/init/frequency record,row6 measured clock divider counts plus init/error flags. Row0 contains a fixed magic to reject incorrect capture orientation/decoding.

Native geometry monitor tests cover full1080p,changed blanking,and wrong720p dimensions. Independent review confirmed fields/CDC. PDS final all constraints met; unchanged provisional external-delay model is retained. Falling geometry stayed1920x1080/2073600pixels/2475000clocks for40samples; rising geometry fields inconsistent. This is a hypothesis about capture phase,not RGB acceptance or completed repair.

Next controlled candidate changes ONLY the physical top VS/HS/DE/RGB input register edge. Both input30/output60 and input60/output60 native application/DDR/HDMI regressions run,then full PDS and Program/Verify. Actual camera video must be observed before declaring the fault fixed. Frozen qualified image and both diagnostic attempts remain separately recoverable.
