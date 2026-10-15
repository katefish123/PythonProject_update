"""Freeze the small board-fix dependencies with their bound source provenance."""
import hashlib
import json
import shutil
from pathlib import Path

HERE=Path(__file__).resolve().parent
ORIGIN=Path('D:/FPGA/output/c_capture_burst_20261014')
INITIAL=Path('C:/Users/Lenovo/Documents/ChatGPT/FPGA/initial_display_fix')
OUT=HERE/'board_snapshot'
names=['rtl/memory/ddr_capture_writer.v','rtl/video/rx_preview.v','rtl/video/status_overlay.v']
names+=['diagnostics/ddr_camera_hires_prefetch_20261012/results/video_correct_ddr_top.v']
names += ['fullhd_tests/'+name+'.sv' for name in ['tb_rx_preview','tb_preview_display','tb_reason','tb_selftest_status','tb_tag_status','tb_capture_batch_recovery','tb_capture_burst_protocol']]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest=ORIGIN/'reproduction_manifest.json';m=json.loads(manifest.read_text())
release=json.loads((ORIGIN/'release_burst/package_manifest.json').read_text())
assert sha(manifest)==release['source_manifest_sha256']
files={};origins={};selected={}
for name in names:
    src=ORIGIN/name;expected=m['files'][name]['local_sha256'];assert sha(src)==expected,name
    if name.startswith('fullhd_tests/'):
        candidate=INITIAL/src.name
        # Keep the exact source used by this development regression. Board
        # preparation may have added compatibility ports to its own copy.
        if candidate.read_bytes()!=src.read_bytes():
            origins[name]={'source':str(candidate),'board_bound_counterpart_sha256':expected,'same_as_board_bound_copy':False}
            src=candidate;expected=sha(src)
    files[name]=expected;selected[name]=src
OUT.mkdir(exist_ok=True)
for name in names:
    dst=OUT/name;dst.parent.mkdir(parents=True,exist_ok=True)
    if dst.exists():assert dst.read_bytes()==selected[name].read_bytes(),name
    else:shutil.copyfile(selected[name],dst)
(OUT/'manifest.json').write_text(json.dumps(dict(origin_root=str(ORIGIN),source_manifest_sha256=sha(manifest),
    board_release_sbit_sha256=release['files']['video_correct_ddr_top.sbit'],
    inherited_acceptance=False,test_source_distinctions=origins,files=files),indent=2)+'\n')
print('BOARD_DEPENDENCIES_FROZEN files='+str(len(files))+' inherited_acceptance=false')
