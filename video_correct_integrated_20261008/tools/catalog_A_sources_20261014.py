"""Index the retained baseline's actual compiled source closure."""
from pathlib import Path
import hashlib
import json
import zipfile

root = Path('C:/D/FPGA/video_correct_integrated_20261008')
release = root / 'release/ddr_camera_black_20261014'
out = root / 'tmp/a_tasks_20261014'
qualification = json.loads((release / 'build_qualification.json').read_text(encoding='utf-8-sig'))
zip_path = release / 'source_snapshot.zip'
assert hashlib.sha256(zip_path.read_bytes()).hexdigest() == qualification['files']['source_snapshot.zip']
hashes = json.loads((release / 'source_hashes.json').read_text(encoding='utf-8-sig'))
with zipfile.ZipFile(zip_path) as archive:
    print('SNAPSHOT_ENTRIES', len(archive.namelist()))
    entries = []
    for name in archive.namelist():
        if name.endswith('/'):
            continue
        data = archive.read(name)
        entry = {'archive_path': name, 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
        matches = [p for p, digest in hashes.items() if digest == entry['sha256']]
        entry['source_paths'] = matches
        entries.append(entry)
        if '/ddr3_ip/' not in name:
            print(name, '->', ' / '.join(matches))
    (out / 'baseline_catalog.json').write_text(json.dumps(entries, ensure_ascii=False, indent=2), encoding='utf-8')
print('QUALIFIED_BASELINE', json.dumps({k: v for k, v in qualification.items() if k != 'files'}, ensure_ascii=False))
