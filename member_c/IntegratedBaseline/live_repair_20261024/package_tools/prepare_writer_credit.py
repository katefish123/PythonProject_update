"""Isolated timing hypothesis: register the writer's exclusive ACK-slot grant."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def transform(text):
    old = "assign cmd_valid=ui_live&&hold_valid&&!inflight&&!afull;"
    if text.count(old) != 1:
        raise RuntimeError("Unexpected writer version")
    text = text.replace(old, """// This FIFO has one ACK producer and one outstanding command. Only
 // ack_push can consume the reserved slot; revoke the next-cycle grant
 // on that edge, including an issue with an immediate response.
 reg ack_slot_available;
 always @(posedge ui_clk or negedge ui_live)
  if(!ui_live)ack_slot_available<=0;
  else ack_slot_available<=!afull&&!ack_push;
 assign cmd_valid=ui_live&&hold_valid&&!inflight&&ack_slot_available;""")
    return text


def bench(text):
    text = text.replace("dut(.*);", "dut(.rsp_valid(effective_rsp),.*);")
    text = text.replace("reg rsp_valid=0,rsp_write=1;", "reg immediate=0; reg rsp_valid=0,rsp_write=1; wire effective_rsp=immediate?(cmd_valid&&cmd_ready):rsp_valid;")
    text = text.replace("due[qt]=ticks+5+($random(seed)&31); qt=qt+1;", "if(!immediate)begin due[qt]=ticks+5+($random(seed)&31); qt=qt+1;end")
    text = text.replace("if(rsp_valid) begin qh=qh+1;ack_count=ack_count+1;end", "if(effective_rsp) begin if(!immediate)qh=qh+1;ack_count=ack_count+1;end")
    anchor = ' $display("PASS burst writer all tests commands=%0d acks=%0d",accept_count,ack_count);$finish;'
    if text.count(anchor) != 1:
        raise RuntimeError("Unexpected writer testbench")
    text = text.replace(anchor, ''' immediate=1;
 for(integer ib=0;ib<2;ib=ib+1)begin
  start(ib);for(n=0;n<1024;n=n+1)pixel(n);waitdrain();if(fault)fail("immediate response fault");
 end
 $display("PASS immediate responses both banks commands=%0d acks=%0d",accept_count,ack_count);
 $display("PASS burst writer credit pipeline stress");$finish;''')
    text = text.replace("initial begin #3000000;", '''reg was_stalled=0;reg[2075:0] stalled_payload;
always @(posedge ui_clk)begin
 if(!ui_rst_n)was_stalled<=0;
 else begin
  if(was_stalled&&(!cmd_valid||{cmd_addr,cmd_block_data}!==stalled_payload))fail("command unstable under backpressure");
  if(cmd_valid&&dut.afull)fail("command offered without ACK reservation");
  was_stalled<=cmd_valid&&!cmd_ready;stalled_payload<={cmd_addr,cmd_block_data};
 end
end
initial begin #3000000;''')
    return text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--candidate", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    source = args.candidate.resolve()/"sources/ddr_result_writer_burst64.v"
    original_bench = Path(__file__).resolve().parents[1]/"stream_video_20261015/result_burst/tb_writer_burst.sv"
    records = {}
    for mode in ("original", "registered"):
        out = root/mode
        out.mkdir()
        writer = out/source.name
        writer.write_text(source.read_text() if mode == "original" else transform(source.read_text()))
        tb = out/"tb_writer_burst.sv"
        tb.write_text(bench(original_bench.read_text()))
        commands = [
            ["vlib.exe", "work"],
            ["vlog.exe", "-sv", writer.name, tb.name],
            ["vsim.exe", "-c", "-voptargs=+acc", "tb_writer_burst", "-do", "run -all; quit -f"],
        ]
        for index, command in enumerate(commands):
            executable = Path("D:/softwares/modelsim/win64")/command[0]
            result = subprocess.run([str(executable), *command[1:]], cwd=out, capture_output=True, text=True)
            (out/f"step{index}.log").write_text(result.stdout+result.stderr)
            if result.returncode:
                raise RuntimeError(f"{mode} failed: {command[0]}")
        log = (out/"step2.log").read_text()
        if "PASS burst writer credit pipeline stress" not in log or "** Fatal:" in log or "** Error:" in log:
            raise RuntimeError(f"{mode} simulation failed")
        records[mode] = {"writer_sha256": sha(writer), "bench_sha256": sha(tb), "simulation_sha256": sha(out/"step2.log")}
    (root/"verification.json").write_text(json.dumps({"parent_writer_sha256": sha(source), "scope": "ACK safety/command stability regression; no physical timing qualification", "tests": records}, indent=2)+"\n")
    print(json.dumps(records, indent=2))


if __name__ == "__main__":
    main()
