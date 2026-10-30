"""Freeze this candidate's exact inputs and create an offline native build."""
from pathlib import Path
import datetime
import hashlib
import json
import re
import argparse

ROOT=Path(__file__).resolve().parents[1]
R=ROOT/'candidate_host_angle_v2_product_stage'
PARENT=Path('C:/D/FPGA/A_board_20261029/candidate_de_frame_guard_v2')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    global R
    ap=argparse.ArgumentParser();ap.add_argument('--candidate',type=Path,default=R);a=ap.parse_args();R=a.candidate.resolve()
    reference=R/'project/build_parent_reference.tcl'
    text=reference.read_text()
    text=text.replace(PARENT.as_posix(),R.as_posix())
    additions=['lens_affine_instance.v','lens_parameter_mailbox.v','lens_uart_control.v']
    text=text.replace('compile -top_module video_correct_ddr_top',
                      ''.join('add_design [file join $root sources '+name+']\n' for name in additions)+
                      'compile -top_module video_correct_ddr_top')
    paths=re.findall(r'(?:add_design|add_constraint) \[file join \$root sources ([^\]]+)\]',text)
    assert len(paths)==len(set(paths))
    actual={p.name:sha(p) for p in (R/'sources').iterdir() if p.is_file()}
    top=(R/'sources/video_correct_ddr_top.v').read_text()
    cache_lines=int(re.search(r'\.SOURCE_CACHE_LINES\((\d+)\)',top)[1])
    tile_size=64 if 'x[5:0]==63' in (R/'sources/frame_processor_stream.v').read_text() else 128
    assert set(paths)==set(actual),(set(paths)-set(actual),set(actual)-set(paths))
    old=(PARENT/'sources/board_ddr.fdc').read_bytes()
    expected=old.replace(b'create_clock -name processing_clock -period 13.468013',b'create_clock -name processing_clock -period 10.774410')
    assert (R/'sources/board_ddr.fdc').read_bytes().startswith(expected)
    base=json.loads((PARENT/'project/source_manifest.json').read_text())['source_sha256']
    changes={name:{'baseline':base.get(name),'current':actual[name]} for name in actual if base.get(name)!=actual[name]}
    build=R/'project/build_full.tcl';build.write_text(text)
    record={'scope':'1080p30 Brown k1/k2/p1/p2 with PC-controlled 2D affine angle; no automatic tracking or IMU.',
            'created':datetime.datetime.now().astimezone().isoformat(),
            'baseline':str(PARENT),'baseline_qualification_sha256':sha(PARENT/'candidate_qualification.json'),
            'source_sha256':actual,'source_prefetch_enable':0,'source_cache_lines':cache_lines,'tile_size':tile_size,'capture_burst_beats':16,
            'runtime_affine':True,'tiled_order':f'{tile_size}x{tile_size}, last band clipped; contiguous64-pixel writes','clock_mhz':{'processing':92.8125,'output':74.25,'input':148.5,'ui':125,'uart':27},
            'uart':{'rx_pad':'B24','tx_pad':'C24','voltage':3.3,'baud':115200},
            'changed_sources':changes,'source_input_count':len(paths),'build_tcl_sha256':sha(build),
            'hardware_accessed':False,'qualified':False}
    (R/'project/source_manifest.json').write_text(json.dumps(record,indent=2))
    print(json.dumps({'inputs':len(paths),'changed':list(changes),'manifest_sha256':sha(R/'project/source_manifest.json')},indent=2))


if __name__=='__main__':main()
