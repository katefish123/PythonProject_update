"""Finalize this measured optical round, then honor the explicit user pause."""
from pathlib import Path
from datetime import datetime,timezone,timedelta
import csv,hashlib,json,shutil,zipfile
R=Path(__file__).resolve().parents[1]
hw=R/'results/hardware_20261009'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
state_path=hw/'rowtrain_camera_state_20261013.json'
state=json.loads(state_path.read_text(encoding='utf-8-sig'))
image=R/state['current_image']
assert sha(image)==state['current_image_sha256']=='eb06c8f9645665111b339e2ea305549a107830275d50f7625245b163b371d987'
assert sha(R/state['program_log'])==state['program_log_sha256']
primary_path=hw/'rowtrain_update_20261013_143010/measurement.json'
cross_path=hw/'rowtrain_update_20261013_143154/measurement.json'
primary=json.loads(primary_path.read_text(encoding='utf-8-sig'))
cross=json.loads(cross_path.read_text(encoding='utf-8-sig'))
assert primary['image_sha256']==cross['image_sha256']==state['current_image_sha256']
assert primary['program_log']==cross['program_log']==state['program_log']
assert primary['counter_decode_sufficient_for_observed_rate'] and primary['observed_distinct_update_hz']==0.85
assert len(primary['groups'])==18 and primary['valid_counter_frames']==679
assert all(s['dark_rows']==0 for s in primary['frames'] if s['counter'] is not None)
stimulus=R/'results/camera_update_counter_20261013/actual_stimulus_20261013_143014.csv'
rows=list(csv.DictReader(stimulus.open(encoding='utf-8')))
assert all(g['counter'] in {int(r['counter']) for r in rows} for g in primary['groups'])
# The raw analysis helper initially selects the latest CSV. Use and record
# the matching original session explicitly instead of treating that field as proof.
cross_groups=cross['groups'][1:]
assert cross['groups'][0]['counter']==235 and cross_groups[0]['counter']==46
assert all(0<(b['counter']-a['counter'])<250 for a,b in zip(cross_groups,cross_groups[1:]))
cross_rate=(len(cross_groups)-1)/(cross_groups[-1]['encoded_seconds']-cross_groups[0]['encoded_seconds'])
assert abs(cross_rate-0.85)<0.01
for q,tag in [(primary,'143010'),(cross,'143154')]:
    original=Path(q['original_video'])
    assert sha(original)==q['original_sha256']
    saved=hw/f'rowtrain_update_camera_20261013_{tag}.mp4'
    if saved.exists():assert sha(saved)==q['original_sha256']
    else:shutil.copyfile(original,saved)
