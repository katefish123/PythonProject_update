# Native retirement and next-command acceptance

The engine can accept a new command on the clock edge retiring the previous public response. The old response data/type remain associated with the old owner through that edge. New command fields are latched for the next transaction. Sticky faults still stop admission. The matching arbiter preserves active ownership if a response and new acceptance coincide; it routes the old response before updating the owner.

Inner arbitration retains result-write priority; outer arbitration balances capture/correction while keeping display priority. The two arbiters and engine are changed together in a fresh generated snapshot. Changing only one side does not eliminate the bubble.

`run_tests.ps1` checks seven independent cases, including simultaneous retirement/acceptance, old/new read association, balanced grants, native ID/LAST/errors/timeouts, cache invalidation, source bursts and shared reset. Original engine fails TURNAROUND_REQUIRED. Generated reduced6 pressure test passes with no underrun, source corruption, early publication or bad-marker publication. Native full-resolution measurements are recorded separately in continuous_system_test evidence.

No changes to B arithmetic, source sampling or output dimensions. No hardware qualification implied.
