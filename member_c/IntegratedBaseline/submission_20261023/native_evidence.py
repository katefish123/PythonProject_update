"""Fail-closed offline binding of the three frozen native-payload contracts.

Only current clean runs are archived. Old exploratory runs and simulator work
databases are deliberately excluded. No simulator or hardware is accessed.
"""
import difflib
import hashlib
import json
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import shlex

RUNS = ('old_clean', 'new_clean', 'default_clean')
CORE = 'video_correct_ddr_continuous_core.v'
TOP = 'video_correct_ddr_top.v'
BENCH = 'tb_native_payload.sv'
RTL = tuple('''async_packet_fifo.v async_packet_fifo_monitored.v async_packet_stream.v
async_packet_stream_monitored.v bilinear_interp.v b_rectifier.v color_marker_detector.v
continuous_capture_geometry.v continuous_capture_rx.v continuous_capture_writer.v
continuous_source_path.v c_corner_rectifier.v c_frame_mode_controller.v
c_stream_burst_correction_path.v c_stream_correction_path.v ddr_arbiter3.v
ddr_arbiter3_fair.v ddr_arbiter3_turnaround.v ddr_quad_tile_cache.v
ddr_result_display_raw_corrected.v ddr_result_writer_burst64.v ddr_result_writer_stream.v
ddr_self_test.v ddr_word_engine_result_burst.v frame_processor_stream.v
frame_telemetry_overlay.v hdmi_vs_recover.v homography_solver.v lens_autocrop_instance.v
lens_distort_coord.v manager_raw.v marker_color_classifier.v marker_detector.v
perspective_coord.v perspective_core.v quad_geometry_guard.v quad_packet_bridge.v
reset_sync.v rx_preview_stream.v scaled_div_pipe.v signed_div_seq.v snapshot_cdc.v
unsigned_div_seq.v video_correct_ddr_continuous_core.v video_timing_vtc.v'''.split())
ROOT_FILES = {'verification.json', 'IMPLEMENTATION_REPORT.md', 'run_contract.py',
              'finalize_evidence.py', BENCH}
GENERATED_FILES = {'source_binding.json', CORE, TOP, 'tb_lens_board.sv',
                   CORE+'.diff', TOP+'.diff', 'tb_lens_board.sv.diff'}
PASS = ('# PASS native payload real core/engine BIST256 beats=16 capture8=16 '
        'result8=16 read_rsp=20 AWstalls=22 Wstalls=15 resets=2')
GUARD = 'BIST_ONLY_NATIVE_WDATA requires CAPTURE_BURST_BEATS=8'
OVERRIDES = ['-G/tb_native_payload/dut/CAPTURE_BURST_BEATS=1',
             '-G/tb_native_payload/dut/continuous_sources/writer/BURST_BEATS=8']


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return path.read_text(encoding='utf-8-sig')


def safe_file(root, name):
    require(isinstance(name, str) and bool(name) and '\\' not in name and ':' not in name,
            'Unsafe native evidence path: '+str(name))
    p, w = PurePosixPath(name), PureWindowsPath(name)
    require(not p.is_absolute() and not w.drive and
            all(part not in ('', '.', '..') for part in name.split('/')),
            'Unsafe native evidence path: '+name)
    target = root/name
    require(target.resolve().is_relative_to(root) and target.is_file(),
            'Missing/escaping native evidence file: '+name)
    return target


def inventory(root):
    names = set(ROOT_FILES) | {'generated/'+n for n in GENERATED_FILES}
    generated = root/'generated'
    require(generated.is_dir(), 'Missing generated native evidence')
    require({p.relative_to(generated).as_posix() for p in generated.rglob('*') if p.is_file()} == GENERATED_FILES,
            'Unexpected generated native evidence')
    for mode in RUNS:
        d = root/mode
        require(d.is_dir(), 'Missing native run: '+mode)
        allowed = set(RTL) | {BENCH}
        for p in d.rglob('*'):
            rel = p.relative_to(d)
            if p.is_file() and p.suffix.lower() in ('.v', '.sv', '.vp') and 'work' not in rel.parts:
                require(rel.as_posix() in allowed, 'Unbound native source: '+mode+'/'+rel.as_posix())
        names |= {mode+'/'+n for n in allowed | {'verification.json', 'step0.log', 'step1.log', 'step2.log'}}
    names.add('new_clean/invalid_guard.log')
    for name in names:
        safe_file(root, name)
    return names


