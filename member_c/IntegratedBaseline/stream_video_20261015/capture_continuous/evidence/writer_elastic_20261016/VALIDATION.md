# Capture writer elastic timing candidate

See summary.json for source SHA bindings, exact old paths, test results and remaining limits. Old V4N worst UI path: data_crossing/head[1] through FIFO selection, header/address validation and fanout1705 enable to writer/assembly[601]/CE, -1.120ns, six levels, logic1.256ns/route7.314ns.

The writer buffers one input record with simultaneous consume/refill. Assembly is stored under only registered packet kind/valid and local state/fill. Invalid packets can overwrite an unowned partial lane, but original header checks still gate fill/SEND and prevent rejected data from becoming an owned command. All eight lanes are overwritten before SEND, so BEGIN/END/ACK clearing is unnecessary. Assembly/address stay immutable during SEND/WAIT_ACK. END cannot report until the owned burst ACK retires. Same-cycle command/ACK remains supported. Shared hard reset flushes the stage and cancels native ownership together with the engine.

Old writer explicitly fails the new elastic-capacity check. Frozen writer passes queue-full/backpressure, stable command/terminal payload, delayed and same-cycle ACK, consecutive accepted last-DATA/END cycles, partial rejection, generation mismatch and SEND/WAIT_ACK reset recovery. The existing reduced six-frame source-path suite passes576 commands/576 ACKs, real async FIFO full, malformed dimensions, geometry FIFO overflow, stopped RX clock recovery, stale release and shared reset. Both pass with zero errors/warnings.

Only writer RTL and dedicated tests/evidence changed. No sourcepath/RX/geometry/engine/clocks/constraints changed. No full60/PDS/board run was started. Root must test the newly bound full-system snapshot and routed timing before claiming physical closure or native throughput.
