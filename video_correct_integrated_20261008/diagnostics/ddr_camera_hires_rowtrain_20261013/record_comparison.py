from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,re
D=Path(__file__).resolve().parent
O=D/'results'
def read(p):
    b=p.read_bytes()
    return b.decode('utf-16') if b.startswith((b'\xff\xfe',b'\xfe\xff')) else b.decode('utf-8-sig')
metrics={}
for variant,name in [('old','tb_old_contention_control'),('repaired','tb_rowtrain_contention')]:
    p=O/(name+'.run.log')
    s=read(p)
    assert 'VERIFIED_PASS_BIT=1' in s and not re.search(r'\*\* (Warning|Error|Fatal)',s)
    fields={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',s)}
    metrics[variant]={k:fields[k] for k in ['frames','correct_pixels','black_pixels','max_row_cycles','capture','source','max_capture_backlog']}
    metrics[variant].update(log=str(p),log_sha256=hashlib.sha256(p.read_bytes()).hexdigest())
assert metrics['repaired']['correct_pixels']==2*640*904 and metrics['repaired']['black_pixels']==0
assert metrics['repaired']['max_capture_backlog']<1024
assert metrics['old']['black_pixels']==640*903
record={'recorded_at_utc':datetime.now(timezone.utc).isoformat(),
    'same_memory_model':{'result_first_read_ui_clocks':40,'source_first_read_ui_clocks':80,'periodic_refresh_extra_ui_clocks':100,
        'physical_write_wait_ui_clocks':12,'capture_packet_period_ui_clocks':32,'processor_request_period_ui_clocks':97,
        'capture_and_processor_phases_separate':True,'phase_ui_clocks':2083340},
    'model_is_measured_board_latency':False,'hardware_accepted':False,
    'row_budget_approx_ui_clocks':1852,'variants':metrics,
    'rejected_overload_trial':'rejected_simultaneous_overload_new.log retains failed trial with continuous full capture AND processing and twelve-clock write drain. Real FrameSession freezes and drains capture before processor start, so qualification uses separate capture/processing phases. Legacy simultaneous traffic remains a separate test without additional write stall.',
    'qualification_scope':'Exact full output pixels of two banks, bounded capture backlog, both clients making progress, same hypothetical physical-memory delays. Does not prove physical latency, FPS, or long-term stability.'}
(O/'rowtrain_comparison.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
print(json.dumps(metrics,indent=2))
