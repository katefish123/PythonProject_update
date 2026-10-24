"""Real frozen evidence and small offline corruption/relocation checks."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from fanout_evidence import verify_fanout_archive, verify_fanout_evidence
from cache_evidence import sha

ROOT = Path('D:/FPGA/output/lookup_fanout_micro_20261023')
OLD = '4681124d318ef4d4d082242d69217cae2f06ee156d39b07acf03ee021ae01a6c'
NEW = '309da877bc90b0ec02e7868fd93f916ae6fc2e7b75fd83af644775abf60b94ea'
GENERATOR = '93557c80360b37102e00b0b725c7737da7452c3f304d6d6de7d3adea6da5ac49'


def clone(root):
    manifest = json.loads((ROOT/'evidence_manifest.json').read_text())
    for name in [*manifest['files_sha256'], 'evidence_manifest.json']:
        p = root/name
        p.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT/name, p)


class FanoutEvidenceTests(unittest.TestCase):
    def test_real_frozen_evidence(self):
        record = verify_fanout_evidence(ROOT, OLD, NEW, GENERATOR)
        self.assertEqual(len(record['files_sha256']), 41)
        self.assertEqual(len(verify_fanout_archive(ROOT, record)), 41)

    def test_tamper_rejected(self):
        for name in ('new/tb_quad_pipeline.sv', 'new/step2.log', 'new/cycle_trace.txt',
                     'new/commands.json', 'new/verification.json', 'verification.json'):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as td:
                root = Path(td)
                clone(root)
                record = verify_fanout_evidence(root, OLD, NEW, GENERATOR)
                (root/name).write_text('tampered')
                with self.assertRaises(RuntimeError):
                    verify_fanout_evidence(root, OLD, NEW, GENERATOR)
                with self.assertRaises(RuntimeError):
                    verify_fanout_archive(root, record)

    def test_extra_input_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            clone(root)
            record = verify_fanout_evidence(root, OLD, NEW, GENERATOR)
            (root/'new/extra.v').write_text('unbound source')
            with self.assertRaises(RuntimeError):
                verify_fanout_evidence(root, OLD, NEW, GENERATOR)
            with self.assertRaises(RuntimeError):
                verify_fanout_archive(root, record)

    def test_escape_rejected(self):
        record = verify_fanout_evidence(ROOT, OLD, NEW, GENERATOR)
        for name in ('../outside', '/absolute', 'C:/absolute', '..\\outside', 'new/../../outside'):
            bad = copy.deepcopy(record)
            bad['files_sha256'][name] = '0'*64
            with self.subTest(name=name), self.assertRaises(RuntimeError):
                verify_fanout_archive(ROOT, bad)

    def test_relocation(self):
        record = verify_fanout_evidence(ROOT, OLD, NEW, GENERATOR)
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            clone(root)
            self.assertEqual(verify_fanout_archive(root, record), sorted(record['files_sha256']))

    def test_optimized_python_still_rejects(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            clone(root)
            (root/'new/step2.log').write_text('** Fatal: bad')
            code = ('from fanout_evidence import verify_fanout_evidence; '
                    f'verify_fanout_evidence({str(root)!r},{OLD!r},{NEW!r},{GENERATOR!r})')
            run = subprocess.run([sys.executable, '-B', '-O', '-c', code],
                                 cwd=Path(__file__).parent, capture_output=True, text=True)
            self.assertNotEqual(run.returncode, 0)
            self.assertIn('RuntimeError', run.stderr)

    def test_semantic_failures_rejected_even_after_manifest_rebound(self):
        for change in ('exit', 'warning', 'argv', 'bench', 'trace'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as td:
                root = Path(td)
                clone(root)
                proof = json.loads((root/'verification.json').read_text())
                record = proof['runs']['new']
                if change == 'exit':
                    record['commands'][1]['exit_code'] = 1
                elif change == 'warning':
                    p = root/'new/step2.log'
                    p.write_text(p.read_text()+'** Warning: poisoned\n')
                    record['commands'][2]['log_sha256'] = sha(p)
                elif change == 'argv':
                    record['commands'][1]['argv'] += ['extra.v']
                elif change == 'bench':
                    p = root/'new/tb_quad_pipeline.sv'
                    p.write_text(p.read_text()+'// changed stimulus\n')
                    record['bench_sha256'] = sha(p)
                else:
                    p = root/'new/cycle_trace.txt'
                    p.write_text(p.read_text()+'F 0 0 0\n')
                    record['trace_sha256'] = sha(p)
                (root/'new/verification.json').write_text(json.dumps(record))
                (root/'new/commands.json').write_text(json.dumps(record['commands']))
                (root/'verification.json').write_text(json.dumps(proof))
                p = root/'evidence_manifest.json'
                manifest = json.loads(p.read_text())
                manifest['files_sha256'] = {n:sha(root/n) for n in manifest['files_sha256']}
                p.write_text(json.dumps(manifest))
                with self.assertRaises(RuntimeError):
                    verify_fanout_evidence(root, OLD, NEW, GENERATOR)


if __name__ == '__main__':
    unittest.main()
