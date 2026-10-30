"""Collect exact-source evidence; release requires successful native timing/IO too."""
from pathlib import Path
import argparse,datetime,hashlib,json
ROOT=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()

def inputs_for(p,v):
    f=p.parent/'inputs.json'
    if not f.exists():return {}
    h=v.get('input_manifest_sha256',v.get('inputs_sha256'))
    if h and sha(f)!=h:raise ValueError('Input manifest changed '+str(f))
    return json.loads(f.read_text(encoding='utf-8'))

def source_subset(i,current,names):
    mapping=i.get('source_sha256',i.get('input_sha256',{}))
    return all(any(Path(p).name==n and h==current[n] for p,h in mapping.items()) for n in names)

def assess(candidate):
    candidate=candidate.resolve();manifest=candidate/'project/source_manifest.json'
    m=json.loads(manifest.read_text());current={p.name:sha(p) for p in (candidate/'sources').iterdir() if p.is_file()}
    if current!=m['source_sha256']:raise ValueError('Candidate differs from its source manifest')
    if sha(candidate/'project/build_full.tcl')!=m['build_tcl_sha256']:raise ValueError('Build script differs from source manifest')
    files=sorted((ROOT/'verification').glob('*/verification.json'),reverse=True)
    proofs={};missing=[]
    def pick(label,prefix,predicate):
        for p in files:
            if not p.parent.name.startswith(prefix+'_'):continue
            v=json.loads(p.read_text(encoding='utf-8'))
            if not v.get('passed'):continue
            i=inputs_for(p,v)
            if predicate(v,i):
                proofs[label]={'verification':str(p),'sha256':sha(p),'inputs':str(p.parent/'inputs.json') if i else None};return
        missing.append(label)
    common=lambda v:v.get('source_sha256')==current and v.get('qualifies_simulated_30fps') is True
    mode=lambda v:v['parameters']
    pick('video_bilinear0','video',lambda v,i:common(v) and not mode(v)['raw'] and not mode(v)['nearest'] and mode(v)['angle_deg']==0 and mode(v).get('alternating_angle_deg') is None)
    pick('video_bilinear90','video',lambda v,i:common(v) and not mode(v)['raw'] and not mode(v)['nearest'] and mode(v)['angle_deg']==90 and mode(v).get('alternating_angle_deg') is None)
    pick('video_dynamic0_90','video',lambda v,i:common(v) and mode(v)['angle_deg']==0 and mode(v).get('alternating_angle_deg')==90)
    pick('video_raw','video',lambda v,i:common(v) and mode(v)['raw'])
    pick('video_nearest','video',lambda v,i:common(v) and not mode(v)['raw'] and mode(v)['nearest'])
    pick('affine_lens_exact','affine_lens',lambda v,i:source_subset(i,current,['lens_affine_instance.v','lens_distort_coord.v','bilinear_interp.v']))
    pick('wire_control_pipeline','control_pipeline',lambda v,i:source_subset(i,current,['lens_uart_control.v','lens_parameter_mailbox.v','frame_processor_stream.v','lens_affine_instance.v','lens_distort_coord.v','bilinear_interp.v']))
    pick('tile_traversal_abort','tile_order',lambda v,i:source_subset(i,current,['frame_processor_stream.v','ddr_result_writer_burst64.v']))
    pick('mailbox_atomic','parameter_mailbox',lambda v,i:i.get('rtl_sha256')==current['lens_parameter_mailbox.v'])
    pick('uart_wire_crc_commit','uart',lambda v,i:i.get('rtl_sha256')==current['lens_uart_control.v'] and i.get('host_tool_sha256')==sha(ROOT/'tools/send_lens_angle.py'))
    pick('pll_and_constraints','video_clocks',lambda v,i:source_subset(i,current,['video_pll_27m_148m5.v','board_ddr.fdc','video_correct_ddr_top.v']))
    pick('actual_synthesized_lens_cells','native_lens',lambda v,i:i.get('source_sha256')==current and Path(i['full_netlist']).exists() and sha(i['full_netlist'])==i['full_netlist_sha256'])
    pick('host_angle_binding','host_angle',lambda v,i:i.get('host_sha256')==sha(ROOT/'tools/send_lens_angle.py') and i.get('rtl_sha256')==current['lens_affine_instance.v'])
    def tool_set(i,names):
        mapping=i.get('source_sha256',i.get('input_sha256',{}))
        return all(any(Path(p).name==n and h==sha(ROOT/'tools'/n) for p,h in mapping.items()) for n in names)
    pick('synthetic_calibration_points','calibration_check',lambda v,i:tool_set(i,['camera_calibration.py','board_geometry.py','check_calibration.py']))
    pick('synthetic_calibration_image_cli','calibration_cli',lambda v,i:tool_set(i,['camera_calibration.py','board_geometry.py','check_calibration_cli.py']))
    pick('slanted_edge_sfr','sfr_check',lambda v,i:tool_set(i,['slanted_edge_sfr.py','check_sfr.py']))
    pick('new_profile_export','profile_export',lambda v,i:v.get('template_source_sha256')==current and v.get('exporter_sha256')==sha(ROOT/'tools/export_lens_profile.py'))
    functional_ready=not missing
    native=None
    for p in sorted((candidate/'build').glob('pds_*/native_audit.json'),reverse=True):
        v=json.loads(p.read_text())
        if v.get('passed') and v.get('source_sha256')==current and sha(p.parent/'offline_build_inputs.json')==v['native_inputs_sha256']:
            native={'audit':str(p),'audit_sha256':sha(p),'build':str(p.parent),'timing':v['timing'],'io_pad_count':v['io']['pad_count']};break
    if native is None:missing.append('native_physical_timing_and_io')
    artifacts={}
    if native:
        b=Path(native['build']);bit=list((b/'generate_bitstream').glob('*.sbit'));mask=list((b/'generate_bitstream').glob('*.smsk'))
        db=b/'place_route/video_correct_ddr_top_prr.adf'
        if len(bit)!=1 or len(mask)!=1 or not db.exists():missing.append('selected_physical_database_and_paired_cram_files')
        else:
            for name,p in [('sbit',bit[0]),('smsk',mask[0]),('physical_database',db)]:artifacts[name]={'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size}
    parent=Path('C:/D/FPGA/A_board_20261029/candidate_de_frame_guard_v2')
    baseline=json.loads((parent/'project/source_manifest.json').read_text())['source_sha256']
    immutable=all(sha(parent/'sources'/name)==digest for name,digest in baseline.items())
    if not immutable:missing.append('immutable_baseline_integrity')
    review={'software_candidate_ready':not missing,'functional_ready':functional_ready,'hardware_accepted':False,'hardware_accessed_this_scope':False,
            'hardware_fps_unverified':True,'real_calibration_independently_validated':False,'target_fps':30,'resolution':[1920,1080],
            'scope':'Brown lens correction plus PC-controlled2D affine angle. Automatic tracking, IMU and optional perspective deferred.',
            'updated':datetime.datetime.now().astimezone().isoformat(),'candidate':str(candidate),'source_manifest_sha256':sha(manifest),
            'source_sha256':current,'proofs':proofs,'missing':missing,'native':native,'artifacts':artifacts,
            'immutable_baseline_passed':immutable,'assessor_sha256':sha(Path(__file__)),
            'remaining_hardware':'Independent fixed-focus calibration/optical tests, actual board30fps and physical end-to-end latency remain pending.'}
    (candidate/'candidate_review.json').write_text(json.dumps(review,indent=2))
    return review

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--candidate',type=Path,default=ROOT/'candidate_host_angle_v2_product_stage');ap.add_argument('--write-qualification',action='store_true');a=ap.parse_args()
    r=assess(a.candidate)
    if a.write_qualification:
        if not r['software_candidate_ready']:raise SystemExit('Qualification refused: '+', '.join(r['missing']))
        (a.candidate/'candidate_qualification.json').write_text(json.dumps(r,indent=2))
    print(json.dumps({k:r[k] for k in ['software_candidate_ready','functional_ready','missing','immutable_baseline_passed']},indent=2))

if __name__=='__main__':main()
