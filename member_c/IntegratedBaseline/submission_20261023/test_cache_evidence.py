"""Offline release evidence checks; never invokes a simulator or hardware."""
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from cache_evidence import verify_cache_archive, verify_cache_evidence


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def fixture(root):
    root.mkdir(exist_ok=True)
    generated = root/'generated'
    generated.mkdir()
    expected = [hashlib.sha256(x).hexdigest() for x in (b'old RTL', b'new RTL', b'transform')]
    proof = dict(source_sha256=expected[0], generated_sha256=expected[1],
                 transform_sha256=expected[2], transform_reproducible=True,
                 unexpected_and_already_transformed_inputs_rejected=True, runs={})
    for name in ('old', 'new', 'old8', 'new8'):
        d = root/name
        d.mkdir()
        small = name.endswith('8')
        bench = 'tb_quad_tile.sv' if small else 'tb_quad_pipeline.sv'
        (d/'ddr_quad_tile_cache.v').write_bytes(b'old RTL' if name.startswith('old') else b'new RTL')
        (d/bench).write_text('same bench')
        width = 8 if small else 64
        trace = f'0 1 0 0 0 0 0 0 0 0 3 {(1<<width)-1:x} {width-1:x}\n1 1 0 0 0 0 0 0 0 0 0 {(1<<width)-1:x} 0\n'
        (d/'cycle_trace.txt').write_text(trace)
        passes = ['# NEW warm 64 quads cycles=72', '# PASS watchdog and common reset recovery',
                  '# PASS invalid address and wrong response hard faults']
        if small:
            passes += ['# PASS quad tile RGB metadata/backpressure/eviction/generation/bank/edges 413 packets 232 commands']
        else:
            passes += ['# PASS registered lookup old-frame/future-S=1434 fill-relookups=197 simultaneous-S/L/M=640 old-read+invalidate=17',
                       '# PASS quad pipeline64 native dimensions RGB/metadata/protection/eviction/generation/bank/edges 1029 packets 788 commands',
                       '# PASS shared reset flushes active partial fill and lookup pipeline']
        logs = ['', '# Errors: 0, Warnings: 0\n', '\n'.join(passes)+'\n# Errors: 0, Warnings: 0\n']
        args = [['vlib.exe', 'work'], ['vlog.exe', '-sv'] +
                ([] if small else ['+define+PIPELINE_CHECKS']) + ['ddr_quad_tile_cache.v', bench],
                ['vsim.exe', '-c', '-sv_seed', '61837', '-voptargs=+acc', Path(bench).stem, '-do', 'run -all; quit -f']]
        commands = []
        for i, text in enumerate(logs):
            p = d/f'step{i}.log'
            p.write_text(text)
            commands.append(dict(args=args[i], exit_code=0, log_sha256=sha(p)))
        v = dict(rtl_sha256=sha(d/'ddr_quad_tile_cache.v'), bench_sha256=sha(d/bench),
                 trace_sha256=sha(d/'cycle_trace.txt'), commands=commands, pass_lines=passes)
        (d/'verification.json').write_text(json.dumps(v))
        proof['runs'][name] = dict(trace_sha256=v['trace_sha256'], trace_bytes=(d/'cycle_trace.txt').stat().st_size,
                                   live_cycles=2, replacement_wrap_after_final_fill=1,
                                   all_lines_valid_cycles=2, verification=v)
    (generated/'ddr_quad_tile_cache.v').write_bytes(b'new RTL')
    (generated/'rtl.diff').write_text('review diff')
    (generated/'source_binding.json').write_text(json.dumps(dict(source=str(root/'old/ddr_quad_tile_cache.v'),
        source_sha256=expected[0], generated=str(generated/'ddr_quad_tile_cache.v'),
        generated_sha256=expected[1], transform_sha256=expected[2],
        physical_timing_qualified=False, hardware_acceptance=False)))
    for n in ('IMPLEMENTATION_REPORT.md', 'run_regression.py'):
        (root/n).write_text('archived evidence')
    (root/'verification.json').write_text(json.dumps(proof))
    return expected


