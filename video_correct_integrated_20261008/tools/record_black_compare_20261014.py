"""Bounded capture-card recording for the black-marker optical comparison."""
from datetime import datetime, timezone, timedelta
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import time

R = Path('C:/D/FPGA/video_correct_integrated_20261008')
FFMPEG = R / 'tools/python_packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe'
VIDEO_DEVICE = 'VC-002Pro '


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('phase', choices=('baseline', 'fast'))
    ap.add_argument('--probe', action='store_true')
    ap.add_argument('--seconds', type=int, default=25)
    ap.add_argument('--receipt', type=Path, required=True)
    ap.add_argument('--outdir', type=Path, required=True)
    args = ap.parse_args()
    assert 5 <= args.seconds <= 30
    receipt = json.loads(args.receipt.read_text(encoding='utf-8-sig'))
    assert receipt['program_verify_passed'] and not receipt['flash_modified']
    release = R / 'release' / ('ddr_camera_black_20261014' if args.phase == 'baseline' else 'ddr_camera_black_fast_20261014')
    bit = release / 'video_correct_ddr_top.sbit'
    digest = hashlib.sha256(bit.read_bytes()).hexdigest()
    assert digest == receipt['bitstream_sha256']
    args.outdir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).astimezone(timezone(timedelta(hours=8))).strftime('%Y%m%d_%H%M%S')
    stem = f'{args.phase}_{"probe" if args.probe else "capture"}_{stamp}'
    output = args.outdir / (stem + ('.png' if args.probe else '.mp4'))
    log = args.outdir / (stem + '.log')
    command = [str(FFMPEG), '-nostdin', '-n', '-hide_banner', '-loglevel', 'info',
               '-rtbufsize', '256M', '-f', 'dshow', '-video_size', '1920x1080',
               '-framerate', '30', '-pixel_format', 'nv12', '-i', 'video=' + VIDEO_DEVICE, '-an']
    if args.probe:
        command += ['-ss', '2', '-frames:v', '1', '-update', '1', str(output)]
    else:
        command += ['-t', str(args.seconds), '-c:v', 'libx264', '-preset', 'ultrafast',
                    '-crf', '18', '-pix_fmt', 'yuv420p', '-fps_mode', 'passthrough',
                    '-movflags', '+faststart', str(output)]
    started_utc = datetime.now(timezone.utc).isoformat()
    started = time.monotonic()
    print(json.dumps({'capture_started': str(output), 'phase': args.phase,
                      'probe': args.probe, 'seconds_limit': args.seconds}, ensure_ascii=False), flush=True)
    with log.open('wb') as stream:
        result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT,
                                timeout=20 if args.probe else args.seconds + 25)
    elapsed = time.monotonic() - started
    if result.returncode or not output.is_file() or not output.stat().st_size:
        raise RuntimeError(f'Capture failed, see {log}: {log.read_text(encoding="utf-8", errors="replace")[-1800:]}')
    meta = {'phase': args.phase, 'source': 'VC-002Pro capture card; physical camera-FPGA route confirmed earlier by user',
            'program_receipt': str(args.receipt), 'bitstream_sha256': digest,
            'output': str(output), 'output_sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
            'started_at_utc': started_utc, 'elapsed_wall_seconds': elapsed,
            'capture_profile': {'width': 1920, 'height': 1080, 'requested_device_fps': 30, 'pixel_format': 'nv12'},
            'probe': args.probe, 'recording_seconds_limit': args.seconds,
            'source_counter_period_seconds': 0.1, 'absolute_latency_measured': False,
            'algorithm_update_rate_accepted': False, 'temperature_during_capture_measured': False,
            'ffmpeg_log': str(log), 'command': command}
    output.with_suffix('.json').write_text(json.dumps(meta, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'capture_complete': str(output), 'elapsed_wall_seconds': elapsed,
                      'bytes': output.stat().st_size}, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
