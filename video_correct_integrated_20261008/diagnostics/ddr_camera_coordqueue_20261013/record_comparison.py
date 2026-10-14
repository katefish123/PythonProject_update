from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,re
D=Path(__file__).resolve().parent
O=D/'results'
def read(p):
    b=p.read_bytes()
    return b.decode('utf-16') if b.startswith((b'\xff\xfe',b'\xfe\xff')) else b.decode('utf-8-sig')
metrics={}
for version,name in [('baseline','tb_frame_profile'),('coordinate_lookahead','tb_ddr_full_frame')]:
    p=O/(name+'.run.log')
    s=read(p)
    assert 'DDR_FULL_FRAME_PASS' in s and 'VERIFIED_PASS_BIT=1' in s and not re.search(r'\*\* (Warning|Error|Fatal)',s)
    cycles=int(re.search(r'DDR_FULL_FRAME_CYCLES=(\d+)',s)[1])
    stage={int(k):int(v) for k,v in re.findall(r'PROFILE_STAGE state=(\d+) cycles=(\d+)',s)}
    assert sum(stage.values())==cycles
    metrics[version]={'total_cycles':cycles,'stages':stage,'modeled_27mhz_seconds':cycles/27000000,
        'source_reads':int(re.search(r'source_reads=(\d+)',s)[1]),'log':str(p),'log_sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
assert metrics['baseline']['total_cycles']==25094025
assert metrics['coordinate_lookahead']['total_cycles']==12365414
assert metrics['baseline']['source_reads']==metrics['coordinate_lookahead']['source_reads']==385848
record={'recorded_at_utc':datetime.now(timezone.utc).isoformat(),'same_native_golden_pixels':578560,'same_full_native_rgb':True,
    'geometry_and_pixel_math_unchanged':True,'host_memory_model_only':True,'hardware_programmed':False,'hardware_speedup_accepted':False,
    'variants':metrics,'modeled_cycle_speed_ratio':metrics['baseline']['total_cycles']/metrics['coordinate_lookahead']['total_cycles'],
    'actual_working_baseline_observed_hz':0.85,'baseline_hardware_receipt':'results/hardware_20261009/rowtrain_actual_update_rate_verified_20261013.json',
    'note':'Old WAIT_REQ stage waits23 clocks per pixel; lookahead reserves16 credits and overlaps coordinate work while one pixel samples/interpolates. Full native golden unchanged, max16reserved/15queued. Clock and DDR interface unchanged. Synthetic memory model gains are not a measured new board FPS.'}
(O/'coordinate_comparison.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'speed_ratio':record['modeled_cycle_speed_ratio'],'baseline_cycles':25094025,'lookahead_cycles':12365414,'actual_hardware_unverified':True},indent=2))
