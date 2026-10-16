# Read-only protection observations

Scope: frozen `c_stream_board_v4s_20261016` generated top/core/path; no protection code was changed and no new system fault injection was run.

Confirmed diagnostic issue: generated top lines65-74 latch the first memory_detail. Lines90-91 select that historical detail whenever proc reason==7. Thus a withdrawn ALIGN historical26 masks a later source-only generic7. The minimal red unit reproduces exactly those selector semantics. The dedicated fault LED aggregation at top line150 omits source; another LED receives frame_error, which includes source in core. Do not describe every LED as blind to source.

Potential, not a demonstrated system defect: top memory_fault is raw engine|PHY|ALIGN. Core's fault_sync and path's ui_fault_sync are multi-flop LEVEL synchronizers into proc. A one-UI-cycle ALIGN pulse can be shorter than a proc period and may be missed depending on phase. UI command gating suppresses new commands during the pulse, while proc abort is not guaranteed merely by this CDC form. A phase-swept core/native-engine fault injection must establish actual behavior before changing protection. The new diagnostic's UI history catches a sampled UI pulse but must not silently become protection.

Potential ownership review point, not a proved failure: core PROCESS error/abort emits source release credit immediately, while path comments and writer contracts permit already-owned queued traffic to retire. New launches are gated by writer_drained and generations discard stale reads. Current code intentionally relies on those contracts. The new observer neither proves all fault/credit combinations nor changes them. A separate native fault/abort/late-ACK/reallocation test is needed before altering source lease timing.

Expected hard-fault limit: engine sticky fault disables command acceptance until coordinated hard reset. Remaining queued writer ownership may therefore never drain under a hard engine stop; clearing only a writer/arbiter would forget owned commands. Diagnostics must not attempt recovery or independently reset those owners. Parent's coordinated-reset contract remains authoritative.

Unchanged response routing: turnaround arbiters retain owner through response, with response routing independent of new-command enable. The generated outer core qualifies app_r with actual cmd_valid&&cmd_ready. No mismatch was established by this read-only review. No unproven protection fix was made.
