"""Fail-closed, offline binding of the frozen cache-decision comparison.

No simulator, tool process, port or hardware is accessed. The archive verifier
returns relative POSIX filenames; callers copy only those files beneath root.
Coverage concerns this fixed stimulus and traces, not formal or physical proof.
"""
import hashlib
import json
from pathlib import Path, PurePosixPath, PureWindowsPath
import re

RUNS = ('old', 'new', 'old8', 'new8')
RTL = 'ddr_quad_tile_cache.v'
SOURCE_EXTENSIONS = {'.v', '.sv', '.vp'}


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return path.read_text(encoding='utf-8-sig')


def safe_file(root, name):
    require(isinstance(name, str) and bool(name) and '\\' not in name,
            'Unsafe cache evidence path: ' + str(name))
    posix, windows = PurePosixPath(name), PureWindowsPath(name)
    require(not posix.is_absolute() and not windows.drive and
            all(p not in ('..', '.') for p in name.split('/')),
            'Unsafe cache evidence path: ' + name)
    path = root/name
    require(path.resolve().is_relative_to(root) and path.is_file(),
            'Missing/escaping cache evidence file: ' + name)
    return path


def inventory(root):
    """Bind root documents, generated files and actual run inputs/logs.

    Simulator work databases are deliberately excluded. Extra HDL anywhere
    outside those databases is rejected, including hidden nested input trees.
    """
    files = {p.relative_to(root).as_posix() for p in root.iterdir() if p.is_file()}
    require({'verification.json', 'IMPLEMENTATION_REPORT.md', 'run_regression.py'} <= files,
            'Missing cache root evidence')
    generated = {'generated/' + n for n in (RTL, 'rtl.diff', 'source_binding.json')}
    require((root/'generated').is_dir(), 'Missing generated cache evidence')
    actual_generated = {p.relative_to(root).as_posix() for p in (root/'generated').rglob('*') if p.is_file()}
    require(actual_generated == generated, 'Unexpected generated cache files')
    files |= generated
    for mode in RUNS:
        d = root/mode
        require(d.is_dir(), 'Missing cache run ' + mode)
        bench = 'tb_quad_tile.sv' if mode.endswith('8') else 'tb_quad_pipeline.sv'
        expected = {RTL, bench, 'cycle_trace.txt', 'verification.json',
                    'step0.log', 'step1.log', 'step2.log'}
        actual = {p.name for p in d.iterdir() if p.is_file()}
        require(expected <= actual, 'Missing cache run input/log ' + mode)
        files |= {mode+'/'+n for n in actual}
    # Root bench snapshots are useful archives; only these known root HDL
    # names are permitted, and they must match the actual compiled benches.
    allowed_hdl = {f'{m}/{RTL}' for m in RUNS} | {f'{m}/' +
        ('tb_quad_tile.sv' if m.endswith('8') else 'tb_quad_pipeline.sv') for m in RUNS}
    allowed_hdl |= {'generated/'+RTL, 'tb_quad_tile.sv', 'tb_quad_pipeline.sv'}
    for p in root.rglob('*'):
        rel = p.relative_to(root)
        if p.is_file() and p.suffix.lower() in SOURCE_EXTENSIONS and 'work' not in rel.parts:
            require(rel.as_posix() in allowed_hdl, 'Unbound cache RTL/bench: ' + rel.as_posix())
    for name in files:
        safe_file(root, name)
    return files


def trace_coverage(path, lines):
    rows = []
    for line in read(path).splitlines():
        words = line.split()
        require(bool(words), 'Empty cache trace line')
        if words[0] not in ('F', 'R'):
            require(len(words) == 13, 'Malformed cache cycle trace')
            if words[1] == '1':
                rows.append(words)
    require(bool(rows), 'Empty live cache trace')
    wraps = sum(int(a[-1], 16) == lines-1 and int(b[-1], 16) == 0
                and a[-3] == '3' and b[-3] == '0' for a, b in zip(rows, rows[1:]))
    full = sum(int(row[-2], 16) == (1 << lines)-1 for row in rows)
    require(wraps > 0 and full > 0, 'Missing cache replacement wrap/saturation coverage')
    return dict(trace_sha256=sha(path), trace_bytes=path.stat().st_size,
                live_cycles=len(rows), replacement_wrap_after_final_fill=wraps,
                all_lines_valid_cycles=full)


