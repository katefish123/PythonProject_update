"""Archive synthetic frame publication tests, not physical DDR acceptance."""
from pathlib import Path
import hashlib,json,re,zipfile
R=Path(__file__).resolve().parent;B=R.parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
 b=p.read_bytes();return b.decode('utf-16' if b.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig')
def main():
 paths=[R/'corrected_frame_guard.v',R/'tb_publish.sv',B/'stream_video_20261015/result_burst/ddr_result_writer_burst64.v',
 B/'frame_region_20261017/region_sample.v',B/'frame_region_20261017/source_marker_clean.v',
 B/'lens_throughput_20261017/q30_alu_fast.v',B/'lens_throughput_20261017/generated/lens_map_fast.v',
 B/'lens_throughput_20261017/generated/lens_composed_map_fast.v',B/'a_sync_20261013/hires_candidate/vendor/b/rtl/bilinear_interp.v']
 deps={p.name:p for p in paths}
 cases={'controls_final':'PASS FRAME_PUBLISH native=0 sampler=0','native_full':'PASS FRAME_PUBLISH native=1',
 'sampler1':'PASS FRAME_PUBLISH native=0 sampler=1',
 'release_negative_publish_early':'PUBLISHED_BEFORE_DDR_DRAIN',
 'release_negative_ignore_scene':'FAILURE_TIMEOUT','release_negative_ignore_source_bank':'FAILURE_TIMEOUT',
 'release_negative_ignore_upstream':'ABORT_LOST_UPSTREAM_OWNERSHIP'}
 evidence=R/'evidence';evidence.mkdir(exist_ok=True);archive=evidence/'synthetic_publication.zip';records={}
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
  for suffix,message in cases.items():
   d=Path('D:/FPGA/output')/('frame_publish_20261018_'+suffix);negative='negative' in suffix
   c=read(d/'compile.log');s=read(d/'simulation.log')
   assert 'Errors: 0, Warnings: 0' in c and not re.search(r'\*\* (Error|Warning|Fatal):',c)
   if negative:assert '** Fatal: '+message in s,(suffix,s[-1000:])
   else:assert message in s and 'Errors: 0, Warnings: 0' in s and not re.search(r'\*\* (Error|Warning|Fatal):',s)
   hashes=json.loads((d/'compiled_hashes.json').read_text(encoding='utf-8-sig'))
   assert len(hashes)==(9 if suffix=='sampler1' else 3)
   for name,digest in hashes.items():
    p=d/'source_snapshot'/name;assert sha(p)==digest
    if not negative or name!='corrected_frame_guard.v':assert sha(deps[name])==digest,(suffix,name,'source drift')
    z.write(p,suffix+'/source_snapshot/'+name)
   for name in ('compile.log','simulation.log','compiled_hashes.json'):z.write(d/name,suffix+'/'+name)
   record={'expected_failure':negative,'expected_message':message,'compiled_source_sha256':hashes,
    'compile_log_sha256':sha(d/'compile.log'),'simulation_log_sha256':sha(d/'simulation.log')}
   if not negative:
    stats={k:int(v) for k,v in re.findall(r'(pixels|blocks|acknowledged|publishes|failures|command_stalls)=(\d+)',s)}
    assert stats['publishes']==1 and stats['command_stalls']>0
    if suffix=='native_full':assert stats==dict(pixels=2073600,blocks=32400,acknowledged=32400,publishes=1,command_stalls=28589)
    else:assert stats['failures']==16
    record['statistics']=stats
   records[suffix]=record
  for name in ('DESIGN.md','corrected_frame_guard.v','tb_publish.sv','run_tests.ps1','mutate_for_test.py','collect_evidence.py'):z.write(R/name,'development/'+name)
 assert zipfile.ZipFile(archive).testzip() is None
 result={'status':'synthetic_frame_publication_guard_pass','scope':'Existing asynchronous burst writer plus behavioral native endpoint; reduced actual mapper/sampler-to-writer path; native full canvas writer/publication guard only',
 'enterprise_acceptance':False,'hardware_acceptance':False,'board_integrated':False,'PDS_timing_qualified':False,'full_composed_native_throughput_qualified':False,
 'real_calibration':'blocked_by_missing_calibration','tests':records,
 'source_sha256':{p.name:sha(p) for p in R.iterdir() if p.suffix in ('.v','.sv','.py','.ps1')},
 'dependency_sha256':{p.relative_to(B).as_posix():sha(p) for p in paths if p.parent!=R},'evidence_zip_sha256':sha(archive),
 'remaining':['actual paper/pad and exact marker mask generation','physical source-read DDR adapter and complete camera-to-result ownership integration','real cross-clock HDMI pending/front bank selector and reservation allocator','full native composed mapping throughput and final PDS timing','real calibration and held-out MTF/SFR/geometry/hardware acceptance'],
 'integration_contract':['upstream_idle covers physical source reads,mapper,sampler and held outputs','stop new upstream work during cancellation; late outputs are drained and discarded','hold source/result bank reservations across abort and display-descriptor ownership transfer','guard/writer/UI/native-engine resets must cancel/drain all old physical transactions together','truncated source requires explicit abort; no new timeout policy']}
 (R/'verification.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
 print('PASS archive:3 green suites;native2073600 pixels,32400 write ACKs;4 expected-red controls;source/ZIP bound')
if __name__=='__main__':main()
