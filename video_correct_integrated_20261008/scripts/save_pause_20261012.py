"""Freeze the verified baseline and the high-detail candidate without programming."""
from datetime import datetime,timedelta,timezone
from pathlib import Path
import hashlib
import json
import zipfile

R=Path(__file__).resolve().parents[1]
hw=R/"results/hardware_20261009"
candidate=R/"diagnostics/ddr_camera_hires_prefetch_20261012"
O=candidate/"results"
now=datetime.now(timezone.utc)
local=now.astimezone(timezone(timedelta(hours=8)))
stamp=local.strftime("%Y%m%d_%H%M%S")
board_path=hw/"clean_camera_state_20261011.json"
board=json.loads(board_path.read_text(encoding="utf-8-sig"))
receipt=json.loads((hw/"baseline_recovered_verified_20261012.json").read_text(encoding="utf-8-sig"))
assert board["current_image_sha256"]=="a4bd7f42732c100b598cb974e03477877aab4032e39f6de558bb245d666e232e"
assert board["actual_camera_correction_accepted"] and receipt["full_page_visually_checked"]
tests=json.loads((O/"simulation_qualification.json").read_text(encoding="utf-8-sig"))
assert len(tests["tests"])==12 and all(t["passed"] for t in tests["tests"].values())
for t in tests["tests"].values():
    assert hashlib.sha256(Path(t["log"]).read_bytes()).hexdigest()==t["log_sha256"]
timing=(O/"report_timing/video_correct_ddr_top.rtr").read_text(encoding="utf-8-sig",errors="replace")
build=(O/"build_run.log").read_text(encoding="utf-8-sig",errors="replace")
bit=O/"generate_bitstream/video_correct_ddr_top.sbit"
mask=bit.with_suffix(".smsk")
record={
 "saved_at_utc":now.isoformat(),"saved_at_local":local.isoformat(),"paused_by_user":True,
 "pause_request":"今天就先到这吧，高清晰度的明天再搞，先保存",
 "current_board_image":board["current_image"],"current_board_image_sha256":board["current_image_sha256"],
 "current_program_log":board["program_log"],"working_baseline_evidence":"results/hardware_20261009/baseline_recovered_verified_20261012.json",
 "working_baseline_video":"results/hardware_20261009/clean_corrected_camera_20261012_003742.mp4",
 "current_baseline_complete_correction_verified":True,"baseline_short_stable_encoded_picture_seconds":receipt["stable_encoded_picture_seconds_approximately"],
 "baseline_clarity_improvement_accepted":False,"algorithm_update_fps_measured":False,
 "high_detail_project":"diagnostics/ddr_camera_hires_prefetch_20261012/results/ddr_camera_hires_prefetch.pds",
 "high_detail_source":[960,540],"high_detail_result":[640,904],"display":[1920,1080],
 "high_detail_twelve_simulations_passed":True,"high_detail_build_completed":"Executing : gen_bit_stream successfully." in build,
 "high_detail_timing_report_all_constraints_met":"Design Summary : All Constraints Met." in timing,
 "high_detail_generated_bitstream":str(bit.relative_to(R)),"high_detail_generated_bitstream_sha256":hashlib.sha256(bit.read_bytes()).hexdigest(),
 "high_detail_generated_mask_sha256":hashlib.sha256(mask.read_bytes()).hexdigest(),
 "high_detail_release_sealed":False,"high_detail_programmed":False,"high_detail_real_camera_accepted":False,
 "flash_modified":False,"original_A_B_C_modified":False,"original_target_and_Esc_modified":False,
 "computer_use_paused_by_user":True,"active_prefetch_build":False,
 "resume":"Wait for user resume. Check power/devices, seal the qualified high-detail release, update its current state/video analyzer, then Program/Verify and compare actual same-target clarity/full rows. Restore a4 if needed."
}
pause_path=hw/"paused_work_20261012.json"
pause_path.write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
board.update(paused_by_user=True,paused_at_utc=now.isoformat(),
    pending="Paused by user. Working baseline retained. High-detail build/timing completed, but release is not sealed or programmed. Resume only on user instruction.")