now=datetime.now(timezone.utc).isoformat()
receipt={
    'verified_at_utc':now,'current_image':state['current_image'],'image_sha256':state['current_image_sha256'],
    'program_log':state['program_log'],'program_log_sha256':state['program_log_sha256'],
    'physical_route':'R50 -> FPGA HDMI-IN -> FPGA HDMI-OUT -> VC-002Pro -> PC USB',
    'user_report':'Complete corrected picture; user initially perceived LIVE value as unchanged. Recordings stopped.',
    'actual_observation':'Actual saved images visibly show LIVE0046 and LIVE0138; primary recording decodes0034 through0235 in18 successive result groups. Whole corrected page and four corners visually checked.',
    'primary_measurement':str(primary_path.relative_to(R)),'primary_measurement_sha256':sha(primary_path),
    'primary_original_video':primary['original_video'],'primary_video_sha256':primary['original_sha256'],
    'primary_preserved_video':'results/hardware_20261009/rowtrain_update_camera_20261013_143010.mp4',
    'matching_stimulus_csv':str(stimulus.relative_to(R)),'matching_stimulus_csv_sha256':sha(stimulus),
    'all_decoded_values_present_in_matching_stimulus':True,
    'raw_latest_stimulus_association_corrected_in_this_receipt':True,
    'observed_distinct_updates':17,'observed_update_span_seconds':20.0,
    'observed_output_update_hz':0.85,'observed_mean_inter_update_seconds':20.0/17,
    'valid_decoded_page_frames':679,'valid_decoded_page_span_seconds':22.6,'missing_dark_rows_in_valid_page':0,
    'cross_measurement':str(cross_path.relative_to(R)),'cross_measurement_sha256':sha(cross_path),
    'cross_original_video':cross['original_video'],'cross_video_sha256':cross['original_sha256'],
    'cross_preserved_video':'results/hardware_20261009/rowtrain_update_camera_20261013_143154.mp4',
    'cross_single_session_rate_hz':cross_rate,
    'cross_note':'Initial235 is the previously held result; optical viewer was restarted. Exclude235->46 reset/startup interval from steady rate. New session46..164 has10 changes in11.8s.',
    'current_boot_optical_picture_verified':True,'actual_camera_correction_accepted':True,
    'observed_output_update_rate_measured':True,'exact_internal_publish_fps_proven':False,
    'maximum_processing_throughput_proven':False,'long_term_stability_verified':False,
    'scope':'Observed distinct visible corrected counter updates under10Hz optical stimulus at source960x540/result640x904. Not HDMI carrier/OBS30fps. Holds and duplicate encoded frames do not count. Does not prove internal maximum FPS or controlled sharpness.',
    'fpga_code_changed_this_round':False,'original_A_B_C_modified':False,'original_video_modified':False,'flash_modified':False,
}
receipt_path=hw/'rowtrain_actual_update_rate_verified_20261013.json'
receipt_path.write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
pending='Paused at explicit user request. Preserve working eb06c8f9 release. On resume check power/connections and reprogram same image if power was lost. Next investigate per-stage processing waits and improve update throughput in an independent clone; current640x904 observed rate0.85Hz. No changes while paused.'
updates=dict(paused_by_user=True,paused_at_utc=now,current_boot_optical_picture_verified=True,
    current_boot_video_analysis=str(primary_path.relative_to(R)),current_boot_video_evidence=str(receipt_path.relative_to(R)),
    actual_camera_correction_accepted=True,actual_camera_display_accepted=True,actual_camera_display_accepted_for_current_image=True,
    full_corrected_page_observed_for_current_image=True,short_recording_stable_picture_accepted=True,
    algorithm_update_fps_measured=True,algorithm_update_fps_measured_method='Visible distinct corrected optical counter groups; observed output rate, not proof of internal maximum throughput',
    observed_corrected_output_update_hz=0.85,observed_mean_inter_update_seconds=20/17,
    latest_performance_evidence=str(receipt_path.relative_to(R)),latest_video_analysis=str(primary_path.relative_to(R)),
    latest_original_video=primary['original_video'],latest_video_sha256=primary['original_sha256'],
    latest_preserved_video=receipt['primary_preserved_video'],current_failed_stage=None,
    long_term_camera_display_verified=False,pending=pending,
    phase='Paused: high-detail picture/cold-boot recovery/current optical updates verified; throughput0.85Hz requires improvement',
    qualification_limit=receipt['scope'])
