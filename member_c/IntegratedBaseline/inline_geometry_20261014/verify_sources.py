"""Verify the pinned upstream snapshot and byte-identical generated B RTL."""
import argparse, hashlib, json
from pathlib import Path
HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(root):
    snapshot = HERE.parent/'a_black_sync_20261014'
    manifest = json.loads((snapshot/'upstream_manifest.json').read_text(encoding='utf-8-sig'))
    for name, record in manifest['files'].items():
        if sha(snapshot/'upstream'/name) != record['sha256']:
            raise RuntimeError('Upstream snapshot changed: '+name)
    bfiles = snapshot/'upstream/diagnostics/ddr_camera_black_20261014/b_algorithm/rtl'
    names = []
    for source in bfiles.glob('*.v'):
        target = root/('rtl/algo/marker_detector.v' if source.name == 'marker_detector.v' else 'vendor/b/rtl/'+source.name)
        if sha(source) != sha(target):
            raise RuntimeError('B algorithm changed: '+source.name)
        names.append(source.name)
    if len(names) != 9:
        raise RuntimeError('Expected nine original B modules')
    fixture = json.loads((root/'fullhd_tests/fixture.json').read_text())
    if len({tuple(r['H_q']) for r in fixture['frames']}) != 3:
        raise RuntimeError('Three distinct transforms required')
    words = (root/'fullhd_tests/source_corners96.hex').read_text().splitlines()
    expected = [''.join(f'{int(v):03x}' for point in row['points'] for v in point) for row in fixture['frames']]
    if words != expected or len(set(words)) != 3:
        raise RuntimeError('Geometry generation evidence mismatch')
    return dict(a_commit=manifest['commit'], b_commit=manifest['b_commit'],
                upstream_files_verified=len(manifest['files']), original_b_rtl_verified=sorted(names),
                distinct_geometry_generations=3, hardware_accepted=False)


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--root', type=Path, required=True)
    print(json.dumps(verify(p.parse_args().root), indent=2))
