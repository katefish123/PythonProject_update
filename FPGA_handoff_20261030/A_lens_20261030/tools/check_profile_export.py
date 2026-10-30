"""Verify calibration -> all RTL constants/defaults binding without compilation."""
from pathlib import Path
import datetime,hashlib,json,re
from export_lens_profile import stage
from send_lens_angle import hardware_binding
ROOT=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()

def main():
    out=ROOT/'verification'/('profile_export_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
    profile=ROOT/'calibration/r50_18mm_hdmi_trial.json';source=ROOT/'candidate_host_angle_v2_product_stage'
    before={p.name:sha(p) for p in (source/'sources').iterdir() if p.is_file()}
    original=json.loads(profile.read_text());altered=json.loads(profile.read_text())
    altered['model']['fx']+=7;altered['model']['K'][0][0]=altered['model']['fx'];altered['model']['output_camera_matrix_for_preview'][0][0]=altered['model']['fx']
    synthetic=out/'synthetic_rebinding_fixture.json';synthetic.write_text(json.dumps(altered))
    cases=[]
    for label,p in [('actual_trial',profile),('synthetic_rebinding_fixture',synthetic)]:
        candidate=out/label;b=stage(p,candidate,source);q=b['default_affine_q24'];packed=sum((v&((1<<40)-1))<<(40*i) for i,v in enumerate(q))
        for name in ['lens_parameter_mailbox.v','frame_processor_stream.v']:
            text=(candidate/'sources'/name).read_text();m=re.search(r"localparam\[239:0\]DEFAULT_AFFINE=240'h([0-9a-f]{60});",text)
            assert m and int(m[1],16)==packed
        for key,v in b['hardware_params'].items():
            m=re.search(r"`define SAFE_"+key+r" 32'sh([0-9a-f]{8})",(candidate/'sources/lens_autocrop_instance.v').read_text());assert m and int(m[1],16)==(v&0xffffffff)
        assert hardware_binding(p,candidate,[1920,1080])['compatible']
        assert not b['software_qualified'] and not b['hardware_accepted'] and b['optical_acceptance_pending']
        try:stage(p,candidate,source)
        except ValueError:pass
        else:raise AssertionError('Existing candidate overwritten')
        cases.append({'label':label,'candidate':str(candidate),'binding_sha256':sha(candidate/'project/lens_binding.json'),'default_affine_q24':q})
    assert before=={p.name:sha(p) for p in (source/'sources').iterdir() if p.is_file()}
    assert hardware_binding(profile,out/'synthetic_rebinding_fixture',[1920,1080])['compatible'] is False
    result={'passed':True,'hardware_accessed':False,'compile_or_optical_acceptance':False,'scope':__doc__,'cases':cases,
            'template_source_sha256':before,'exporter_sha256':sha(ROOT/'tools/export_lens_profile.py'),'checker_sha256':sha(Path(__file__))}
    (out/'verification.json').write_text(json.dumps(result,indent=2));print(json.dumps({'directory':str(out),'passed':True,'cases':2,'template_unchanged':True,'hardware_accessed':False},indent=2))

if __name__=='__main__':main()