def command_line(log, executable):
    lines = re.findall(r'^\s*(?:#\s*)?'+executable+r'\s+(.+)$', log, re.M)
    require(len(lines) == 1, 'Missing/ambiguous actual '+executable+' invocation')
    return [executable]+shlex.split(lines[0])


def clean_log(log):
    require(not re.search(r'\*\*\s+(?:Error|Fatal|Warning)\s*:|^\s*(?:ERROR|FATAL):', log, re.M | re.I),
            'Native diagnostic in clean run')
    summaries = re.findall(r'Errors:\s*(\d+),\s*Warnings:\s*(\d+)', log)
    require(summaries == [('0', '0')], 'Missing/nonclean native tool summary')


def verify_native_evidence(root, candidate_sources, payload_record):
    root, candidate = Path(root).resolve(), Path(candidate_sources).resolve()
    names = inventory(root)
    proof = json.loads(read(root/'verification.json'))
    binding = json.loads(read(root/'generated/source_binding.json'))
    require(set(payload_record['files']) == {CORE, TOP}, 'Unexpected native payload scope')
    generator = payload_record['generator_sha256']
    require(proof['generator_sha256'] == binding['generator_sha256'] == generator and
            sha(Path(__file__).with_name('prepare_native_payload.py')) == generator,
            'Native generator binding drift')
    require(proof['binding_sha256'] == sha(root/'generated/source_binding.json'), 'Native binding drift')
    require(all(proof.get(k) is True for k in ('reproducible', 'duplicate_and_unsafe_top_rejected',
                                              'top_and_fullbench_only_parameter_edit')),
            'Missing native transform evidence')
    require(binding['physical_timing_qualified'] is False and binding['hardware_acceptance'] is False,
            'Native local evidence overstates qualification')
    require(set(binding['files']) == {CORE, TOP, 'tb_lens_board.sv'}, 'Unexpected generated native file set')
    functions = {CORE:'transform_core', TOP:'transform_top', 'tb_lens_board.sv':'enable_bench'}
    for name, b in binding['files'].items():
        require(b['transform'] == functions[name], 'Unexpected native transformation record')
        target = root/'generated'/name
        require(sha(target) == b['generated_sha256'], 'Generated native input drift: '+name)
        if name in (CORE, TOP):
            expected = payload_record['files'][name]
            require(b['source_sha256'] == expected['old_sha256'] and
                    b['generated_sha256'] == expected['new_sha256'] == sha(candidate/name),
                    'Native candidate/generated binding drift: '+name)
        source = Path(b['source'])
        require(source.is_file() and sha(source) == b['source_sha256'], 'Frozen native ancestor input drift: '+name)
        # Verify the diff body against the actual before/after text. Header
        # paths remain historical metadata so a safe archive may relocate.
        expected_diff = ''.join(difflib.unified_diff(read(source).splitlines(keepends=True),
                                                   read(target).splitlines(keepends=True)))
        actual_lines = read(root/'generated'/(name+'.diff')).splitlines(keepends=True)
        require(len(actual_lines) > 2 and actual_lines[0].startswith('--- ') and actual_lines[1].startswith('+++ ') and
                ''.join(actual_lines[2:]) == ''.join(expected_diff.splitlines(keepends=True)[2:]),
                'Native review diff drift: '+name)
    require(set(proof['runs']) == set(RUNS), 'All three native runs must be bound')
    bench_hash = sha(root/BENCH)
    for mode in RUNS:
        d = root/mode
        v = json.loads(read(d/'verification.json'))
        require(v == proof['runs'][mode] and v['mode'] == mode, 'Native nested run drift: '+mode)
        require(set(v['production_sha256']) == set(RTL), 'Native production source set drift: '+mode)
        require(v['bench_sha256'] == bench_hash == sha(d/BENCH), 'Native compiled bench drift: '+mode)
        for name in RTL:
            expected = payload_record['files'][CORE]['old_sha256'] if name == CORE and mode == 'old_clean' else sha(candidate/name)
            require(sha(d/name) == v['production_sha256'][name] == expected,
                    'Native compiled production input drift: '+mode+'/'+name)
        expected_args = [
            ['vlib.exe', 'work'],
            ['vlog.exe', '-sv'] + (['+define+SPECIALIZED'] if mode == 'new_clean' else []) + list(RTL) + [BENCH],
            ['vsim.exe', '-c', '-voptargs=+acc', 'tb_native_payload', '-do', 'run -all;quit -f'],
        ]
        require(len(v['commands']) == 3, 'Unexpected native tool command count')
        for i, command in enumerate(v['commands']):
            require(command['args'] == expected_args[i] and command['exit_code'] == 0,
                    'Unbound/failed native tool command: '+mode)
            p = d/f'step{i}.log'
            require(sha(p) == command['log_sha256'], 'Native tool log drift: '+mode)
            log = read(p)
            if i:
                clean_log(log)
                require(command_line(log, 'vlog' if i == 1 else 'vsim') ==
                        [expected_args[i][0][:-4]]+expected_args[i][1:],
                        'Native actual tool invocation drift: '+mode)
            else:
                require(not re.search(r'\*\*\s+(?:Error|Fatal|Warning)\s*:', log, re.I), 'Native library diagnostic')
        log = read(d/'step2.log')
        require(v['pass_lines'] == [PASS] and log.splitlines().count(PASS) == 1,
                'Native workload/PASS counters differ: '+mode)
        require(len(re.findall(r'^# PASS ', log, re.M)) == 1, 'Unexpected native pass record')
    guard = proof['invalid_parameter']
    guard_args = ['vsim.exe', '-c', '-voptargs=+acc']+OVERRIDES+['tb_native_payload', '-do', 'run 1 ns;quit -f']
    require(guard['args'] == guard_args and guard['expected_fatal'] == GUARD and
            guard['expected_errors'] == 1 and guard['warnings'] == 0,
            'Native illegal-parameter command/expectation drift')
    require('guard' in guard['scope'].lower() and 'production RTL unmodified' in guard['scope'],
            'Illegal override must be identified as guard-only evidence')
    log_path = root/'new_clean/invalid_guard.log'
    require(sha(log_path) == guard['simulation_sha256'], 'Native guard log drift')
    log = read(log_path)
    require(re.findall(r'\*\*\s+Fatal:\s*(.*)', log, re.I) == [GUARD] and
            not re.search(r'\*\*\s+(?:Error|Warning)\s*:', log, re.I) and
            not re.search(r'^\s*(?:ERROR|FATAL|WARNING):', log, re.M | re.I) and
            re.findall(r'Errors:\s*(\d+),\s*Warnings:\s*(\d+)', log) == [('1', '0')] and
            'Time: 0 ps  Scope: tb_native_payload.dut ' in log,
            'Unexpected native guard failure/diagnostic')
    # ModelSim prints -G overrides after the -do argument, irrespective of
    # their original argv placement. No other reordering/options are allowed.
    actual = command_line(log, 'vsim')
    require(actual == ['vsim', '-c', '-voptargs=+acc', 'tb_native_payload', '-do', 'run 1 ns;quit -f']+OVERRIDES,
            'Native actual guard invocation drift')
    return dict(directory=str(root), files_sha256={n:sha(root/n) for n in sorted(names)},
                generator_sha256=generator,
                scope='Frozen real-core client contracts only; injected clients and guard-only illegal override; no full-chain, physical or hardware qualification')


def verify_native_archive(root, record):
    """Recheck the exact copy set without following historical external paths."""
    root = Path(root).resolve()
    files = record['files_sha256']
    require(isinstance(files, dict) and bool(files), 'Missing native copy manifest')
    for name, expected in files.items():
        require(sha(safe_file(root, name)) == expected, 'Native archive drift: '+name)
    require(inventory(root) == set(files), 'Unbound native archive input')
    return sorted(files)
