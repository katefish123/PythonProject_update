"""Profile the sealed baseline with its unchanged full-resolution RGB golden."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json
D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/'results'
O.mkdir(exist_ok=True)
base=R/'diagnostics/ddr_camera_hires_rowtrain_20261013/results'
sealed=R/'release/ddr_camera_hires_rowtrain_20261013'
manifest=json.loads((sealed/'source_hashes.json').read_text(encoding='utf-8-sig'))
for p,h in manifest.items():assert hashlib.sha256(Path(p).read_bytes()).hexdigest()==h,p
source=(base/'tb_ddr_full_frame.sv').read_text(encoding='utf-8-sig')
source=source.replace('module tb_ddr_full_frame;','module tb_frame_profile;')
anchor=' reg test_passed=0;'
assert source.count(anchor)==1
source=source.replace(anchor,anchor+'''
 integer stage_cycles[0:11];integer profile_total=0;
 initial begin for(integer s=0;s<12;s=s+1)stage_cycles[s]=0;end
 always @(posedge clk)if(rst_n&&busy)begin
  profile_total=profile_total+1;
  if(dut.state<=11)stage_cycles[dut.state]=stage_cycles[dut.state]+1;
 end
''')
anchor='  $display("DDR_FULL_FRAME_CYCLES=%0d GEOMETRY_VALID=%b",cycles,geometry_valid);'
assert source.count(anchor)==1
source=source.replace(anchor,anchor+'''
  for(integer s=0;s<12;s=s+1)$display("PROFILE_STAGE state=%0d cycles=%0d",s,stage_cycles[s]);
  $display("PROFILE_TOTAL=%0d",profile_total);
''')
(O/'tb_frame_profile.sv').write_text(source,encoding='utf-8')
rtl=[Path(p) for p in manifest if p.endswith('.v') and '/ddr3_ip/' not in p.replace('\\','/') and '/ip/' not in p.replace('\\','/')]
top='tb_frame_profile'
lines=['onerror {quit -f -code 1}',f'transcript file {{{(O/(top+".transcript.log")).as_posix()}}}',
    'if {![file isdirectory work_profile]} {vlib work_profile}','vmap work_profile work_profile',
    'vlog -sv -work work_profile '+' '.join('{'+p.as_posix()+'}' for p in rtl+[O/(top+'.sv')]),
    f'vsim -c -voptargs=+acc -wlf {{{(O/(top+".wlf")).as_posix()}}} work_profile.{top}',
    'onfinish stop','run -all',f'set passed [examine -value -radix binary -noshowbase sim:/{top}/test_passed]',
    'if {[llength $passed]!=1 || [lindex $passed 0] ne "1"} {quit -f -code 1}',
    'puts "VERIFIED_PASS_BIT=1"','quit -f -code 0']
(O/(top+'.do')).write_text('\n'.join(lines)+'\n',encoding='utf-8')
(O/'baseline_sources.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
now=datetime.now(timezone.utc).isoformat()
for path in [R/'docs/hardware_20261009.json',R/'results/hardware_20261009/rowtrain_camera_state_20261013.json']:
    state=json.loads(path.read_text(encoding='utf-8-sig'))
    state.update(paused_by_user=False,resumed_at_utc=now,
        phase='Resumed: profile processing stages and validate coordinate lookahead in an independent clone; working hardware unchanged',
        pending='Profile baseline native RGB golden, overlap coordinate calculation with current sampling, validate output/credits/reset and complete final timing before any new programming.')
    path.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(O/'resumed_work.json').write_text(json.dumps({'resumed_at_utc':now,'working_image_unchanged':'eb06c8f9645665111b339e2ea305549a107830275d50f7625245b163b371d987','paused_by_user':False,'hardware_reprogrammed':False,'baseline_sources_verified':True},indent=2)+'\n',encoding='utf-8')
print('Baseline profiler prepared. Stable source closure verified; user resume recorded.')