def verify_cache_evidence(root, expected_old_sha, expected_new_sha, expected_transform_sha):
    root = Path(root).resolve()
    names = inventory(root)
    proof = json.loads(read(root/'verification.json'))
    require(set(proof['runs']) == set(RUNS), 'All four cache runs must be recorded')
    hashes = dict(source_sha256=expected_old_sha, generated_sha256=expected_new_sha,
                  transform_sha256=expected_transform_sha)
    for key, expected in hashes.items():
        require(proof[key] == expected, 'Cache expected hash mismatch: ' + key)
    require(proof['transform_reproducible'] is True and
            proof['unexpected_and_already_transformed_inputs_rejected'] is True,
            'Missing cache transform checks')
    binding = json.loads(read(root/'generated/source_binding.json'))
    for key, expected in hashes.items():
        require(binding[key] == expected, 'Cache generated binding mismatch: ' + key)
    require(binding['physical_timing_qualified'] is False and binding['hardware_acceptance'] is False,
            'Cache local evidence overstates qualification')
    require(sha(Path(binding['source'])) == expected_old_sha,
            'Cache frozen source drift')
    require(Path(binding['generated']).resolve() == root/'generated'/RTL and
            sha(root/'generated'/RTL) == expected_new_sha, 'Cache generated RTL drift')
    for mode in RUNS:
        d = root/mode
        small = mode.endswith('8')
        bench = 'tb_quad_tile.sv' if small else 'tb_quad_pipeline.sv'
        record = proof['runs'][mode]
        v = json.loads(read(d/'verification.json'))
        require(v == record['verification'], 'Cache nested run record drift: ' + mode)
        for name, key in ((RTL, 'rtl_sha256'), (bench, 'bench_sha256'),
                          ('cycle_trace.txt', 'trace_sha256')):
            require(sha(d/name) == v[key], 'Cache actual input drift: ' + mode+'/'+name)
        require(v['rtl_sha256'] == (expected_old_sha if mode.startswith('old') else expected_new_sha),
                'Cache run RTL differs from expected: ' + mode)
        coverage = trace_coverage(d/'cycle_trace.txt', 8 if small else 64)
        for key, value in coverage.items():
            require(record[key] == value, 'Cache coverage record mismatch: ' + mode+'/'+key)
        commands = v['commands']
        require(len(commands) == 3, 'Missing cache tool command')
        expected_args = [
            ['vlib.exe', 'work'],
            ['vlog.exe', '-sv'] + ([] if small else ['+define+PIPELINE_CHECKS']) + [RTL, bench],
            ['vsim.exe', '-c', '-sv_seed', '61837', '-voptargs=+acc', Path(bench).stem,
             '-do', 'run -all; quit -f'],
        ]
        logs = []
        for i, executable in enumerate(('vlib.exe', 'vlog.exe', 'vsim.exe')):
            c = commands[i]
            require(c['exit_code'] == 0 and c['args'][0] == executable,
                    'Cache tool command failed/mismatched: ' + mode)
            require(c['args'] == expected_args[i], 'Unbound cache tool arguments: ' + mode)
            p = d/f'step{i}.log'
            require(sha(p) == c['log_sha256'], 'Cache command log drift: ' + mode)
            log = read(p)
            require(not re.search(r'\*\*\s+(?:Fatal|Error|Warning)\s*:|^\s*(?:ERROR|FATAL):', log, re.M | re.I),
                    'Cache tool diagnostic: ' + mode)
            if i:
                require('Errors: 0, Warnings: 0' in log, 'Missing clean cache tool summary: ' + mode)
            logs.append(log)
        require(RTL in commands[1]['args'] and bench in commands[1]['args'],
                'Cache compiler did not consume recorded RTL/bench')
        supplied_hdl = {s for s in commands[1]['args'][1:] if Path(s).suffix.lower() in SOURCE_EXTENSIONS}
        require(supplied_hdl == {RTL, bench}, 'Unbound cache compiler input')
        require('-sv_seed' in commands[2]['args'] and
                commands[2]['args'][commands[2]['args'].index('-sv_seed')+1] == '61837' and
                Path(bench).stem in commands[2]['args'], 'Cache simulation stimulus changed')
        for line in v['pass_lines']:
            require(line in logs[2], 'Missing recorded cache pass line')
        for token in ('warm 64 quads cycles=72', 'PASS watchdog and common reset recovery',
                      'PASS invalid address and wrong response hard faults'):
            require(token in logs[2], 'Missing required cache result: ' + token)
        if small:
            require('413 packets 232 commands' in logs[2], 'Missing eight-line cache workload')
        else:
            require('1029 packets 788 commands' in logs[2] and
                    'PASS shared reset flushes active partial fill and lookup pipeline' in logs[2],
                    'Missing production cache workload/reset coverage')
            counts = re.search(r'old-frame/future-S=(\d+) fill-relookups=(\d+) simultaneous-S/L/M=(\d+) old-read\+invalidate=(\d+)', logs[2])
            require(counts is not None and all(int(x) > 0 for x in counts.groups()),
                    'Missing retained-L/future-S/relookup coverage')
    for old, new in (('old', 'new'), ('old8', 'new8')):
        bench = 'tb_quad_tile.sv' if old.endswith('8') else 'tb_quad_pipeline.sv'
        for name in (bench, 'cycle_trace.txt'):
            require((root/old/name).read_bytes() == (root/new/name).read_bytes(),
                    'Cache comparison differs: ' + name)
        if (root/bench).is_file():
            require(sha(root/bench) == sha(root/new/bench), 'Cache root bench differs from compiled input')
    return dict(directory=str(root), files_sha256={n:sha(root/n) for n in sorted(names)},
                source_sha256=expected_old_sha, generated_sha256=expected_new_sha,
                transform_sha256=expected_transform_sha,
                scope='Fixed-seed 64/8-line cycle equivalence, wrap/saturation and retained-L/relookup; not formal, physical timing or hardware qualification')


def verify_cache_archive(root, record):
    """Recheck before copying; return the safe relative file copy list."""
    root = Path(root).resolve()
    files = record['files_sha256']
    require(isinstance(files, dict) and bool(files), 'Missing cache archive manifest')
    for name, expected in files.items():
        require(sha(safe_file(root, name)) == expected, 'Cache archive drift: ' + name)
    require(inventory(root) == set(files), 'Unbound cache archive file/source')
    return sorted(files)
