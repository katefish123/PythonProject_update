"""Write a factual resume point; never converts an incomplete run to acceptance."""
from pathlib import Path
import argparse,datetime,hashlib,json
ROOT=Path(__file__).resolve().parents[1]
R=ROOT/'candidate_host_angle_v2_product_stage'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    global R
    ap=argparse.ArgumentParser();ap.add_argument('--candidate',type=Path,default=R);a=ap.parse_args();R=a.candidate.resolve()
    inputs={p.name:sha(p) for p in (R/'sources').iterdir() if p.is_file()}
    completed=[];pending=[]
    for p in sorted((ROOT/'verification').glob('*/verification.json')):
        obj=json.loads(p.read_text(encoding='utf-8'))
        if obj.get('source_sha256')==inputs and obj.get('passed'):
            completed.append({'path':str(p),'sha256':sha(p),'parameters':obj.get('parameters'),'simulated_30fps':obj.get('qualifies_simulated_30fps',False)})
    for folder in sorted((ROOT/'verification').glob('video_*')):
        if (folder/'simulation.log').exists() and not (folder/'verification.json').exists():pending.append(str(folder))
    builds=[]
    for p in sorted((R/'build').glob('pds_*/offline_build_inputs.json')):
        obj=json.loads(p.read_text())
        if obj['source_sha256']==inputs:builds.append({'path':str(p),'status':obj['status'],'qualified':False})
    record={'updated':datetime.datetime.now().astimezone().isoformat(),
            'scope':'1080p30 Brown k1/k2/p1/p2 lens correction plus PC-controlled 2D affine rotation/scale. Automatic tracking, IMU and optional four-point perspective are deferred.',
            'active_candidate':str(R),'baseline':'C:/D/FPGA/A_board_20261029/candidate_de_frame_guard_v2',
            'source_manifest_sha256':sha(R/'project/source_manifest.json'),
            'clock_mhz':{'processing':92.8125,'output':74.25,'input':148.5,'ddr_ui':125},
            'address_order':'Axis-aligned affine: raster. Rotated/sheared affine:128x128 tiles, last row band clipped; every DDR result burst remains64 contiguous pixels.',
            'current_source_full_video_passes':completed,'incomplete_video_runs':pending,'native_builds':builds,
            'hardware_accessed_this_scope':False,'camera_needed_now':False,'complete':False,
            'real_calibration_independently_validated':False,
            'remaining':['Finish all current-source functional modes if any verification runs remain incomplete.',
                         'Complete current native physical implementation and audit every timing summary/IO/resource constraint.',
                         'Package exact qualified source/bitstream/evidence only after those gates pass.',
                         'Later: fixed-focus independent camera calibration/optical measurements, actual board angle-update/30fps and physical end-to-end latency acceptance.']}
    record['previous_candidate']='C:/D/FPGA/A_lens_20261030/candidate_host_angle_v1'
    record['current_lens_pipeline_stages']=11 if 'v2_product' in R.name else 10
    record['scope_notes']='V1 passed11 full native-video regressions; first physical runs retained negative setup paths. V2 adds one exact radial-product pipeline boundary and has passed RTL/frozen-model equivalence and actual full-synthesis lens-cell integer comparisons. No hardware access.'
    (ROOT/'CURRENT_STATE.json').write_text(json.dumps(record,indent=2,ensure_ascii=False),encoding='utf-8')
    print(json.dumps({'current_source_video_passes':len(completed),'pending_video_runs':len(pending),'native_builds':builds},indent=2))

if __name__=='__main__':main()
