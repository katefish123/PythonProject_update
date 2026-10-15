"""Isolated protocol/cache regression, with a semantic pre-change RED mode."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path
from prepare_engine import transform

HERE = Path(__file__).resolve().parent
BASE = Path('D:/FPGA/output/c_inline_black_geometry_v5_20261015/diagnostics/ddr_camera_hires_prefetch_20261012/results/ddr_word_engine.v')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--red', action='store_true')
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    source = BASE.read_text()
    if args.red:
        # Port shim only, no write behavior changes: prove old single beat
        # engine fails the same data/command test, rather than elaboration.
        source = source.replace('parameter integer WATCHDOG_CYCLES = 1024,',
                                'parameter integer WATCHDOG_CYCLES = 1024, parameter CAPTURE_BURST_BEATS=1,')
        source = source.replace('input  wire [31:0]   cmd_wstrb,',
                                'input  wire [31:0]   cmd_wstrb,input wire [2047:0]capture_burst_data,')
        source = source.replace('output reg           fault,',
                                'output reg           fault,output wire [3:0]fault_reason,')
        source = source.replace('    localparam [2:0] ST_IDLE', '    assign fault_reason=0;\n    localparam [2:0] ST_IDLE', 1)
    else:
        source = transform(source)
    engine = out/'ddr_word_engine.v'
    engine.write_text(source)
    bench = HERE/'tb_burst_source_cache.sv'
    script = out/'run.do'
    script.write_text('onerror {quit -f -code 1}\nvlib work\nvmap work work\n'
                      f'vlog -sv {{{engine.as_posix()}}} {{{bench.as_posix()}}}\n'
                      'vsim -c -voptargs=+acc work.tb_burst_source_cache\nonfinish stop\nrun -all\n'
                      'set pass_bit [examine -value -radix binary -noshowbase sim:/tb_burst_source_cache/test_passed]\n'
                      'if {[lindex $pass_bit 0] ne "1"} {quit -f -code 1}\n'
                      'puts "VERIFIED_PASS_BIT=1"\nquit -f -code 0\n')
    log = out/'simulation.log'
    with log.open('w') as stream:
        proc = subprocess.run(['D:/softwares/modelsim/win64/vsim.exe', '-c', '-do', str(script)],
                              cwd=out, stdout=stream, stderr=subprocess.STDOUT)
    content = log.read_text()
    passed = (proc.returncode == 0 and 'VERIFIED_PASS_BIT=1' in content and
              'BURST_SOURCE_CACHE_PASS' in content and not re.search(r'\*\* (Error|Fatal|Warning)', content))
    inputs = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in [BASE, engine, bench, script]}
    (out/'evidence.json').write_text(json.dumps(dict(passed=passed, red=args.red,
        exit_code=proc.returncode, inputs=inputs, log_sha256=hashlib.sha256(log.read_bytes()).hexdigest(),
        hardware_accepted=False), indent=2)+'\n')
    print(content[-3500:])
    print('RED_EXPECTED_FAILURE' if args.red and not passed else 'PASS' if passed else 'FAIL')
    raise SystemExit(0 if args.red != passed else 1)


if __name__ == '__main__':
    main()
