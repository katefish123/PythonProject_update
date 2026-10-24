"""Offline binding for the frozen four-net fanout attribute experiment.

Requires cache_evidence.py and prepare_lookup_fanout.py beside this module.
No simulation, synthesis, process, port or hardware operation is performed.
"""
import json
from pathlib import Path, PureWindowsPath
import re

from cache_evidence import require, safe_file, sha, trace_coverage
from prepare_lookup_fanout import transform, restore

RUNS = ('old', 'new', 'old8', 'new8')
RTL = 'ddr_quad_tile_cache.v'
FROZEN_BENCH_SHA = {
    False: '89ccf4652b03524c001104acd06952d282a66ea271fc2e4cbb3db078214e73f1',
    True: '04b3dcff1c3805916c024419e5aabd88fbd2e027f58512e9e5c411a337456c52',
}


def read(p):
    return p.read_text(encoding='utf-8-sig')


def expected_files():
    files = {'run_micro.py', 'verification.json', 'generated/original.v',
             'generated/attributed.v'}
    for mode in RUNS:
        bench = 'tb_quad_tile.sv' if mode.endswith('8') else 'tb_quad_pipeline.sv'
        files |= {mode+'/'+n for n in (RTL, bench, 'commands.json', 'cycle_trace.txt',
                   'verification.json', 'step0.log', 'step1.log', 'step2.log', 'transcript')}
    require(len(files) == 40, 'Internal fanout inventory error')
    return files


def actual_files(root):
    require(root.is_dir(), 'Missing fanout evidence directory')
    require({p.name for p in root.iterdir() if p.is_dir()} == {'generated', *RUNS},
            'Unexpected fanout evidence directory')
    for mode in RUNS:
        require({p.name for p in (root/mode).iterdir() if p.is_dir()} <= {'work'},
                'Unbound fanout run directory: ' + mode)
    require(not any(p.is_dir() for p in (root/'generated').iterdir()),
            'Unbound fanout generated directory')
    return {p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()
            and not (len(p.relative_to(root).parts) >= 3 and
                     p.relative_to(root).parts[0] in RUNS and
                     p.relative_to(root).parts[1] == 'work')}


def check_files(root, files):
    for name, h in files.items():
        require(sha(safe_file(root, name)) == h, 'Fanout evidence drift: ' + name)
    require(actual_files(root) == set(files), 'Unbound/missing fanout evidence file')


