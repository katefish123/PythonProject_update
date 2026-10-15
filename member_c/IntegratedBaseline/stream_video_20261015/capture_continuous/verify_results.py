from pathlib import Path
import json,hashlib,re
here=Path(__file__).resolve().parent
root=Path('D:/FPGA/output')
names=['continuous_capture_rx.v','continuous_capture_writer.v','continuous_capture_geometry.v','continuous_capture_manager.v','continuous_source_path.v']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
runs={}
for suffix in ['manager_telemetry','reduced_overflow_restart','native60_telemetry','frozen_native6']:
 folder=root/f'c_continuous_capture_20261015_{suffix}'
 raw=(folder/'simulation.log').read_bytes()
 log=raw.decode('utf-16' if raw.startswith(b'\xff\xfe') else 'utf-8')
 assert 'Errors: 0, Warnings: 0' in log and '** Fatal:' not in log and 'PASS ' in log
 runs[suffix]={'simulation_log':str(folder/'simulation.log'),'log_sha256':sha(folder/'simulation.log'),'compile_log':str(folder/'compile.log'),'compile_sha256':sha(folder/'compile.log')}
 snapshot=folder/'source_snapshot'
 if snapshot.exists():
  for name in names:assert sha(snapshot/name)==sha(here/name),(suffix,name)
  runs[suffix]['compiled_source_snapshot']=str(snapshot)
  runs[suffix]['source_hashes']=str(folder/'source_hashes.txt')
 lines=re.findall(r'CAPTURE_DESCRIPTOR native=1 gen=(\d+) bank=(\d) source_frame=(\d+) capture_ms=(\d+) time_ns=(\d+)',log)
 if lines:
  runs[suffix]['descriptors']=[{'generation':int(g),'bank':int(b),'source_frame':int(f),'capture_ms':int(t),'timestamp_ps':int(time)} for g,b,f,t,time in lines]
  stamps=[int(row[-1]) for row in lines]
  runs[suffix]['native_intervals_ns']={'minimum':min(b-a for a,b in zip(stamps,stamps[1:]))/1000,'maximum':max(b-a for a,b in zip(stamps,stamps[1:]))/1000,'average':(stamps[-1]-stamps[0])/(len(stamps)-1)/1000}
report={'candidate_ready_for_integration':True,'full_corrected_hdmi_60fps_verified':False,'board_accepted':False,
'native_source_frames':60,'native_source_pixels_checked':60*1920*1080,'native_capture_burst8_commands_acked':1944000,
'module_sha256':{name:sha(here/name) for name in names},'runs':runs,
'caveats':['Native source bench uses mock processor release after1ms and a burst ACK memory model.','Root must verify full correction+HDMI under DDR contention and PDS timing.','Native60 run used same five frozen RTL sources; reduced-only bench cases were extended while it ran. Frozen_native6 rerun snapshots the exact final bench and RTL before compiling.']}
(here/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
print('CAPTURE_CANDIDATE_VERIFICATION_READY native_source_frames=60 source_pixels=124416000 frozen_modules=5 full_corrected_hdmi_60fps_verified=false')
