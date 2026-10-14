"""Present preserved hardware evidence without changing the qualified releases."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
from PIL import Image

ROOT = Path('C:/D/FPGA/video_correct_integrated_20261008')
OUT = ROOT / 'results/成果展示_20261014'
SOURCE = ROOT / 'results/hardware_20261014_black/black_camera_2026-10-14 01-14-46.mp4'
EXPECTED_SOURCE_SHA = '5a02b7913ee067fac62f813d1f6be7ce436e9d28f8397750bedd769c5d70a8bd'
FFMPEG = ROOT / 'tools/python_packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    assert sha(SOURCE) == EXPECTED_SOURCE_SHA, 'Preserved hardware video checksum changed'
    OUT.mkdir(exist_ok=True)
    demo = OUT / '黑标校正_旧版真实上板演示.mp4'
    preview = OUT / '黑标校正_旧版真实上板截图.png'
    source_frame = ROOT / 'results/hardware_20261014_black/black_probe_20261014_011446/sample_02_20.48s.png'
    with Image.open(source_frame) as frame:
        # Only remove the external HDMI black surround; retain the whole result
        # including the lower gray strip and slight geometric errors.
        frame.crop((640, 88, 1280, 992)).save(preview)
    simulation = OUT / '提速版_合成测试前后对照.png'
    shutil.copyfile(ROOT / 'release/ddr_camera_black_fast_20261014/black_correction_preview.png', simulation)
    if not demo.exists():
        cmd = [str(FFMPEG), '-nostdin', '-n', '-hide_banner', '-loglevel', 'info',
               '-ss', '8.17', '-i', str(SOURCE), '-t', '32.7', '-an',
               '-vf', 'crop=640:904:640:88', '-c:v', 'libx264', '-preset', 'veryfast',
               '-crf', '18', '-pix_fmt', 'yuv420p', '-fps_mode', 'passthrough',
               '-movflags', '+faststart', str(demo)]
        with (OUT / '演示导出.log').open('wb') as log:
            subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=50)
    qualification = json.loads((ROOT / 'release/ddr_camera_black_fast_20261014/build_qualification.json').read_text(encoding='utf-8-sig'))
    fast_receipt = ROOT / 'results/hardware_20261014_black_fast/black_fast_program_20261014_125009.json'
    receipt = json.loads(fast_receipt.read_text(encoding='utf-8-sig'))
    assert receipt['program_verify_passed'] and not receipt['flash_modified']
    report = {
        'created_utc': datetime.now(timezone.utc).isoformat(),
        'hardware_video_version': 'historical_baseline_black_873cb996',
        'hardware_video_recorded_local': '2026-10-14 01:14:46 Asia/Shanghai',
        'source_video': str(SOURCE), 'source_video_sha256': EXPECTED_SOURCE_SHA,
        'demo_source_start_seconds': 8.17, 'demo_seconds_requested': 32.7,
        'crop_xywh': [640, 88, 640, 904], 'audio_in_demo': False,
        'fast_bitstream_sha256': receipt['bitstream_sha256'],
        'fast_program_verify_passed': True, 'fast_program_receipt': str(fast_receipt),
        'baseline_model_seconds': qualification['baseline_modeled_frame_cycles'] / 27_000_000,
        'fast_model_seconds': qualification['modeled_27mhz_seconds'],
        'model_time_reduction_percent': 100 * (1 - qualification['modeled_frame_cycles'] / qualification['baseline_modeled_frame_cycles']),
        'fast_python_native_system_checks': [17, 9, 16],
        'exact_rgb_pixels': qualification['whole_frame_exact_rgb_pixels'],
        'latest_resident_program': 'baseline_black_873cb996_reloaded_20261014_130506',
        'fast_optical_speed_comparison_passed': False,
        'absolute_end_to_end_latency_measured': False,
        'geometric_accuracy_accepted': False,
        'free_360_degree_rotation_accepted': False,
        'realtime_30fps_accepted': False,
        'latest_observation': 'Fast probes 13:02:44 and 13:04:37 were pixel-identical despite a moving counter. Reloaded baseline produced color bars at 13:06:54 and 13:07:52. Source/ROI and input-state inspection remains necessary.',
        'files_sha256': {p.name: sha(p) for p in (demo, preview, simulation)},
    }
    (OUT / '成果证据.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    text = '''# 黑色角标校正：当前可展示成果

真实上板演示视频和截图来自2026年10月14日01:14:46保存的旧黑标版873cb996录像，物理链路为相机→FPGA→采集卡。演示保留完整640×904处理区域，包括底部灰边和轻微歪斜；只去除了HDMI外围黑色区域。它证明曾经通过FPGA显示完整黑标纸页，不能证明新版实拍速度或精确几何完成。

![旧版真实上板截图](黑标校正_旧版真实上板截图.png)

[旧版真实上板演示视频](黑标校正_旧版真实上板演示.mp4)

提速版39574d43已经生成并通过真实Program/Verify，未写Flash。17项Python模型、9项原生算法、16项系统检查和578560个完整RGB像素对照通过，最终时序通过。优化包含四个检测区域扫描、两级缓存、读取/插值/写入重叠。同一模拟内存模型下456.1→236.8ms，处理时间缩短48.1%；这是仿真数据。

![合成测试输入与参考校正](提速版_合成测试前后对照.png)

当前实拍速度对照尚未通过：用户确认计数源在变化，提速版两次探测输出却像素完全相同；旧版重载后仍为彩条。还需检查相机原始取景与固定检测窗口、输入状态。现在板上为对照重载的旧黑标版。新版不能声称已经达到实时30fps或任意0～360°角度。

原视频、发布文件和源码封存均保留。来源、程序下载回读记录及各展示文件SHA256见“成果证据.json”。
'''
    (OUT / '成果说明.md').write_text(text, encoding='utf-8')
    print(json.dumps({'demo': str(demo), 'preview': str(preview), 'report': str(OUT / '成果说明.md')}, ensure_ascii=False))


if __name__ == '__main__':
    main()
