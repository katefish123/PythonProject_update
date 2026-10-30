from pathlib import Path
import subprocess,json,datetime
R=Path(__file__).resolve().parents[1]
BIN=Path(r'C:\modeltech64_2020.4\win64')
OUT=R/'results/integration';OUT.mkdir(parents=True,exist_ok=True)
def run(exe,args,name):
 p=subprocess.run([str(BIN/exe),*map(str,args)],cwd=R,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
 (OUT/name).write_bytes(p.stdout)
 if p.returncode:raise RuntimeError(p.stdout.decode(errors='replace')[-6000:])
 return p.stdout.decode(errors='replace')
if not (OUT/'work').exists():run('vlib.exe',[OUT/'work'],'vlib.log')
run('vmap.exe',['integration_work',OUT/'work'],'vmap.log')
sources=sorted((R/'vendor/b/rtl').glob('*.v'))+sorted((R/'rtl/top').glob('*.v'))
run('vlog.exe',['-work',OUT/'work',*sources],'compile.log')
run('vlog.exe',['-sv','-work',OUT/'work',R/'sim/tb_frame_processor.sv'],'compile_test.log')
script=OUT/'check.do'
script.write_text('onerror {quit -code 2 -force}\nonbreak {resume}\nonfinish stop\nrun -all\nset b [examine -value -radix binary -noshowbase sim:/tb_frame_processor/test_passed]\nif {[llength $b]!=1 || [lindex $b 0] ne "1"} {quit -code 3 -force}\nquit -code 0 -force\n')
log=run('vsim.exe',['-c','-voptargs=+acc','integration_work.tb_frame_processor','-do',script],'simulation.log')
if 'FRAME_PROCESSOR_PASS' not in log:raise RuntimeError('No pass evidence')
print('\n'.join(line for line in log.splitlines() if 'PASS' in line))
(OUT/'verification.json').write_text(json.dumps({'status':'pass','utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'hardware_tested':False},indent=2))
