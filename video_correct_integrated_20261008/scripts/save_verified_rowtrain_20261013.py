"""Save the accepted short-run release and its real media without changing RTL."""
from datetime import datetime,timezone
from pathlib import Path
import hashlib,json,zipfile
R=Path(__file__).resolve().parents[1]
hw=R/'results/hardware_20261009'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
state=json.loads((hw/'rowtrain_camera_state_20261013.json').read_text(encoding='utf-8-sig'))
evidence_path=R/state['latest_camera_verified_evidence']
evidence=json.loads(evidence_path.read_text(encoding='utf-8-sig'))
assert evidence['image_sha256']==state['current_image_sha256']
assert evidence['actual_camera_correction_accepted'] and evidence['short_recording_stable_picture_accepted']
release=R/'release/ddr_camera_hires_rowtrain_20261013'
qualification=json.loads((release/'build_qualification.json').read_text(encoding='utf-8-sig'))
for name,h in qualification['files'].items():assert sha(release/name)==h,name
sources=json.loads((release/'source_hashes.json').read_text(encoding='utf-8-sig'))
for path,h in sources.items():assert sha(Path(path))==h,path
guide=f'''# 当前工程入口

当前可用版：高清行读取修复版。960×540源采样，640×904校正结果，1080p中心显示，无诊断格。Program/Verify、十四项检查和最终时序通过；当前实际相机录像已核对，完整纸页出现后约26.1秒没有缺行、黑屏或退彩条，用户也确认稳定不闪烁。此处只接受本次短测，长时间运行、断电恢复及实际处理更新帧率尚未验收。

| 用途 | 文件 |
| --- | --- |
| 当前PDS工程 | diagnostics/ddr_camera_hires_rowtrain_20261013/results/ddr_camera_hires_rowtrain.pds |
| 当前下载入口 | 下载高清校正_行读取修复版.cmd |
| 码流、资格记录和源码闭包 | release/ddr_camera_hires_rowtrain_20261013 |
| 当前状态 | results/hardware_20261009/rowtrain_camera_state_20261013.json |
| 本次实际验收 | results/hardware_20261009/rowtrain_camera_verified_20261013_003121.json |
| 保存的实际录像 | results/hardware_20261009/rowtrain_corrected_camera_20261013_003121.mp4 |
| 问题及修复 | docs/高清行读取修复_20261013.md |
| 基础版恢复 | 下载相机校正_重连版.cmd |
| 相机大角标测试图 | 显示相机测试图_大角标.cmd |
| OBS | 打开OBS.cmd |

码流SHA256：{state['current_image_sha256']}。
本次下载回读日志：{state['program_log']}。
实际录像SHA256：{evidence['video_sha256']}。

当前程序保留在板内临时CRAM，未写Flash；断电后需要再次运行上述当前下载入口。保持R50→FPGA HDMI-IN；FPGA HDMI-OUT→采集卡；USB→电脑。R50 FHD59.94/HDMI1080p，OBS1920×1080、NV12、30帧。下载后OBS取消激活采集源，等2秒再激活。KEY0用于逻辑复位，仅在恢复需要时使用。

原材料、基础版、旧高清失败证据、原测试图及大角标测试图都保留。本轮只改显示读取衔接，108个其余编译文件内容不变；保留一条未完成DDR命令和完整行确认。双缓存只显示完成的校正结果，测试图退出后保留最后完成画面是设计行为，不能据此声称算法30/60FPS实时更新。

录像开头约7.6秒为启动彩条，此后782个被分析的视频帧均为完整纸页；抽帧可见从初始失焦到文字逐渐清楚，但尚未完成同一光学条件的定量清晰度比较。测试图上的320×452为原图文字，当前芯片结果配置是640×904。

下一轮整体验收：长时间运行、断电后重新下载恢复、实际处理更新帧率。当前工作版已保存，本轮无需再操作或重录。桌面自动控制继续停用。
'''
(R/'docs/当前工程入口_20261011.md').write_text(guide,encoding='utf-8')
prefix='''## 2026-10-13 最新：高清行读取版实际短测通过，已保存

当前码流eb06c8f9；真实下载回读、十四项仿真和最终时序通过。00:31:21实际录像经过FPGA完成光学校正，完整图出现后约26.1秒未检测到缺行/黑屏/退彩条，用户确认不闪烁。当前960×540源、640×904结果可用版已保存。最新状态和入口见docs/当前工程入口_20261011.md、results/hardware_20261009/rowtrain_camera_state_20261013.json。仍需后续长时间运行、断电恢复和实际算法更新帧率验收；不可沿用视频编码30fps充当处理帧率。以下为历史阶段记录。

'''
for relative in ['README.md','docs/继续工作.md','docs/相机校正接续_20261011.md']:
    p=R/relative
    old=p.read_text(encoding='utf-8-sig')
    if '高清行读取版实际短测通过，已保存' not in old:p.write_text(prefix+old,encoding='utf-8')