class CacheEvidenceTests(unittest.TestCase):
    def test_fixture_and_archive_success(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            record = verify_cache_evidence(root, *fixture(root))
            paths = verify_cache_archive(root, record)
            self.assertIn('generated/rtl.diff', record['files_sha256'])
            self.assertEqual(len(paths), len(record['files_sha256']))

    def test_tampered_inputs_and_records_rejected(self):
        for name in ('new/tb_quad_pipeline.sv', 'new/step1.log', 'new/cycle_trace.txt',
                     'new/verification.json', 'verification.json'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as td:
                root = Path(td)
                expected = fixture(root)
                record = verify_cache_evidence(root, *expected)
                (root/name).write_text('tampered')
                with self.assertRaises((RuntimeError, ValueError)):
                    verify_cache_evidence(root, *expected)
                with self.assertRaises(RuntimeError):
                    verify_cache_archive(root, record)

    def test_unbound_source_and_directory_rejected(self):
        for name in ('new/extra.v', 'new/nested/extra.sv'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as td:
                root = Path(td)
                expected = fixture(root)
                record = verify_cache_evidence(root, *expected)
                p = root/name
                p.parent.mkdir(exist_ok=True)
                p.write_text('unbound')
                with self.assertRaises(RuntimeError):
                    verify_cache_evidence(root, *expected)
                with self.assertRaises(RuntimeError):
                    verify_cache_archive(root, record)

    def test_archive_path_escape_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            record = verify_cache_evidence(root, *fixture(root))
            for name in ('../outside', '/absolute', 'C:/absolute', 'new/../../outside', '..\\outside'):
                bad = copy.deepcopy(record)
                bad['files_sha256'][name] = '0'*64
                with self.subTest(name=name), self.assertRaises(RuntimeError):
                    verify_cache_archive(root, bad)

    def test_optimized_python_keeps_checks(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            expected = fixture(root)
            (root/'new/step2.log').write_text('** Fatal: bad\n')
            code = ('from cache_evidence import verify_cache_evidence; '
                    f'verify_cache_evidence({str(root)!r}, *{expected!r})')
            run = subprocess.run([sys.executable, '-B', '-O', '-c', code],
                                 cwd=Path(__file__).parent, capture_output=True, text=True)
            self.assertNotEqual(run.returncode, 0)
            self.assertIn('RuntimeError', run.stderr)

    def test_rebound_bad_log_exit_and_missing_run_rejected(self):
        for change in ('diagnostic', 'exit', 'missing_run', 'compiler_args', 'coverage'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as td:
                root = Path(td)
                expected = fixture(root)
                proof = json.loads((root/'verification.json').read_text())
                v = proof['runs']['new']['verification']
                if change == 'diagnostic':
                    p = root/'new/step2.log'
                    p.write_text(p.read_text()+'** Warning: poisoned\n')
                    v['commands'][2]['log_sha256'] = sha(p)
                elif change == 'exit':
                    v['commands'][1]['exit_code'] = 1
                elif change == 'compiler_args':
                    v['commands'][1]['args'] += ['-f', 'unrecorded-inputs.txt']
                elif change == 'coverage':
                    proof['runs']['new']['replacement_wrap_after_final_fill'] = 0
                else:
                    del proof['runs']['old8']
                (root/'new/verification.json').write_text(json.dumps(v))
                (root/'verification.json').write_text(json.dumps(proof))
                with self.assertRaises(RuntimeError):
                    verify_cache_evidence(root, *expected)

    def test_archive_relocation(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)/'original'
            record = verify_cache_evidence(root, *fixture(root))
            moved = Path(td)/'moved'
            moved.mkdir()
            for name in verify_cache_archive(root, record):
                p = moved/name
                p.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(root/name, p)
            self.assertEqual(verify_cache_archive(moved, record), sorted(record['files_sha256']))


if __name__ == '__main__':
    unittest.main()
