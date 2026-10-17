"""Source-bound single-sampling integration evidence, never board acceptance."""
from pathlib import Path
import hashlib,json,re,zipfile
R=Path(__file__).resolve().parent;B=R.parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
 b=p.read_bytes();return b.decode('utf-16' if b.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig')
def main():
 deps={p.name:p for p in [R/'region_sample.v',R/'source_marker_clean.v',R/'tb_region_sample.sv',
 B/'lens_throughput_20261017/q30_alu_fast.v',B/'lens_throughput_20261017/generated/lens_map_fast.v',
 B/'lens_throughput_20261017/generated/lens_composed_map_fast.v',B/'a_sync_20261013/hires_candidate/vendor/b/rtl/bilinear_interp.v']}
 expected_fixture=json.loads((B/'lens_model_next/verification.json').read_text())['vectors']
 cases={'release_final':'PASS REGION_SAMPLE','release_negative_ignore_response_bank':'OUTPUT_MISMATCH',
 'release_negative_skip_marker_cleanup':'OUTPUT_MISMATCH','release_negative_live_profile':'ADDRESS_ASSOCIATION'}
 archive=R/'evidence/synthetic_sampling.zip';records={}
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
  for suffix,message in cases.items():
   d=Path('D:/FPGA/output')/('region_sample_20261017_'+suffix);negative='negative' in suffix
   compile_log=read(d/'compile.log');log=read(d/'simulation.log')
   assert 'Errors: 0, Warnings: 0' in compile_log and not re.search(r'\*\* (Error|Fatal|Warning):',compile_log)
   if negative:assert '** Fatal: '+message in log
   else:assert message in log and 'Errors: 0, Warnings: 0' in log and not re.search(r'\*\* (Error|Fatal|Warning):',log)
   hashes=json.loads((d/'compiled_hashes.json').read_text(encoding='utf-8-sig'));assert set(hashes)==set(deps)
   for name,digest in hashes.items():
    p=d/'source_snapshot'/name;assert sha(p)==digest
    if not negative or name!='region_sample.v':assert sha(deps[name])==digest,(suffix,name)
    z.write(p,suffix+'/source_snapshot/'+name)
   m=json.loads((d/'manifest.json').read_text());assert m==expected_fixture
   for name,key in [('vectors.hex','vectors_sha256'),('composed_vectors.hex','composed_vectors_sha256'),('expected_pixels.hex','expected_pixels_sha256')]:
    assert sha(d/name)==m[key];z.write(d/name,suffix+'/fixtures/'+name)
   z.write(d/'manifest.json',suffix+'/fixtures/manifest.json')
   for name in ('compile.log','simulation.log','compiled_hashes.json'):z.write(d/name,suffix+'/'+name)
   records[suffix]={'expected_failure':negative,'expected_message':message,'compiled_source_sha256':hashes,
    'simulation_log_sha256':sha(d/'simulation.log'),'compile_log_sha256':sha(d/'compile.log')}
   if not negative:
    for item in ('sampled_pixels=972','requests=1000','interpolations=992'):assert item in log
    records[suffix]['statistics']={'composed_vectors':1024,'valid_vector_sampled_pixels':972,'accepted_memory_requests_total':1000,'B_interpolations_total':992}
  for name in ('region_sample.v','tb_region_sample.sv','run_sampling.ps1','mutate_sampling.py','collect_sampling_evidence.py','SAMPLING_DESIGN.md'):z.write(R/name,'integration/'+name)
 assert zipfile.ZipFile(archive).testzip() is None
 receipt={'status':'synthetic_single_sample_integration_pass','enterprise_acceptance':False,'hardware_acceptance':False,
 'board_integrated':False,'PDS_timing_qualified':False,'full_video_throughput_qualified':False,
 'real_calibration':'blocked_by_missing_calibration','scope':'Descriptor executor with actual exact fast H/Brown RTL,original B interpolation and a behavioral four-neighbor memory responder',
 'tests':records,'dependency_sha256':{p.relative_to(B).as_posix():sha(p) for p in deps.values()},
 'support_sha256':{n:sha(R/n) for n in ('run_sampling.ps1','mutate_sampling.py','collect_sampling_evidence.py')},
 'fixture_manifest_sha256':sha(Path('D:/FPGA/output/lens_vectors_20261017/manifest.json')),
 'evidence_zip_sha256':sha(archive),'reset_contract':'External producer cancels/drains accepted old memory work during reset; uncoordinated reset/late-response recovery not implemented',
 'remaining':['actual paper/pad and per-frame exact mask generation','region configuration/profile/mask atomic system ownership','physical DDR adapter and complete region stream connection','whole-frame error aggregation and corrected-result publication','pipelined throughput,final changed-board PDS timing','real calibration,held-out MTF/SFR and hardware acceptance']}
 (R/'sampling_verification.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
 print('PASS sampling archive:1024 vectors,972 vector pixels;1000 memory requests,992 single B interpolations;3 expected-red controls')
if __name__=='__main__':main()