report=R/'docs/高清行读取修复_20261013.md'
old=report.read_text(encoding='utf-8-sig')
note='''
## 实际短测结果（2026-10-13 00:31:21）

当前eb06c8f9码流真实下载回读通过之后，用户保持经过板子的链路完成新录像并确认完整图稳定、不闪烁。原文件25,347,429字节、33.73秒，视频SHA256为6ad598aa4c364b8acce394e887cc0b444813919a2728d70372488c9cf45e2b8d。分析1011个已解码视频帧，约7.63秒后出现完整白纸页；此后的782帧（约26.07秒）没有检测到缺行、整屏黑画面或退彩条。原始九张抽帧及末尾完整1920×1080图片已人工核对四角、标题、网格和文字。

该录像、探测数据和正式验收收据保存于results/hardware_20261009；原录像未改。本轮接受完整光学相机校正及短时间不闪烁，不扩大到长时间、断电恢复、精确处理帧率或量化清晰度。当前配置为640×904结果。保留此工作版本，不需要重复录像。
'''
if '实际短测结果（2026-10-13 00:31:21）' not in old:report.write_text(old+note,encoding='utf-8')
save_path=hw/'verified_rowtrain_saved_20261013_003121.json'
package=R/'release/verified_rowtrain_camera_20261013_003121.zip'
assert not package.exists()
files=list(release.glob('*'))+[Path(p) for p in sources]
D=R/'diagnostics/ddr_camera_hires_rowtrain_20261013'
O=D/'results'
files+=list(D.glob('*.py'))+list(D.glob('*.ps1'))+list(D.glob('*.sv'))
files+=list(O.glob('tb*.sv'))+list(O.glob('tb*.do'))+list(O.glob('*.hex'))
files+=[O/'build.tcl',O/'ddr_camera_hires_rowtrain.pds',O/'simulation_cases.json',O/'rowtrain_comparison.json',O/'fixture.json',O/'configuration.json']
files+=list((R/'vendor/b/vectors').glob('*.hex'))+list((R/'vendor/b/python').rglob('*.py'))
files+=list((hw/'rowtrain_probe_20261013_003121').glob('*'))
files+=[evidence_path,hw/'rowtrain_camera_state_20261013.json',hw/'rowtrain_corrected_camera_20261013_003121.mp4',hw/'rowtrain_camera_obs_20261013_003121.log',R/state['program_log'],
    R/'scripts/program_ddr_camera_hires_rowtrain.ps1',R/'pds/program_ddr_camera_hires_rowtrain.tcl',
    R/'scripts/record_rowtrain_camera_program_20261013.py',R/'scripts/probe_rowtrain_video_20261013.py',
    R/'scripts/record_rowtrain_camera_verified_20261013.py',R/'scripts/save_verified_rowtrain_20261013.py',R/'scripts/publish_rowtrain_entry_20261013.py',
    R/'下载高清校正_行读取修复版.cmd',R/'显示相机测试图.cmd',R/'显示相机测试图_大角标.cmd',
    R/'scripts/show_camera_target.py',R/'scripts/show_camera_target_large.py',R/'打开OBS.cmd',
    R/'results/camera_target_large_20261011/source_large_markers_640x480.png',R/'results/ddr_fixture/source_640x480.png',
    R/'docs/当前工程入口_20261011.md',R/'docs/高清行读取修复_20261013.md',R/'docs/hardware_20261009.json',R/'docs/继续工作.md',R/'README.md',
    R/'diagnostics/ddr_camera_hires_prefetch_20261012/results/ddr_result_display.v',
    O/'rejected_simultaneous_overload_new.log',O/'simultaneous_overload_old_control.log']
files=list(dict.fromkeys(p for p in files if p.is_file()))
manifest={'saved_at_utc':datetime.now(timezone.utc).isoformat(),
    'current_image':state['current_image'],'current_image_sha256':state['current_image_sha256'],
    'actual_short_optical_test_accepted':True,'flash_modified':False,
    'remaining_acceptance':['long run','cold boot recovery','actual algorithm update FPS','controlled optical sharpness comparison'],
    'original_A_B_C_modified':False,'original_video_modified':False,
    'file_hashes':{p.relative_to(R).as_posix():sha(p) for p in files}}
with zipfile.ZipFile(package,'x',zipfile.ZIP_DEFLATED,compresslevel=5) as z:
    for p in files:
        z.write(p,p.relative_to(R).as_posix(),compress_type=zipfile.ZIP_STORED if p.suffix in ['.zip','.mp4','.jpg','.png'] else zipfile.ZIP_DEFLATED)
    z.writestr('VERIFIED_SAVE_MANIFEST.json',json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
with zipfile.ZipFile(package) as z:
    assert z.testzip() is None
    assert all(hashlib.sha256(z.read(name)).hexdigest()==h for name,h in manifest['file_hashes'].items())
saved={'saved_at_utc':manifest['saved_at_utc'],'package':str(package.relative_to(R)),'package_bytes':package.stat().st_size,
    'package_sha256':sha(package),'file_count':len(files),'zip_crc_and_hashes_verified':True,
    'current_image_sha256':state['current_image_sha256'],'actual_evidence':str(evidence_path.relative_to(R)),
    'preserved_video':state['latest_preserved_video'],'original_A_B_C_modified':False,'original_video_modified':False,'paused_by_user':False}
save_path.write_text(json.dumps(saved,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(saved,ensure_ascii=False,indent=2))
