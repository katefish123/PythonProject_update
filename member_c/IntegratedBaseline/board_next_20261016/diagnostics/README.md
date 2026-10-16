# Candidate fault diagnostics (observation only)

Frozen production RTL is untouched. `fault_diagnostics_stream.v` is a synthesizable, isolated observer. It has no command, abort, source-credit, owner, protection or reset output. Integrate only as diagnostic signals; do not replace protection with its delayed CDC observations or sticky history.

## Contract and API

Inputs: `proc_clk`, `ui_clk`, common hard `rst_n`; UI-owned `ui_engine_fault`, `ui_engine_reason[3:0]`, `ui_phy_fail`, `ui_align_error`, `ui_self_fail`, `ui_stage[3:0]`, `ui_dqs_valid[3:0]`; proc-owned `proc_source_fault[3:0]`. Source nibble is opaque raw data: preserve the new core's documented four-route ordering. Do not connect unsynchronized raw RX/UI source bits here. Existing default remains `TICK_BITS=48`.

`current_mask[4:0]` bits0..4 mean source,engine,PHY,ALIGN,self-test. All concurrent causes remain visible. `current_kind[2:0]` uses NONE0,SOURCE1,ENGINE2,PHY3,ALIGN4,SELF5 and that fixed priority. Priority is a display selection, not a claim of causality. `current_raw_reason` is the unchanged source nibble when source is present, otherwise raw engine reason if engine fault is present, otherwise zero. `current_source_fault` and `current_engine_reason` retain independent qualified raw values. `current_fault_any` includes source and is derived exclusively from current_mask. A historical ALIGN can never change a later source-only current classification. Boolean PHY/ALIGN/self reasons are identified by mask/kind, not synthetic legacy codes25/26/27.

`current_ui_tick`, `current_ui_stage`, `current_dqs_valid` describe the UI sampling edge. `current_source_proc_tick` is when the received source snapshot was sampled in proc; `current_source_received_ui_tick` is its arrival in UI. `source_snapshot_valid` distinguishes reset from having received a coherent source update. The UI faults are sampled once per UI edge. Source current is a periodically refreshed coherent CDC snapshot, not an instantaneous proc signal.

`first_valid`, `first_mask`, `first_kind`, `first_raw_reason`, `first_engine_reason`, `first_source_fault`, `first_ui_tick`, `first_source_proc_tick`, `first_ui_stage`, `first_dqs_valid` freeze the first event OBSERVED IN UI. They do not feed current selection. This is UI observation order, not globally time-aligned physical cause order. The separate `source_first_valid`, `source_first_fault`, `source_first_proc_tick`, `source_first_received_ui_tick` retain the first nonzero source event even when the CDC mailbox was busy and the pulse has already cleared. Such a delayed source-first history event can set first_mask bit0 while current_mask bit0 remains zero; that is intentional history/current separation.

Counters run modulo2^TICK_BITS, with local synchronous reset release after the shared asynchronous assertion. They are independent clocks/units and must not be numerically compared across domains. At125MHz,48bits wrap after26.06days;32bits wrap after34.36seconds. Convert UI/proc tick deltas with each actual clock rate. First records stay immutable across wrap; long elapsed intervals still need the usual modular-range interpretation.

## CDC and pulse limits

The single bundled mailbox contains `{source_now4, proc_sample_tick, source_first_valid, source_first_raw4, source_first_proc_tick}` (9+2*TICK_BITS bits). Proc captures its first nonzero event independently of mailbox availability. A req/ack toggle handshake refreshes snapshots on every completed round trip. Req and ack each pass two ASYNC_REG flops. Payload remains unchanged from request until the returned acknowledgement is observed. UI reads it after the synchronized request has arrived; the extra sequential detection edge provides settling time. Unit assertions check hold-until-ACK and received field coherence.

Either stopped clock delays delivery; diagnostics never unblock or reset ownership. Later short source transitions may coalesce, but the first source event cannot be overwritten. UI pulses must intersect a UI sampling edge; sub-cycle/asynchronous PHY pulses need an appropriately specified upstream capture/synchronizer. ui_stage and ui_dqs_valid must be UI-owned observations. If not wired, tie them to zero and mark context unavailable in the integration manifest rather than interpreting zero as measured training state.

Both domains must assert rst_n together; no one-sided soft reset is supported. Reset release is synchronized locally. Shared reset while UI is stopped is tested and old requests do not replay. This candidate adds no timing exceptions. The eventual integration still requires CDC implementation review and routed timing checks, including held-data settling before the UI mailbox capture; digital simulation is not analog metastability or physical CDC signoff.

## Integration sketch

Instantiate in the new candidate only. Connect engine/PHY/ALIGN/self-test from their current UI signals; connect root's new proc source-fault vector and preserve/document its bit order. Connect UI-local phase/DQS context if available. Consume current fields for live labels/diagnostic LED and first fields as explicitly historical records. If an LED is consumed in another clock domain, synchronize that scalar there. Any multi-bit HUD/export requires its own coherent snapshot transfer; do not repeat the legacy per-bit bus synchronizer pattern.

Do not override a current source reason with historical memory_detail. Do not feed first_valid/history into memory_fault or alter hard/soft reset, abort, native command gating, bank release or source lease. This observer neither measures RAW motion nor marker quality and cannot attribute HELD/stale video to movement. RAW tracking and marker validity need independent measurements.

## Tests and evidence

`run_tests.ps1` runs the identical injection suite with TICK_BITS48 and8 using independent14ns proc/8ns UI clocks. The default case passes38 coherent updates and134 payload-hold checks; the8-bit case passes121 updates,382 hold checks and2 UI timestamp wraps. Both have zero errors/warnings and before/after source SHA bindings. Cases include historical ALIGN clearing then source-only raw7, one-UI-cycle ALIGN, sustained ALIGN, secondary engine reason5, all concurrent causes, all source bits/multi-bit raw codes, UI stopped with mailbox busy and one-proc-cycle source pulse, source clear without false current fault, common reset while stopped/inflight, and history retention over wrap.

`tb_legacy_fault_red.sv` is a minimal reproduction of the frozen top's selector expressions, not a full-board test. It fails `HISTORY_OVERRIDES_CURRENT_SOURCE` with source7/history26 as expected. Final module tests pass that scenario. No full60,PDS,hardware or frozen core/top edit was performed. See evidence/summary.json for exact source/log hashes and the readonly review below.
