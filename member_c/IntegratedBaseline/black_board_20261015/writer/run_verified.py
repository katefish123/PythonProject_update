"""Verify the preserved writer and bank adapter independently of the core."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True)
OUT=parser.parse_args().output.resolve()
OUT.mkdir(parents=True,exist_ok=False)
files=[HERE/name for name in ['ddr_capture_writer.v','ddr_capture_writer_banked.v','tb_banked_burst_writer.sv']]
assert files[0].read_bytes()==Path('D:/FPGA/output/c_capture_burst_20261014/rtl/memory/ddr_capture_writer.v').read_bytes()
script=OUT/'run.do'
script.write_text('onerror {quit -f -code 1}\nvlib work\nvmap work work\n'
                  +'vlog -sv '+' '.join('{'+p.as_posix()+'}' for p in files)+'\n'
                  +'vsim -c -voptargs=+acc work.tb_banked_burst_writer\nonfinish stop\nrun -all\n'
                  +'set bit [examine -value -radix binary -noshowbase sim:/tb_banked_burst_writer/test_passed]\n'
                  +'if {[lindex $bit 0] ne "1"} {quit -f -code 1}\nputs "VERIFIED_PASS_BIT=1"\nquit -f -code 0\n')
log=OUT/'simulation.log'
with log.open('w') as stream:
    proc=subprocess.run(['D:/softwares/modelsim/win64/vsim.exe','-c','-do',str(script)],cwd=OUT,stdout=stream,stderr=subprocess.STDOUT)
content=log.read_text()
passed=proc.returncode==0 and 'VERIFIED_PASS_BIT=1' in content and 'BANKED_BURST_WRITER_PASS' in content and not re.search(r'\*\* (Error|Warning|Fatal)',content)
(OUT/'evidence.json').write_text(json.dumps(dict(passed=passed,exit_code=proc.returncode,hardware_accepted=False,
    files={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files+[script,log]}),indent=2)+'\n')
print(content[-2800:])
raise SystemExit(0 if passed else 1)