state.update(updates,last_verified_at_utc=now)
state_path.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
main_path=R/'docs/hardware_20261009.json'
main=json.loads(main_path.read_text(encoding='utf-8-sig'))
assert main['current_image_sha256']==state['current_image_sha256']
main.update(updates,last_update_utc=now,capture_result='Paused by user after real current-boot optical validation. Counter does update:17 changes in20s (~0.85Hz). Complete page has no missing rows in679 decoded page frames. Preserve this stable image; throughput optimization remains.')
main_path.write_text(json.dumps(main,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
pause_doc='''# 本轮保存与接续（2026-10-13）

用户要求“思考完这一轮就先暂停”，本轮已完成分析并暂停。当前芯片仍为已验证eb06c8f9高清行读取版，960×540源采样、640×904结果；未改变RTL或重新下载其他版本，未写Flash。原A/B/C和旧静态测试图、所有原录像保留。

当前工程：diagnostics/ddr_camera_hires_rowtrain_20261013/results/ddr_camera_hires_rowtrain.pds。
断电后的恢复入口：下载高清校正_行读取修复版.cmd。
最新状态：results/hardware_20261009/rowtrain_camera_state_20261013.json。
性能实测：results/hardware_20261009/rowtrain_actual_update_rate_verified_20261013.json。

本轮LIVE并未冻结：14:30:10录像解析出0034→0046→0058→…→0235共18组结果，20秒内17次变化，实际观察到0.85次/秒，平均约1.18秒/次。679个有效纸页视频帧没有检测到缺行，四角和文字已查看。独立14:31:54录像在剔除重新打开测试图前保留的0235后，0046→…→0164每约1.17秒更新，得到约0.847Hz。视频/HDMI的30或60帧是显示刷新，不能替代校正结果更新速度。测得的是可见更新率，尚不是内部最大处理吞吐率。

测试图输入CSV与解出的每个计数值都匹配。原分析器会默认写入最新CSV名称，主要录像的真实匹配文件是actual_stimulus_20261013_143014.csv；正式收据已纠正此关联，原分析数据保留。后续分析器需要按录像时间匹配相应测试图实例。

已定位下一轮应检查帧处理吞吐：当前frame_processor明确每次只处理一个像素，包含B的22周期坐标管线及串行四邻点读取；处理时钟27MHz。ddr_pixel_cache已是两条256位缓存，不能将它误认为单条缓存。先在独立克隆里统计扫描、坐标等待、取样、写回等阶段成本，再选择有证据的优化。当前稳定版本保留为对照，不在暂停期间修改。

较长时间稳定性和量化清晰度仍未验收。昨晚实际恢复录像只有约33.5秒有效校正画面，按真实范围接受断电后重新下载的恢复，没有将它算作两分钟测试。

接续时先检查板子/相机/采集卡连接。若暂停期间断电，再重新下载同一已验证程序。用户暂时停用computer-use；继续通过本机文件、工具及用户物理配合完成工作。
'''
(R/'docs/保存与接续_20261013.md').write_text(pause_doc,encoding='utf-8')
prefix='''## 2026-10-13 已按用户要求暂停

当前eb06c8f9可用版及真实录像已保存。LIVE实际有更新：20秒17次，约0.85次/秒（约1.18秒/次）；本轮完整校正图没有缺行，下一轮重点为帧处理效率。最新接续见docs/保存与接续_20261013.md，状态paused_by_user=true。不在暂停期间更改或下载程序。以下为历史记录。

'''
for relative in ['README.md','docs/继续工作.md','docs/相机校正接续_20261011.md','docs/当前工程入口_20261011.md']:
    p=R/relative
    p.write_text(prefix+p.read_text(encoding='utf-8-sig'),encoding='utf-8')
stamp=datetime.now(timezone(timedelta(hours=8))).strftime('%Y%m%d_%H%M%S')
package=R/'release'/f'paused_rowtrain_{stamp}.zip'
files=[R/'release/verified_rowtrain_camera_20261013_003121.zip',receipt_path,state_path,main_path,
    hw/'rowtrain_actual_update_rate_verified_20261013.json',hw/'rowtrain_coldboot_camera_verified_20261013_005755.json',R/state['program_log'],
    hw/'rowtrain_update_camera_20261013_143010.mp4',hw/'rowtrain_update_camera_20261013_143154.mp4',
    R/'docs/保存与接续_20261013.md',R/'docs/继续工作.md',R/'docs/当前工程入口_20261011.md',R/'README.md',
    R/'显示相机测试图_更新速度.cmd',R/'scripts/camera_update_counter.py',R/'scripts/show_camera_target_update.py',
    R/'scripts/analyze_rowtrain_update_video_20261013.py',R/'scripts/prepare_update_counter_entry_20261013.py',
    R/'scripts/record_rowtrain_recovery_and_resume_20261013.py',R/'scripts/save_rowtrain_pause_and_rate_20261013.py']
for name in ['rowtrain_update_20261013_143010','rowtrain_update_20261013_143154','rowtrain_probe_20261013_005755']:
    files+=list((hw/name).glob('*'))
files+=list((R/'results/camera_update_counter_20261013').glob('*'))
files=list(dict.fromkeys(p for p in files if p.is_file()))
manifest={'saved_at_utc':now,'paused_by_user':True,'image_sha256':state['current_image_sha256'],
    'observed_output_update_hz':0.85,'qualification_scope':receipt['scope'],
    'file_hashes':{p.relative_to(R).as_posix():sha(p) for p in files}}
with zipfile.ZipFile(package,'x',zipfile.ZIP_DEFLATED,compresslevel=5) as z:
    for p in files:z.write(p,p.relative_to(R).as_posix(),compress_type=zipfile.ZIP_STORED if p.suffix in ['.mp4','.zip','.png','.jpg'] else zipfile.ZIP_DEFLATED)
    z.writestr('PAUSE_MANIFEST.json',json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
with zipfile.ZipFile(package) as z:
    assert z.testzip() is None
    assert all(hashlib.sha256(z.read(name)).hexdigest()==h for name,h in manifest['file_hashes'].items())
save={'paused_at_utc':now,'paused_by_user':True,'package':str(package.relative_to(R)),
    'package_sha256':sha(package),'package_bytes':package.stat().st_size,'zip_crc_and_hashes_verified':True,
    'current_image_sha256':state['current_image_sha256'],'source_code_and_bitstream_changed':False,
    'actual_update_rate_hz':0.85,'latest_evidence':str(receipt_path.relative_to(R)),'pending':pending}
(hw/'paused_rowtrain_20261013.json').write_text(json.dumps(save,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(save,ensure_ascii=False,indent=2))
