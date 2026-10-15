"""Package qualified PDS output plus three independent black-scene fixtures."""
import argparse, hashlib, json, shutil, subprocess, sys
from pathlib import Path
from verify_sources import verify
HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--build', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    provenance = verify(a.root)
    metrics = a.root/'inline_geometry_metrics.json'
    trace = a.root/'gather_trace.json'
    subprocess.run([sys.executable, str(HERE/'measure.py'), '--root', str(a.root), '--output', str(metrics)], check=True)
    subprocess.run([sys.executable, str(HERE/'trace_gather.py'), '--root', str(a.root), '--output', str(trace)], check=True)
    subprocess.run([sys.executable, str(HERE.parent/'a_sync_20261013/package_hires_reproduction.py'),
                    '--root', str(a.root), '--build', str(a.build), '--output', str(a.output), '--expected-tests', '21'], check=True)
    mp = a.output/'package_manifest.json'
    manifest = json.loads(mp.read_text())
    inputs = json.loads((a.root/'reproduction_manifest.json').read_text())['files']
    extras = {'inline_geometry_metrics.json': metrics, 'gather_trace.json': trace,
              'RELEASE_SCOPE.md': HERE/'RELEASE_SCOPE.md',
              'upstream_manifest.json': HERE.parent/'a_black_sync_20261014/upstream_manifest.json'}
    corners = a.root/'fullhd_tests/source_corners96.hex'
    if sha(corners) != inputs['fullhd_tests/source_corners96.hex']['local_sha256']:
        raise RuntimeError('Changed geometry fixture')
    extras['fixture/source_corners96.hex'] = corners
    for prefix in ('source', 'expected'):
        size = '1920x1080' if prefix == 'source' else '640x904'
        for variant in ('_variant', '_variant2'):
            name = f'{prefix}{variant}_{size}.png'
            src = a.root/'fullhd_tests'/name
            if sha(src) != inputs['fullhd_tests/'+name]['local_sha256']:
                raise RuntimeError('Changed fixture: '+name)
            extras['fixture/'+name] = src
    for name, src in extras.items():
        dst = a.output/name
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        manifest['files'][name] = sha(dst)
    # These values are backed by the raw upstream manifest included above.
    manifest['algorithm_provenance'] = provenance
    manifest['purpose'] = 'offline_integration_and_timing_research'
    manifest['board_replacement_allowed'] = False
    manifest['known_unmerged_board_baseline_fix_sha256'] = '540dd628d92dbd477e6f8cbd4ccf7d0ebffbd1ae067929dc10015a7ae1a7793f'
    manifest['realtime_video_qualified'] = False
    mp.write_text(json.dumps(manifest, indent=2)+'\n')
    print('INLINE_GEOMETRY_PACKAGE_VERIFIED hardware_accepted=false')


if __name__ == '__main__':
    main()
