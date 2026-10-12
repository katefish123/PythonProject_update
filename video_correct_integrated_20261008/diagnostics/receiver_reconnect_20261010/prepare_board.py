"""Prepare a separate board candidate from the immutable working preview archive."""
from pathlib import Path
import hashlib
import json
import zipfile

D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/'board_results'
O.mkdir(exist_ok=True)
base=R/'release/camera_live_bram_20261010'
qualification=json.loads((D/'results/simulation_qualification.json').read_text(encoding='utf-8-sig'))
assert qualification['baseline_failure_reproduced']
assert len(qualification['tests'])==4 and all(t['passed'] for t in qualification['tests'].values())
manifest=json.loads((base/'source_hashes.json').read_text(encoding='utf-8'))
sources=[]
copied_hashes={}
with zipfile.ZipFile(base/'source_snapshot.zip') as z:
    assert z.testzip() is None
    for original,digest in manifest.items():
        source_path=Path(original)
        data=z.read(source_path.relative_to(R).as_posix())
        assert hashlib.sha256(data).hexdigest()==digest,original
        target=O/source_path.name
        if source_path.name=='ms7200_ctl.v':
            data=(D/'results/ms7200_ctl_reconnect.v').read_bytes()
        target.write_bytes(data)
        copied_hashes[str(target)]=hashlib.sha256(data).hexdigest()
        if target.suffix=='.v':sources.append(target)
        elif target.suffix=='.fdc':fdc=target
flow=['set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676']
flow += [f'add_design {{{p.as_posix()}}}' for p in sources]
flow += [f'add_constraint -logic -fdc {{{fdc.as_posix()}}}',
         'compile -top_module camera_live_bram_top','synthesize -ads','dev_map','pnr','report_timing','gen_bit_stream']
(O/'build.tcl').write_text('\n'.join(flow)+'\n',encoding='utf-8')
(O/'source_hashes.json').write_text(json.dumps(copied_hashes,indent=2)+'\n',encoding='utf-8')
tcl=(R/'pds/program_camera_live_bram.tcl').read_text(encoding='utf-8')
tcl=tcl.replace('release camera_live_bram_20261010','release camera_live_bram_reconnect_20261010')
(R/'pds/program_camera_live_bram_reconnect.tcl').write_text(tcl,encoding='utf-8')
driver=(R/'scripts/program_camera_live_bram.ps1').read_text(encoding='utf-8')
driver=driver.replace("'release\\camera_live_bram_20261010'", "'release\\camera_live_bram_reconnect_20261010'")
driver=driver.replace("'pds\\program_camera_live_bram.tcl'", "'pds\\program_camera_live_bram_reconnect.tcl'")
driver=driver.replace('program_camera_live_bram_$stamp.log','program_camera_live_bram_reconnect_$stamp.log')
driver=driver.replace('camera_live_bram_program_$stamp.json','camera_live_bram_reconnect_program_$stamp.json')
(R/'scripts/program_camera_live_bram_reconnect.ps1').write_text(driver,encoding='utf-8')
print('Prepared isolated board candidate from archived preview; only RX reconnect condition changed.')