board_path.write_text(json.dumps(board,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
main_path=R/"docs/hardware_20261009.json"
main=json.loads(main_path.read_text(encoding="utf-8-sig"))
assert main["current_image_sha256"]==board["current_image_sha256"]
main.update(paused_by_user=True,paused_at_utc=now.isoformat(),last_update_utc=now.isoformat(),
    pause_record=str(pause_path.relative_to(R)),pending=board["pending"],
    current_high_detail_project=record["high_detail_project"],high_detail_candidate_programmed=False,
    high_detail_twelve_simulations_passed=True,high_detail_timing_report_all_constraints_met=record["high_detail_timing_report_all_constraints_met"])
main_path.write_text(json.dumps(main,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
note=f'''# 2026-10-12 保存与明日接续

已按用户要求暂停，保存于{local.strftime("%Y-%m-%d %H:%M:%S")}（北京时间）。今天不再切换板上程序。

当前板上是实测基础a4校正版：640×480源、320×452结果、放大2倍置于1080p输出。最近下载日志为program_ddr_camera_reconnect_20261011_235140.log，Program/Verify通过。用户接回板子后彩条恢复，随后完整矩形校正图恢复；00:37:42实际录像已经复制、解码和目视核验。1765个编码帧中，首次校正页出现后1567帧（约52秒）没有黑屏或退回彩条。开始时光学失焦、之后文字与网格可见，但仍有模糊/屏幕摩尔纹。稳定保持画面不能证明算法更新帧率。

基础恢复证据：results/hardware_20261009/baseline_recovered_verified_20261012.json。
实际录像：results/hardware_20261009/clean_corrected_camera_20261012_003742.mp4。
码流SHA256：{board["current_image_sha256"]}。
恢复入口：下载相机校正_重连版.cmd。

高清连续读取修复副本：{record["high_detail_project"]}。保留960×540源、640×904结果、1080p输出及原检测条件；修正Pango块RAM属性，结果区每次预读8个拍，保持原单命令/单响应接口。十二项仿真通过，包含578560个算法参考像素、1080p源采集、完整两帧显示/换帧、缓存一致性与错误/超时/复位、真实核心/内存适配器以及采集/处理/显示同时争用。在假定28周期首拍与偶发100周期刷新等待模型下，共检查1157120个显示像素；共享负载无黑行、采集最大积压8包。模型时间不是实测DDR速度。

用户要求暂停时，本轮构建已在后台自行结束，码流与掩码均已生成，时序报告显示全部约束满足。原始新码流SHA256：{record["high_detail_generated_bitstream_sha256"]}。尚未封装正式资格发布，尚未下载，高清真实清晰度与稳定性未验收。当前硬件仍是基础a4，不能把新码流的仿真结果当成板上画面。

明天接续：

1. 用户说继续后，再检查板子上电、FTDI下载器、VC-002Pro、R50短片取景及接线：相机→FPGA HDMI-IN；FPGA HDMI-OUT→采集卡；USB→电脑。OBS保持1920×1080、NV12、30帧。若已经断电，CRAM临时程序消失，需要重新下载；今天没有写Flash。
2. 核对新副本源哈希、十二项日志、最终时序、码流/掩码，然后封装独立release/ddr_camera_hires_prefetch_20261012资格发布及源码闭包。该发布目前不存在；高清连续读取下载入口已准备，但发布封装前不能使用。基础a4发布与全部旧码流保留。
3. 编写新连续读取码流的当前状态记录，调整真实录像分析入口指向新状态。旧--hires入口读取旧7aed状态，不能用于新连续读取版，以免录像归属错误。
4. 新版本完成Program/Verify后，保持相机位置/焦距/对焦、同一大角标测试图与HDMI线。OBS手动取消激活/等待2秒/激活，保存约30秒实际录像，核验完整页、字迹、黑行/闪烁/黑屏及持有结果。若无信号先恢复输出；不要把相机直连画面当成FPGA证据。

原始A/B/C、原测试图、Esc行为、相机/OBS参数均保留。桌面自动控制仍暂停。
机器状态：results/hardware_20261009/paused_work_20261012.json。
'''
note_path=R/"docs/保存与接续_20261012.md"
note_path.write_text(note,encoding="utf-8")
prefix='''## 2026-10-12 最新：已保存，按用户要求暂停

当前保留实测基础a4版，完整校正图在00:37:42实录中恢复，首次出现后的约52秒无黑屏或退回彩条。高清连续读取副本十二项检查通过，本轮构建已结束，时序报告满足；未封装正式发布、未下载到板子，实际清晰度仍待明天验证。工程记录：docs/保存与接续_20261012.md；机器状态：results/hardware_20261009/paused_work_20261012.json。断电后临时CRAM程序需要重下，未写Flash。以下均为历史阶段记录。

'''
for relative in ["README.md","docs/继续工作.md","docs/相机校正接续_20261011.md"]:
    p=R/relative
    old=p.read_text(encoding="utf-8-sig")
    if "2026-10-12 最新：已保存，按用户要求暂停" not in old:p.write_text(prefix+old,encoding="utf-8")
guide=R/"docs/当前工程入口_20261011.md"
old=guide.read_text(encoding="utf-8-sig")
if "## 2026-10-12 已保存并暂停" not in old:
    guide.write_text("## 2026-10-12 已保存并暂停\n\n当前基础版完整校正图已恢复并实录核验。高清连续读取副本已生成、时序报告满足，未封装发布/未上板。最新状态及接续步骤见docs/保存与接续_20261012.md；下面的待确认表述属于历史。\n\n"+old,encoding="utf-8")
files=set()
def include(path):
    p=Path(path).resolve()
    p.relative_to(R)
    if p.is_file():files.add(p)
for release in ["ddr_camera_reconnect_20261011","ddr_camera_hires_20261011","ddr_camera_hires_status_20261011"]:
    folder=R/"release"/release
    for p in folder.iterdir():include(p)
    for p in json.loads((folder/"source_hashes.json").read_text(encoding="utf-8-sig")):include(p)
for p in json.loads((O/"source_hashes.json").read_text(encoding="utf-8-sig")):include(p)
for root in [R/"scripts",R/"pds",R/"docs",R/"sim",R/"vendor/b/python",R/"vendor/b/vectors"]:
    for p in root.rglob("*"):
        if p.suffix.lower() in {".py",".ps1",".tcl",".do",".sv",".v",".json",".md",".hex",".cmd",".txt"}:include(p)
for p in R.glob("*.cmd"):include(p)
include(R/"README.md")
for folder in [candidate,R/"diagnostics/ddr_hires_read_ahead_20261011",R/"diagnostics/ddr_camera_hires_20261011",
               R/"diagnostics/ddr_camera_hires_status_20261011",R/"diagnostics/ddr_camera_reconnect_20261011"]:
    for p in folder.iterdir():
        if p.suffix.lower() in {".py",".ps1",".sv",".v",".md"}:include(p)
    results=folder/"results"
    for p in results.iterdir():
        if p.suffix.lower() in {".v",".sv",".json",".hex",".png",".pds",".tcl",".do",".log"}:include(p)
    for sub,extensions in [("report_timing",{".rtr"}),("generate_bitstream",{".sbit",".smsk"})]:
        for p in (results/sub).glob("*"):
            if p.suffix.lower() in extensions:include(p)
for name in ["clean_camera_state_20261011.json","baseline_recovered_verified_20261012.json",
 "clean_corrected_camera_20261012_003742.json","clean_corrected_camera_20261012_003742.mp4",
 "clean_corrected_camera_20261012_003742_first.png","clean_corrected_camera_20261012_003742_middle.png","clean_corrected_camera_20261012_003742_last.png",
 "working_clean_baseline_verified_20261011.json","capture_hdmi_recovery_latest_20261011.json",
 "hires_status_state_20261011.json","hires_camera_state_20261011.json","hires_display_failure_20261011_211430.json",
 "paused_work_20261012.json","program_ddr_camera_reconnect_20261011_235140.log"]:include(hw/name)
for folder in [R/"results/camera_target_large_20261011",R/"results/ddr_fixture"]:
    for p in folder.glob("*"):
        if p.suffix.lower() in {".json",".png",".hex"}:include(p)
manifest={p.relative_to(R).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
bundle=R/"release"/("paused_fpga_"+stamp+".zip")
with zipfile.ZipFile(bundle,"x",zipfile.ZIP_DEFLATED) as z:
    for p in sorted(files):z.write(p,p.relative_to(R).as_posix())
    z.writestr("pause/manifest.json",json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")
with zipfile.ZipFile(bundle) as z:assert z.testzip() is None
bundle_record={"saved_at_utc":now.isoformat(),"archive":str(bundle.relative_to(R)),
 "archive_sha256":hashlib.sha256(bundle.read_bytes()).hexdigest(),"file_count":len(files),
 "bytes":bundle.stat().st_size,"verified_zip_crc":True,"current_board_unchanged":True,
 "paused_by_user":True,"resume_document":str(note_path.relative_to(R))}
(hw/"pause_archive_20261012.json").write_text(json.dumps(bundle_record,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(json.dumps(bundle_record,ensure_ascii=False,indent=2))
