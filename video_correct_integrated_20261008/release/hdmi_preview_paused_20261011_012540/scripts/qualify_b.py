"""Run all eight supplied B benches in native ModelSim without touching originals."""
from pathlib import Path
import subprocess, json, datetime

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'vendor/b'
BIN = Path(r'C:\modeltech64_2020.4\win64')
OUT = ROOT / 'results/b_native'
OUT.mkdir(parents=True, exist_ok=True)

def run(exe, args, name, timeout=180):
    p = subprocess.run([str(BIN / exe), *map(str, args)], cwd=BASE,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    (OUT / name).write_bytes(p.stdout)
    if p.returncode:
        raise RuntimeError(f'{name}: exit {p.returncode}\n{p.stdout.decode(errors="replace")[-4000:]}')
    return p.stdout.decode(errors='replace')

if not (BASE/'work').exists(): run('vlib.exe', ['work'], 'vlib.log')
run('vlog.exe', ['-work','work', *sorted((BASE/'rtl').glob('*.v')),
                 BASE/'examples/b_rectifier_instance.v'], 'compile_rtl.log')
run('vlog.exe', ['-sv','-work','work', *sorted((BASE/'sim').glob('*.sv'))], 'compile_tb.log')
results=[]
for line in (BASE/'sim/tests.list').read_text().splitlines():
    if not line.strip() or line.lstrip().startswith('#'): continue
    top, marker = line.split()
    script = OUT / f'{top}.do'
    script.write_text('onerror {quit -code 2 -force}\nonbreak {resume}\nonfinish stop\nrun -all\n'
        f'set bit [examine -value -radix binary -noshowbase sim:/{top}/test_passed]\n'
        'if {[llength $bit] != 1 || [lindex $bit 0] ne "1"} {quit -code 3 -force}\n'
        'echo "NATIVE_PASS_BIT=1"\nquit -code 0 -force\n')
    log=run('vsim.exe',['-c','-voptargs=+acc',f'work.{top}','-do',str(script)],f'{top}.log')
    if marker not in log or 'NATIVE_PASS_BIT=1' not in log: raise RuntimeError(f'Missing pass evidence: {top}')
    results.append({'test':top,'status':'pass','log':str((OUT/f'{top}.log').relative_to(ROOT))})
    print(top,'PASS',flush=True)
report={'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'simulator':'ModelSim SE-64 2020.4',
        'tests':results,'status':'pass','hardware_tested':False}
(OUT/'verification.json').write_text(json.dumps(report,indent=2))
print('ALL_8_NATIVE_MODELSIM_PASS',flush=True)
