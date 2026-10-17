"""Archive source-bound synthetic routing evidence; never board qualification."""
from pathlib import Path
import hashlib,json,re,zipfile

ROOT=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read_log(p):
 data=p.read_bytes()
 return data.decode('utf-16') if data.startswith((b'\xff\xfe',b'\xfe\xff')) else data.decode('utf-8-sig')

def main():
 cases={
  'cleanup_final':'PASS SOURCE_MARKER_CLEAN',
  'region_controls_final':'PASS FRAME_REGION native=0',
  'region_native_final':'PASS FRAME_REGION native=1',
  'geometry_final':'PASS REGION_GEOMETRY cases=10',
  'negative_erase_all_neighbors':'mask cleaner mismatch',
  'negative_outside_fill':'region pixel',
  'negative_commit_busy':'STALLED_PACKET_CHANGED_ON_FRAME_COMMIT',
 }
 records={};archive=ROOT/'evidence'/'synthetic_routing.zip'
 archive.parent.mkdir(exist_ok=True)
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
  for name,expected in cases.items():
   out=Path('D:/FPGA/output')/('frame_region_20261017_'+name)
   compile_log=read_log(out/'compile.log');sim=read_log(out/'simulation.log')
   negative=name.startswith('negative_')
   assert not re.search(r'\*\* (Fatal|Error|Warning):',compile_log),name
   assert expected in sim,name
   assert ('** Fatal:' in sim) if negative else (not re.search(r'\*\* (Fatal|Error|Warning):',sim) and 'Errors: 0, Warnings: 0' in sim),name
   hashes=json.loads((out/'compiled_hashes.json').read_text(encoding='utf-8-sig'))
   for filename,digest in hashes.items():
    p=out/'source_snapshot'/filename
    assert sha(p)==digest,(name,filename)
    if not negative:assert sha(ROOT/filename)==digest,(name,filename,'source drift')
    z.write(p,name+'/source_snapshot/'+filename)
   for filename in ('compile.log','simulation.log','compiled_hashes.json'):
    z.write(out/filename,name+'/'+filename)
   records[name]={'expected_failure':negative,'expected_message':expected,'compiled_source_sha256':hashes,
    'compile_log_sha256':sha(out/'compile.log'),'simulation_log_sha256':sha(out/'simulation.log')}
   if name=='region_native_final':
    stats=dict((k,int(v)) for k,v in re.findall(r'(pixels|outside_identity|raw|fill|warp|accepted_cycles|admission_span_cycles)=(\d+)',sim))
    assert stats==dict(pixels=2073600,outside_identity=725208,raw=725208,fill=829992,warp=518400,accepted_cycles=2073600,admission_span_cycles=2073600),stats
    records[name]['statistics']=stats
 assert zipfile.ZipFile(archive).testzip() is None
 sources={p.name:sha(p) for p in ROOT.iterdir() if p.suffix in ('.v','.sv','.py','.ps1')}
 receipt={'status':'synthetic_supplied_geometry_routing_pass','scope':'supplied convex boundary and exact marker masks; routing and pre-interpolation neighbor cleanup only',
  'enterprise_acceptance':False,'hardware_acceptance':False,'board_integrated':False,'PDS_timing_qualified':False,
  'real_calibration':'blocked_by_missing_calibration','corrected_RGB_implemented':False,
  'tests':records,'source_sha256':sources,'evidence_zip_sha256':sha(archive),
  'remaining':['real paper/pad boundary detection','exact per-frame marker-mask generation','mapping and original-B single sampling with DDR integration','whole-frame corrected publication protection','physical aspect and real calibration provenance','full mapping throughput and final PDS timing','held-out MTF/SFR and hardware acceptance']}
 (ROOT/'verification.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
 print('PASS source-bound archive: 4 green suites,3 expected-red controls; native 2073600 consecutive admissions')

if __name__=='__main__':main()
