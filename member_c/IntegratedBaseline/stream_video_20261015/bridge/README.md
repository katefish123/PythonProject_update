# Quad packet clock-domain bridge

Integrate `quad_packet_bridge.v` and `async_packet_stream.v`, together with the
unchanged baseline `rtl/memory/async_packet_fifo.v`. Default `FIFO_ADDR_BITS=9`
gives each direction a 512-entry CDC FIFO plus four read-side elastic slots.
Other parameters: SRC_W=1920, SRC_H=1080, OUT_W=768, OUT_H=1080.

Shared `rst_n` is hard reset only. No soft reset/abort enters this bridge;
queued packets survive processor abort and retain their original generations.
`proc_clk` owns q/r/fault; `ui_clk` owns req/rsp.

Processor request inputs: q_valid, q_inside, q_nearest,
q_addr00/q_addr10/q_addr01/q_addr11[23:0], q_tag[23:0], q_fx/q_fy[7:0],
q_generation[31:0], q_base[27:0]. Output q_ready. Pixel addresses exclude base.
All fields, including base/generation, are captured atomically on q_valid&&q_ready.

UI request outputs: req_valid, req_base[27:0], req_generation[31:0],
req_x/req_y[11:0], req_nearest, req_inside, req_tag[23:0], req_fx/req_fy[7:0].
Input req_ready. x/y decode q_addr00 using SRC_W. All other neighbor addresses
must match clipped bilinear or nearest geometry. Tags are {row[11:0],col[11:0]}
and must fit physical OUT_W/OUT_H. Address checks apply only when q_inside=1;
q_inside=0 permits arbitrary addresses and produces x=y=0. Invalid address or
tag packets set sticky proc-domain `fault` on acceptance and are forwarded
with req_inside=0,x=y=0. fault clears only on shared hard reset.

UI response inputs: rsp_valid, rsp_inside, rsp_p00/rsp_p10/rsp_p01/rsp_p11[23:0],
rsp_tag[23:0], rsp_fx/rsp_fy[7:0], rsp_generation[31:0]. Output rsp_ready.
Processor response outputs: corresponding r_valid,r_inside,r_p00/r_p10/r_p01/r_p11,
r_tag,r_fx/r_fy,r_generation. Input r_ready. Preserve ordered packet metadata
and return old generations unchanged; the processor decides which to drain.

Every interface uses standard ready/valid: hold valid and payload during stalls.
`async_packet_stream` reserves credit when initiating the registered FIFO read,
not when data reaches the skid. Counted pending reads plus stored packets never
exceed four. It initiates one read every rd_clk when data and credits allow.

Run `run_tests.ps1 -Suffix <unique>` for generic elastic FIFO tests;
add `-Top tb_quad_bridge` for full bidirectional bridge tests. Logs/hashes go to
D:/FPGA/output/c_quad_bridge_unit_20261015_<unique>.

Verified generic test: asynchronous 4ns/6ns clocks, full/stalls/stability/order,
reset with queued traffic, repeated full transfer, credit invariants, 796 packets
accepted on consecutive read clocks. Initial serial implementation failed this
same throughput assertion at max_run=1 before elastic implementation.
Verified bridge: asynchronous 10ns/6ns clocks, 1600 packets per round twice,
random stalls, FIFO full, base/generation/tag/fraction/RGB order, nearest/clipped
addresses, bypass address values, invalid address/tag fault, hard reset and
fault clearing. Last run observed 1334 consecutive processor response transfers.
This is unit CDC simulation, not board timing/DDR throughput validation.
