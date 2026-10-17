"""Fail-closed gap gate, v0: existing software may pass; lens hardware cannot.

This inventory gate is not a validator for future calibration/quality reports.
New reports remain UNVERIFIED until dedicated validators and review exist.
No number or synthetic test is silently promoted to enterprise acceptance.
"""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys
from datetime import datetime,timezone

sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def evaluate(root,model_receipt=None):
 root=Path(root);lens=root/'lens_model_20261015'
 checks={}
 try:
  m=model_receipt if model_receipt is not None else json.loads((lens/'verification.json').read_text())
  logs=(lens/'test_results.log').read_text()
  names={'lens_golden.py','lens_fixed.py','test_lens_golden.py','test_lens_fixed.py'}
  valid=(m['status']=='pass' and m['exit_code']==0 and m['tests']==17
   and m['scope']=='synthetic Python float64 and signed Q34.30 integer model only'
   and m['hardware_acceptance'] is False and m['rtl_lens']=='not_implemented'
   and m['real_camera_calibration']=='not_available'
   and set(m['source_sha256'])==names
   and all(sha(lens/n)==m['source_sha256'][n] for n in names)
   and 'Ran 17 tests' in logs and '\nOK\n' in logs)
  checks['SOFTWARE_REFERENCE']={'status':'PASS' if valid else 'FAIL',
   'scope':'synthetic_software_only','receipt_sha256':sha(lens/'verification.json'),
   'maximum_sample_error_source_px':m.get('fixed_maximum_source_pixel_error_on_declared_samples'),
   'note':'Sampled numerical model only; 0.125 source px is an engineering target, not an enterprise threshold.'}
 except (OSError,ValueError,KeyError,TypeError) as e:
  checks['SOFTWARE_REFERENCE']={'status':'FAIL','scope':'synthetic_software_only','error':str(e)}
 requirements={
  'LENS_RTL':('lens_model_next/rtl_qualification.json','Nonzero k1/k2/p1/p2 individually; independent float/fixed/RTL coordinates and sampled pixels; H-only negative controls.'),
  'PARAM_COMMIT':('lens_model_next/profile_commit_qualification.json','Complete K and lens bank validation; dimensions/mode/version/H association; atomic frame-boundary commit, reset/collision/in-flight ownership.'),
  'H_LENS_COMPOSITION':('lens_model_next/composition_qualification.json','Undistort raw corners before H fitting; target through ideal H then forward lens distortion; one final image sample.'),
  'REAL_CALIBRATION':('calibration_20261017/calibration_manifest.json','Traceable real raw images, camera/lens/mode/settings, K/k1/k2/p1/p2, target geometry, estimator/options, view hashes and errors; disjoint calibration/test captures.'),
  'HELD_OUT_QUALITY':('calibration_20261017/held_out_quality.json','Independent black/white target captures; MTF50 or SFR, straightness, edge stretch/breaks, physical aspect evidence, declared measurement methods and uncertainty.'),
  'LOCAL_FRAME_COMPOSITION':('lens_board_next/local_frame_qualification.json','Same input/output dimensions; actual paper/pad outer boundary; unchanged outside pixels except complete old-marker cleanup; justified target aspect,background fill,actual text-baseline checks and single final sampling with coherent source-frame metadata.'),
  'REALTIME_RESOURCES':('lens_board_next/video_qualification.json','Actual corrected new-image rate, end-to-end hardware latency, LUT/register/DSP use, native16:9 source, real movement/angle changes and persistent stability.'),
  'LENS_PDS':('lens_board_next/implementation.json','Final changed lens-inclusive RTL exact source SHA, all final timing constraints, bit/mask and actual hardware acceptance evidence.'),
 }
 for key,(relative,need) in requirements.items():
  p=root/relative
  status='UNVERIFIED' if p.exists() else ('MISSING_DATA' if key in ('REAL_CALIBRATION','HELD_OUT_QUALITY') else 'NOT_IMPLEMENTED_OR_NOT_EVIDENCED')
  if key=='LENS_PDS':status='UNVERIFIED'
  checks[key]={'status':status,'required_evidence':relative,'requirement':need,
   'external_data_required':key in ('REAL_CALIBRATION','HELD_OUT_QUALITY','REALTIME_RESOURCES')}
  if key=='REAL_CALIBRATION' and not p.exists():checks[key]['blocker']='blocked_by_missing_calibration'
  if p.is_file():checks[key]['unreviewed_file_sha256']=sha(p)
 # A source-bound development baseline documents progress, never release.
 baseline_path=root/'lens_model_next/verification.json'
 if baseline_path.exists():
  try:
   b=json.loads(baseline_path.read_text())
   bound=(b['status']=='synthetic_numeric_baseline_pass' and b['enterprise_acceptance'] is False
    and b['hardware_acceptance'] is False and b['PDS_timing_qualified'] is False
    and all(sha(root/'lens_model_next'/n)==d for n,d in b['source_sha256'].items()))
   for key in ('LENS_RTL','PARAM_COMMIT','H_LENS_COMPOSITION'):
    checks[key]['status']='PARTIAL_SYNTHETIC' if bound else 'DEVELOPMENT_EVIDENCE_FAILED'
    checks[key]['development_receipt_sha256']=sha(baseline_path)
    checks[key]['note']='Independent sequential numeric baseline; no real calibration,board integration,video throughput or changed PDS timing qualification.'
  except (OSError,ValueError,KeyError,TypeError):
   checks['LENS_RTL']['status']='DEVELOPMENT_EVIDENCE_FAILED'
 v5=root/'board_next_20261016/evidence/v5c/implementation.json'
 return {'gate_version':0,'decision':'NOT_READY','enterprise_acceptance':False,
  'checks':checks,'unmet':[k for k,c in checks.items() if c['status']!='PASS'],
  'V5C_preserved_timing_receipt_sha256':sha(v5) if v5.exists() else None,
  'V5C_scope':'H-only/RAW board candidate; cannot qualify lens-inclusive RTL or real lens quality',
  'policy':'Missing or unreviewed evidence blocks acceptance; arbitrary JSON pass flags do not grant release. No enterprise numeric thresholds invented.'}

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--output',type=Path,required=True)
 args=parser.parse_args()
 root=Path(__file__).resolve().parent.parent
 # Refresh the existing model tests; do not replace the independent models.
 p=subprocess.run([sys.executable,'-B',str(root/'lens_model_20261015/verify_models.py')],check=False)
 result=evaluate(root);result['generated_utc']=datetime.now(timezone.utc).isoformat()
 result['fresh_model_process_exit_code']=p.returncode
 if p.returncode:result['checks']['SOFTWARE_REFERENCE']['status']='FAIL'
 result['unmet']=[k for k,c in result['checks'].items() if c['status']!='PASS']
 args.output.parent.mkdir(parents=True,exist_ok=True)
 args.output.write_text(json.dumps(result,indent=2)+'\n')
 print('ENTERPRISE_GATE=NOT_READY unmet='+','.join(result['unmet']))
 return 2

if __name__=='__main__':sys.exit(main())
