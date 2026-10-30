"""Record the user's explicit pause; performs no build or hardware action."""
from pathlib import Path
import datetime,hashlib,json
ROOT=Path(__file__).resolve().parents[1]

def main():
    now=datetime.datetime.now().astimezone().isoformat()
    build=ROOT/'candidate_host_angle_v2_product_stage/build/pds_20261030_135116_814250'
    note={'status':'stopped_by_user','at':now,'reason':'User requested pause and teammate handoff.',
          'driver_status_file':str(build/'offline_build_inputs.json'),
          'stop_is_not_a_tool_crash':True,'native_qualification_passed':False,
          'hardware_accessed_this_scope':False,'handoff':str(ROOT/'交接说明_20261030_暂停.md')}
    (build/'stopped_by_user.json').write_text(json.dumps(note,indent=2),encoding='utf-8')
    p=ROOT/'CURRENT_STATE.json';state=json.loads(p.read_text(encoding='utf-8'))
    candidate=ROOT/'candidate_host_angle_v2_product_stage'
    current={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in (candidate/'sources').iterdir() if f.is_file()}
    video=[]
    for f in sorted((ROOT/'verification').glob('video_*/verification.json')):
        v=json.loads(f.read_text(encoding='utf-8'))
        if v.get('passed') and v.get('source_sha256')==current:
            video.append({'path':str(f),'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'parameters':v['parameters'],'simulated_30fps':v.get('qualifies_simulated_30fps',False)})
    state['current_source_full_video_passes']=video
    state['incomplete_video_runs']=[]
    state['functional_ready']=json.loads((candidate/'candidate_review.json').read_text())['functional_ready']
    state.update(updated=now,status='paused_by_user',paused_by_user=True,paused_at=now,complete=False,
                 camera_needed_now=False,native_qualification_passed=False,hardware_accessed_this_scope=False,
                 handoff=str(ROOT/'交接说明_20261030_暂停.md'),
                 handoff_sha256=hashlib.sha256((ROOT/'交接说明_20261030_暂停.md').read_bytes()).hexdigest(),
                 functional_candidate=str(ROOT/'candidate_host_angle_v2_product_stage'),
                 experimental_candidate=str(ROOT/'candidate_host_angle_v3_cache64'),
                 experiment_status='V3 zero-degree full video30fps passed;90-degree steady34.895ms fails30fps. Bridge regression testbench has compile errors; no V3 physical build.')
    for entry in state.get('native_builds',[]):entry['status']='stopped_by_user';entry['qualified']=False
    p.write_text(json.dumps(state,indent=2,ensure_ascii=False),encoding='utf-8')
    print(json.dumps({'status':'paused_by_user','handoff':state['handoff'],'native_qualification_passed':False,'hardware_accessed':False},ensure_ascii=False))

if __name__=='__main__':main()
