# RX free-tail storage timing candidate

The V4R failing path is capture/y_count[4] through sample bounds,data_due,push_count and a fanout1648 enable into queue[1][269]/CE. It has20 levels including15 cascaded CECO steps,slack-0.250ns,logic3.097ns/route3.411ns. Exact report and source SHA bindings are in summary.json.

No packet stage or queue item was added. The primary tail slot is stored whenever count<8 or a same-edge pop retires the old head. Its payload selection is unchanged. Only original push_count advances tail/count and exposes the stored record. Thus speculative writes to free tail remain invisible; full/stalled storage is untouched; full/pop reuses the retired slot after the consumer samples it. The second BEGIN write remains strictly push_count==2. Original data-space/control reserve,credits,bank/generation identity,packing and close logic are unchanged. There is no added packet latency or pending last-DATA stage.

TDD: old RX fails the new free-storage boundary check. New RX then matches a frozen old RX model cycle by cycle for3079 clocks,406 retirements,389 stalled cycles,41 full-hold cycles,one full pop,three END+BEGIN+pop tail-wrap events and41 DATA¡úEND events. Every valid/stalled output and all owned storage slots are compared. Full count8 and dual-control wrap use explicitly seeded boundary states; natural blocked frames independently exercise the count7 reserved-terminal condition. The original credit/VS boundary suite and reduced six-frame source integration also pass (576 commands/576 ACKs plus fault/backpressure/reset cases),all zero errors/warnings.

Ownership invariants preserve arbitrary backpressure: count/tail alone determine visibility; free-tail guesses never overwrite owned slots. Existing capacity invariant permits the second control write only when two slots are available or retired. At count0,invalid packet_data may change,as allowed by the valid-qualified interface. Shared reset clears visibility/ownership as before.

No full60,PDS or board run was started. These local results do not establish native complete-system throughput or routed timing closure. Root must validate the next snapshot bound to the frozen SHA.
