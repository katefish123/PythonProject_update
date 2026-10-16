from pathlib import Path
import json,hashlib,re
here=Path(__file__).resolve().parent
root=Path('D:/FPGA/output')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
names=['continuous_capture_rx.v','continuous_capture_writer.v','continuous_capture_geometry.v','continuous_capture_manager.v','continuous_source_path.v']
runs={}
for suffix in ['timing_boundary_2315','timing_manager_2314','timing_reduced_2314','timing_reduced_57115_2317','timing_native60_57115_2315']:
 folder=here/'evidence/timing_pipeline'/suffix
 if not folder.exists():folder=root/f'c_continuous_capture_20261015_{suffix}'
 p=folder/'simulation.log';raw=p.read_bytes();log=raw.decode('utf-16' if raw.startswith(b'\xff\xfe') else 'utf-8')
 assert 'Errors: 0, Warnings: 0' in log and '** Fatal:' not in log and 'PASS ' in log,suffix
 for name in names:assert sha(folder/'source_snapshot'/name)==sha(here/name),(suffix,name)
 runs[suffix]={'simulation_log':str(p),'log_sha256':sha(p),'compile_log':str(folder/'compile.log'),'compile_sha256':sha(folder/'compile.log'),'source_hashes':str(folder/'source_hashes.txt'),'pass_lines':re.findall(r'^# PASS .*$',log,re.M)}
 if 'native60' in suffix:
  lines=re.findall(r'CAPTURE_DESCRIPTOR native=1 gen=(\d+) bank=(\d) source_frame=(\d+) capture_ms=(\d+) time_ns=(\d+)',log)
  assert len(lines)==60
  assert [int(x[0]) for x in lines]==list(range(1,61))
  assert [int(x[2]) for x in lines]==list(range(1,61))
  assert 'frames=60 commands=1944000 completed=1944000' in log
  runs[suffix]['descriptors']=[{'generation':int(g),'bank':int(b),'source_frame':int(f),'capture_ms':int(t),'timestamp_ps':int(tm)} for g,b,f,t,tm in lines]
  stamps=[int(x[-1]) for x in lines];intervals=[(b-a)/1000 for a,b in zip(stamps,stamps[1:])]
  runs[suffix]['descriptor_intervals_ns']={'minimum':min(intervals),'maximum':max(intervals),'average':sum(intervals)/len(intervals)}
report_path=root/'c_stream_board_v4k_20261015/build_unqualified_20261015_2240/report_timing/video_correct_ddr_top.rtr'
archived_report=here.parent/'evidence/v4k_implementation/final_timing.rtr'
if archived_report.exists():report_path=archived_report
report={'candidate':'capture timing pipeline 2026-10-15 23:13','rtl_sha256':{n:sha(here/n) for n in names},'baseline_physical_timing':{'report':str(report_path),'sha256':sha(report_path),'rx':{'slack_ns':-0.620,'logic_levels':6,'start':'credit_crossing/head[1]','end':'capture/queue[7][176]','report_line':635},'proc':{'slack_ns':-2.660,'logic_levels':23,'start':'manager/generation[1][9]','end':'geometry/detector/snapx[0][14] CE','report_line':1375}},'changes':['RX fixed-bank generation validation registers credit_return0/1 before allocation/packet queue controls; in-flight duplicate suppression protects same-edge reallocation.','PROC clocks detector event data every cycle and valid from FIFO take; END fences event input immediately on handshake, before delayed detector consumption.','B detector and manager/writer/source-path interface unchanged; no timing exception changes.'],'runs':runs,'source_frames_checked':60,'source_pixels_checked':124416000,'native_source_proc_mhz':57.115,'native_source_rx_mhz':148.5,'end_to_end_corrected_hdmi_revalidated':False,'post_change_pds_timing_verified':False,'limitations':['Source bench uses burst ACK memory model and mock processor release after 1ms.','Parent integrates frozen sources for full corrected DDR/HDMI contention and physical PDS timing.']}
(here/'timing_verification.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS timing candidate bound to five frozen RTL files: boundary, manager, reduced54/57.115MHz, native60 frames/124416000pixels/1944000acked commands; post-change PDS pending')
