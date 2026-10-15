"""Export the exact generated C integration files for review (not qualification)."""
import argparse, hashlib, json, shutil
from pathlib import Path
from verify_sources import verify
FILES = [
    'rtl/video/ddr_snapshot_capture.v',
    'rtl/top/video_correct_ddr_core.v',
    'rtl/algo/c_corner_rectifier.v',
    'rtl/algo/capture_geometry.v',
    'rtl/algo/geometry_frame_join.v',
    'diagnostics/ddr_camera_hires_20261011/results/frame_processor.v',
    'diagnostics/ddr_camera_hires_prefetch_20261012/results/ddr_result_display.v',
    'diagnostics/ddr_camera_hires_prefetch_20261012/results/video_correct_ddr_top.v',
    'fullhd_tests/tb_fullhd_pipeline.sv',
    'fullhd_tests/tb_capture_geometry.sv',
    'fullhd_tests/tb_geometry_join.sv',
]


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    provenance = verify(a.root)
    binding = json.loads((a.root/'reproduction_manifest.json').read_text())['files']
    hashes = {}
    for name in FILES:
        source = a.root/name
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        if digest != binding[name]['local_sha256']:
            raise RuntimeError('Changed source: '+name)
        hashes[name] = digest
    a.output.mkdir(parents=True, exist_ok=False)
    for name in FILES:
        target = a.output/name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(a.root/name, target)
    (a.output/'source_manifest.json').write_text(json.dumps(dict(
        evidence='generated_inputs_only_not_build_acceptance', provenance=provenance,
        files=hashes), indent=2)+'\n')
    print('C_SOURCE_EXPORT_VERIFIED files='+str(len(FILES)))


if __name__ == '__main__':
    main()
