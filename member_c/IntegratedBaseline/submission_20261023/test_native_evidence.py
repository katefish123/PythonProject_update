"""Exercise the gate against frozen real data, with adversarial archive edits."""
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from native_evidence import verify_native_evidence, verify_native_archive

REAL = Path('D:/FPGA/output/native_payload_20261023')
CANDIDATE = Path('D:/FPGA/output/b_lens_board_payload_20261023/sources')
PAYLOAD = json.loads((CANDIDATE.parent/'source_manifest.json').read_text())['native_payload']

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def clone(target):
    names = ['verification.json','IMPLEMENTATION_REPORT.md','run_contract.py','finalize_evidence.py','tb_native_payload.sv']
    names += [p.relative_to(REAL).as_posix() for p in (REAL/'generated').iterdir() if p.is_file()]
    for mode in ('old_clean','new_clean','default_clean'):
        names += [mode+'/'+n for n in ['verification.json','step0.log','step1.log','step2.log','tb_native_payload.sv']]
        names += [p.relative_to(REAL).as_posix() for p in (REAL/mode).glob('*.v')]
    names += ['new_clean/invalid_guard.log']
    for name in names:
        p=target/name;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(REAL/name,p)
    return target

def rebound(root, mode, fn):
    p=root/mode/'verification.json';v=json.loads(p.read_text());fn(v)
    p.write_text(json.dumps(v))
    proof=json.loads((root/'verification.json').read_text());proof['runs'][mode]=v
    (root/'verification.json').write_text(json.dumps(proof))

class NativeEvidenceTests(unittest.TestCase):
    def test_real_data_and_safe_relocation(self):
        record=verify_native_evidence(REAL,CANDIDATE,PAYLOAD)
        self.assertTrue(record.get('files_sha256'),'Bound native copy manifest required')
        paths=verify_native_archive(REAL,record)
        self.assertIn('new_clean/invalid_guard.log',paths)
        self.assertFalse(any('/work/' in n or n.startswith('new_final/') for n in paths))
        with tempfile.TemporaryDirectory() as td:
            root=clone(Path(td))
            self.assertEqual(paths,verify_native_archive(root,record))

    def test_tampered_actual_inputs_and_nested_records(self):
        for name in ('new_clean/ddr_word_engine_result_burst.v','old_clean/tb_native_payload.sv','new_clean/step2.log','generated/video_correct_ddr_top.v.diff','verification.json','new_clean/invalid_guard.log'):
            with self.subTest(name=name),tempfile.TemporaryDirectory() as td:
                root=clone(Path(td));record=verify_native_evidence(root,CANDIDATE,PAYLOAD)
                (root/name).write_text('tampered')
                with self.assertRaises((RuntimeError,ValueError)):
                    verify_native_evidence(root,CANDIDATE,PAYLOAD)
                with self.assertRaises(RuntimeError):verify_native_archive(root,record)

    def test_extra_source_in_current_run_rejected(self):
        for name in ('new_clean/extra.v','new_clean/nested/extra.sv'):
            with self.subTest(name=name),tempfile.TemporaryDirectory() as td:
                root=clone(Path(td));record=verify_native_evidence(root,CANDIDATE,PAYLOAD)
                p=root/name;p.parent.mkdir(exist_ok=True);p.write_text('extra source')
                with self.assertRaises(RuntimeError):verify_native_evidence(root,CANDIDATE,PAYLOAD)
                with self.assertRaises(RuntimeError):verify_native_archive(root,record)

    def test_rebound_command_options_macros_logs_and_missing_sources(self):
        for change in ('missing_macro','extra_macro','old_macro','optimization','extra_option','compiler_path','exit','diagnostic','missing_source','nested_drift','actual_macro','actual_opt','coverage'):
            with self.subTest(change=change),tempfile.TemporaryDirectory() as td:
                root=clone(Path(td));mode='old_clean' if change=='old_macro' else 'new_clean'
                def edit(v):
                    compile_args=v['commands'][1]['args']
                    if change=='missing_macro':compile_args.remove('+define+SPECIALIZED')
                    elif change=='extra_macro':compile_args.insert(2,'+define+OTHER')
                    elif change=='old_macro':compile_args.insert(2,'+define+SPECIALIZED')
                    elif change=='optimization':v['commands'][2]['args'].insert(1,'-O5')
                    elif change=='extra_option':compile_args.extend(['-f','hidden.txt'])
                    elif change=='compiler_path':compile_args[-1]='../tb_native_payload.sv'
                    elif change=='exit':v['commands'][2]['exit_code']=1
                    elif change=='diagnostic':
                        p=root/mode/'step2.log';p.write_text(p.read_text()+'\n** Warning: poisoned\n');v['commands'][2]['log_sha256']=sha(p)
                    elif change=='missing_source':del v['production_sha256']['ddr_self_test.v']
                    elif change=='nested_drift':v['mode']='unexpected'
                    elif change in ('actual_macro','actual_opt','coverage'):
                        index=1 if change=='actual_macro' else 2;p=root/mode/f'step{index}.log';text=p.read_text()
                        if change=='actual_macro':text=text.replace('"+define+SPECIALIZED" ','')
                        elif change=='actual_opt':text=text.replace('# vsim -c ','# vsim -O5 -c ')
                        else:
                            text=text.replace('AWstalls=22','AWstalls=0');v['pass_lines']=[v['pass_lines'][0].replace('AWstalls=22','AWstalls=0')]
                        p.write_text(text);v['commands'][index]['log_sha256']=sha(p)
                rebound(root,mode,edit)
                with self.assertRaises(RuntimeError):verify_native_evidence(root,CANDIDATE,PAYLOAD)

    def test_archive_path_escape(self):
        record=verify_native_evidence(REAL,CANDIDATE,PAYLOAD)
        for name in ('../outside','/absolute','C:/absolute','new_clean/../../outside','..\\outside','new_clean//step1.log','new_clean/./step1.log','new_clean/step1.log:ads'):
            bad=copy.deepcopy(record);bad['files_sha256'][name]='0'*64
            with self.subTest(name=name),self.assertRaises(RuntimeError):verify_native_archive(REAL,bad)

    def test_illegal_guard_rebound_log_and_override_rejected(self):
        for change in ('extra_fatal','warning','wrong_override','wrong_expected'):
            with self.subTest(change=change),tempfile.TemporaryDirectory() as td:
                root=clone(Path(td));p=root/'verification.json';proof=json.loads(p.read_text());r=proof['invalid_parameter']
                if change in ('extra_fatal','warning'):
                    log=root/'new_clean/invalid_guard.log';log.write_text(log.read_text()+('\n** Fatal: unrelated\n' if change=='extra_fatal' else '\n** Warning: unrelated\n'));r['simulation_sha256']=sha(log)
                elif change=='wrong_override':r['args'].insert(1,'-G/tb_native_payload/dut/OTHER=1')
                else:r['expected_errors']=0
                p.write_text(json.dumps(proof))
                with self.assertRaises(RuntimeError):verify_native_evidence(root,CANDIDATE,PAYLOAD)

    def test_optimized_python_still_rejects_tamper(self):
        with tempfile.TemporaryDirectory() as td:
            root=clone(Path(td));(root/'new_clean/step2.log').write_text('** Fatal: poisoned\n')
            code=('from native_evidence import verify_native_evidence; '
                  f'verify_native_evidence({str(root)!r},{str(CANDIDATE)!r},{PAYLOAD!r})')
            result=subprocess.run([sys.executable,'-B','-O','-c',code],cwd=Path(__file__).parent,capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn('RuntimeError',result.stderr)

if __name__=='__main__':unittest.main()