def verify_fanout_evidence(root, oldsha, newsha, generatorsha):
    root = Path(root).resolve()
    manifest_path = safe_file(root, 'evidence_manifest.json')
    manifest = json.loads(read(manifest_path))
    files = manifest['files_sha256']
    require(set(files) == expected_files(), 'Expected exactly 40 frozen fanout files')
    require(manifest['physical_timing_qualified'] is False and manifest['hardware_accessed'] is False,
            'Fanout micro evidence overstates qualification')
    all_files = dict(files, **{'evidence_manifest.json': sha(manifest_path)})
    check_files(root, all_files)
    q = json.loads(read(root/'verification.json'))
    require(q['source_sha256'] == oldsha and q['generated_sha256'] == newsha and
            q['transform_sha256'] == generatorsha, 'Fanout expected hash mismatch')
    require(sha(Path(__file__).with_name('prepare_lookup_fanout.py')) == generatorsha,
            'Fanout generator changed')
    require(sha(Path(q['source'])) == oldsha and sha(Path(q['transform'])) == generatorsha,
            'Fanout external frozen source/generator drift')
    require(q['transform_restores_exact_text'] is True and q['traces_identical'] is True and
            q['physical_timing_qualified'] is False and q['hardware_accessed'] is False,
            'Missing/overstated fanout comparison claims')
    original, attributed = root/'generated/original.v', root/'generated/attributed.v'
    require(sha(original) == oldsha and sha(attributed) == newsha, 'Fanout generated RTL drift')
    require(transform(read(original)) == read(attributed) and
            restore(read(attributed)) == read(original), 'Fanout transform is not exact')
    require(set(q['runs']) == set(RUNS), 'Fanout requires four actual runs')
    for mode in RUNS:
        d = root/mode
        small = mode.endswith('8')
        bench = 'tb_quad_tile.sv' if small else 'tb_quad_pipeline.sv'
        r = q['runs'][mode]
        require(json.loads(read(d/'verification.json')) == r,
                'Fanout nested verification mismatch: ' + mode)
        require(json.loads(read(d/'commands.json')) == r['commands'],
                'Fanout actual argv record mismatch: ' + mode)
        for name, key in ((RTL, 'rtl_sha256'), (bench, 'bench_sha256'),
                          ('cycle_trace.txt', 'trace_sha256')):
            require(sha(d/name) == r[key], 'Fanout actual input mismatch: '+mode+'/'+name)
        require(r['rtl_sha256'] == (oldsha if mode.startswith('old') else newsha),
                'Fanout wrong old/new cache: ' + mode)
        require(r['bench_sha256'] == r['frozen_bench_sha256'] == FROZEN_BENCH_SHA[small]
                and sha(Path(r['frozen_bench'])) == FROZEN_BENCH_SHA[small],
                'Fanout frozen stimulus mismatch: ' + mode)
        trace_coverage(d/'cycle_trace.txt', 8 if small else 64)
        expected = [
            ['vlib.exe', 'work'],
            ['vlog.exe', '-sv'] + ([] if small else ['+define+PIPELINE_CHECKS']) + [RTL, bench],
            ['vsim.exe', '-c', '-sv_seed', '61837', '-voptargs=+acc', Path(bench).stem,
             '-do', 'run -all; quit -f'],
        ]
        require(len(r['commands']) == 3, 'Fanout missing tool command')
        logs = []
        cwd = None
        for i, c in enumerate(r['commands']):
            require(c['args'] == expected[i] and c['exit_code'] == 0,
                    'Fanout failed/changed command: ' + mode)
            require(PureWindowsPath(c['argv'][0]).name == expected[i][0] and
                    c['argv'][1:] == expected[i][1:], 'Fanout actual argv differs: ' + mode)
            cwd = c['cwd'] if cwd is None else cwd
            require(c['cwd'] == cwd and PureWindowsPath(cwd).name == mode,
                    'Fanout command working directory mismatch: ' + mode)
            p = d/f'step{i}.log'
            require(sha(p) == c['log_sha256'], 'Fanout command log drift: ' + mode)
            log = read(p)
            require(not re.search(r'\*\*\s+(Fatal|Error|Warning)\s*:|^\s*(ERROR|FATAL):',
                                  log, re.M | re.I), 'Fanout tool diagnostic: ' + mode)
            if i:
                require('Errors: 0, Warnings: 0' in log, 'Missing clean fanout summary: ' + mode)
            logs.append(log)
        for line in r['pass_lines']:
            require(line in logs[2], 'Missing fanout recorded result')
        for token in ('warm 64 quads cycles=72', 'PASS watchdog and common reset recovery',
                      'PASS invalid address and wrong response hard faults'):
            require(token in logs[2], 'Missing fanout coverage: ' + token)
        if small:
            require('413 packets 232 commands' in logs[2], 'Missing eight-line fanout workload')
        else:
            require('1029 packets 788 commands' in logs[2] and
                    'PASS shared reset flushes active partial fill and lookup pipeline' in logs[2],
                    'Missing full fanout workload/reset coverage')
            counts = re.search(r'old-frame/future-S=(\d+) fill-relookups=(\d+) simultaneous-S/L/M=(\d+) old-read\+invalidate=(\d+)', logs[2])
            require(counts is not None and all(int(x) > 0 for x in counts.groups()),
                    'Missing fanout retained-L/relookup coverage')
    for old, new in (('old', 'new'), ('old8', 'new8')):
        for name in ('cycle_trace.txt', 'tb_quad_tile.sv' if old.endswith('8') else 'tb_quad_pipeline.sv'):
            require((root/old/name).read_bytes() == (root/new/name).read_bytes(),
                    'Fanout old/new comparison differs: ' + name)
    return dict(directory=str(root), files_sha256=dict(sorted(all_files.items())),
                source_sha256=oldsha, generated_sha256=newsha, transform_sha256=generatorsha,
                scope='Frozen 64/8-line fixed-seed behavioral equivalence only; mapped fanout, physical timing and hardware not qualified')


def verify_fanout_archive(root, record):
    """Recheck bound bytes and paths; return safe relative copy filenames."""
    root = Path(root).resolve()
    files = record['files_sha256']
    require(isinstance(files, dict) and bool(files), 'Missing fanout archive record')
    # Validate paths before inventory so malicious keys never reach a copy step.
    check_files(root, files)
    require(set(files) == expected_files() | {'evidence_manifest.json'},
            'Fanout archive record has unexpected scope')
    manifest = json.loads(read(root/'evidence_manifest.json'))
    require(manifest['files_sha256'] == {k:v for k,v in files.items() if k != 'evidence_manifest.json'},
            'Fanout archived manifest differs from qualified record')
    return sorted(files)
