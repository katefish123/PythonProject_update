from pathlib import Path
import json
D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/'results'
sources=json.loads((O/'source_hashes.json').read_text(encoding='utf-8-sig'))
rtl=[Path(p) for p in sources if p.endswith('.v') and '/ddr3_ip/' not in p.replace('\\','/') and '/ip/' not in p.replace('\\','/')]
name='tb_coord_queue_control'
(O/(name+'.sv')).write_bytes((D/(name+'.sv')).read_bytes())
lines=['onerror {quit -f -code 1}',f'transcript file {{{(O/(name+".transcript.log")).as_posix()}}}',
    f'if {{![file isdirectory work_{name}]}} {{vlib work_{name}}}',f'vmap work_{name} work_{name}',
    f'vlog -sv -work work_{name} '+' '.join('{'+p.as_posix()+'}' for p in rtl+[O/(name+'.sv')]),
    f'vsim -c -voptargs=+acc -wlf {{{(O/(name+".wlf")).as_posix()}}} work_{name}.{name}',
    'onfinish stop','run -all',f'set passed [examine -value -radix binary -noshowbase sim:/{name}/test_passed]',
    'if {[llength $passed]!=1 || [lindex $passed 0] ne "1"} {quit -f -code 1}',
    'puts "VERIFIED_PASS_BIT=1"','quit -f -code 0']
(O/(name+'.do')).write_text('\n'.join(lines)+'\n',encoding='utf-8')
cases=json.loads((O/'simulation_cases.json').read_text(encoding='utf-8-sig'))
cases[name]='CONTROL_PASS'
assert len(cases)==15
(O/'simulation_cases.json').write_text(json.dumps(cases,indent=2)+'\n',encoding='utf-8')
print('Fifteen required cases include directed reset/timeout/credit and stable stalled interfaces.')
