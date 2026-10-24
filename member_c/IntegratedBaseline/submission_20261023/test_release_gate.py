import hashlib,json,subprocess,sys,tempfile,unittest
from pathlib import Path

HERE=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

class ReleaseGateTests(unittest.TestCase):
    def test_native_payload_delta_rejects_extra_logic_or_disabled_top(self):
        sys.path.insert(0,str(HERE))
        from qualify_lookahead import verify_native_payload_delta
        from prepare_native_payload import transform_core,transform_top
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/'candidate';parent=Path(tmp)/'parent'
            for d in [root,parent]:(d/'sources').mkdir(parents=True)
            (parent/'source_manifest.json').write_text('{}')
            core='video_correct_ddr_continuous_core.v';top='video_correct_ddr_top.v'
            (parent/'sources'/core).write_text('parameter CAPTURE_BURST_BEATS=8,\n assign cmd_wdata=selftest_passed?app_data:test_data;\n')
            (parent/'sources'/top).write_text('video_correct_ddr_continuous_core #(.CAPTURE_BURST_BEATS(8)) core();\nddr_word_engine_result_burst #(.CAPTURE_BURST_BEATS(8)) engine();\n')
            files={}
            for n,fn in [(core,transform_core),(top,transform_top)]:
                (root/'sources'/n).write_text(fn((parent/'sources'/n).read_text()))
                files[n]={'old_sha256':sha(parent/'sources'/n),'new_sha256':sha(root/'sources'/n)}
            record={'parent':str(parent),'parent_manifest_sha256':sha(parent/'source_manifest.json'),'files':files,
                'generator_sha256':sha(HERE/'prepare_native_payload.py')}
            verify_native_payload_delta(root,record)
            for n in [core,top]:
                target=root/'sources'/n;original=target.read_text()
                target.write_text(original+'assign injected=1;\n');files[n]['new_sha256']=sha(target)
                with self.assertRaises(RuntimeError):verify_native_payload_delta(root,record)
                target.write_text(original);files[n]['new_sha256']=sha(target)
            target=root/'sources'/top;target.write_text(target.read_text().replace('BIST_ONLY_NATIVE_WDATA(1)','BIST_ONLY_NATIVE_WDATA(0)'));files[top]['new_sha256']=sha(target)
            with self.assertRaises(RuntimeError):verify_native_payload_delta(root,record)

    def test_builder_rejects_changed_writer_credit_evidence(self):
        sys.path.insert(0,str(HERE.parent/'b_lens_board_20261022'))
        from build_lens_delivery import verify_writer_credit_evidence
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'verification.json').write_text('{}')
            record={'verification_sha256':sha(root/'verification.json'),'records':{}}
            names={'ddr_result_writer_burst64.v':'writer_sha256','tb_writer_burst.sv':'bench_sha256','step1.log':'compile_sha256','step2.log':'simulation_sha256'}
            for mode in ['original','registered']:
                (root/mode).mkdir();r={}
                for name,key in names.items():(root/mode/name).write_text('bound');r[key]=sha(root/mode/name)
                record['records'][mode]=r
            verify_writer_credit_evidence(root,record)
            for mode in record['records']:
                for name in names:
                    p=root/mode/name;p.write_text('changed')
                    with self.subTest(mode=mode,name=name):
                        with self.assertRaises(RuntimeError):verify_writer_credit_evidence(root,record)
                    p.write_text('bound')

    def test_credit_delta_rejects_extra_logic_and_parent_drift(self):
        sys.path.insert(0,str(HERE))
        from qualify_lookahead import verify_credit_delta
        from prepare_writer_credit import transform
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/'candidate';parent=Path(tmp)/'parent'
            for d in [root,parent]:(d/'sources').mkdir(parents=True)
            n='ddr_result_writer_burst64.v'
            (parent/'source_manifest.json').write_text('{}')
            old=parent/'sources'/n;new=root/'sources'/n
            old.write_text('assign cmd_valid=ui_live&&hold_valid&&!inflight&&!afull;\n')
            new.write_text(transform(old.read_text()))
            record={'parent':str(parent),'parent_manifest_sha256':sha(parent/'source_manifest.json'),
                    'old_sha256':sha(old),'new_sha256':sha(new),'generator_sha256':sha(HERE/'prepare_writer_credit.py')}
            verify_credit_delta(root,record)
            new.write_text(new.read_text()+'assign injected=1;\n');record['new_sha256']=sha(new)
            with self.assertRaises(RuntimeError):verify_credit_delta(root,record)
            new.write_text(transform(old.read_text()));record['new_sha256']=sha(new)
            (parent/'source_manifest.json').write_text('{"changed":true}')
            with self.assertRaises(RuntimeError):verify_credit_delta(root,record)

    def test_builder_refuses_changed_route_metadata(self):
        sys.path.insert(0,str(HERE.parent/'b_lens_board_20261022'))
        from build_lens_delivery import verify_route_metadata
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);(root/'route.tcl').write_text('pnr original\n');(root/'performance.pds').write_text('original\n')
            (root/'input_binding.json').write_text(json.dumps({'route_tcl_sha256':sha(root/'route.tcl')}))
            record={n:sha(root/n) for n in ['route.tcl','input_binding.json','performance.pds']}
            verify_route_metadata(root,record)
            for n in record:
                with self.subTest(file=n):
                    original=(root/n).read_bytes();(root/n).write_text('changed\n')
                    with self.assertRaises(RuntimeError):verify_route_metadata(root,record)
                    (root/n).write_bytes(original)

    def test_builder_refuses_changed_compile_bench_or_source(self):
        sys.path.insert(0,str(HERE.parent/'b_lens_board_20261022'))
        from build_lens_delivery import verify_display_evidence
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);src=root/'source_snapshot';src.mkdir()
            for p in [root/'simulation.log',root/'compile.log',src/'tb.sv',src/'dut.v']:p.write_text('original\n')
            record={'source_subdirectory':'source_snapshot','testbench_name':'tb.sv',
                'simulation_sha256':sha(root/'simulation.log'),'compile_sha256':sha(root/'compile.log'),
                'testbench_sha256':sha(src/'tb.sv'),'production_sha256':{'dut.v':sha(src/'dut.v')}}
            self.assertEqual(verify_display_evidence(root,record),src)
            for p in [root/'compile.log',src/'tb.sv',src/'dut.v']:
                with self.subTest(file=p.name):
                    p.write_text('changed\n')
                    with self.assertRaises(RuntimeError):verify_display_evidence(root,record)
                    p.write_text('original\n')
            (src/'unbound.v').write_text('extra\n')
            with self.assertRaises(RuntimeError):verify_display_evidence(root,record)

    def test_optimized_reproducer_rejects_changed_production(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)/'package';src=root/'validation/display_lookahead/late_mode_reset/source_snapshot'
            src.mkdir(parents=True);(root/'release').mkdir();(root/'sources').mkdir()
            bench=src/'tb.sv';bench.write_text('module tb_raw_corrected; endmodule\n')
            production=root/'sources/dummy.v';production.write_text('module dummy; endmodule\n')
            (src/'dummy.v').write_text('module changed; endmodule\n')
            record={'testbench_sha256':sha(bench),'production_sha256':{'dummy.v':sha(production)}}
            (root/'release/qualification.json').write_text(json.dumps({'display_regressions':{'late_mode_reset':record},'fixtures':{'fixtures_sha256':{}}}))
            out=Path(tmp)/'output'
            result=subprocess.run([sys.executable,'-O',str(HERE/'reproduce_display.py'),'--package',str(root),'--case','late_mode_reset','--output',str(out),'--prepare-only'],capture_output=True,text=True)
            self.assertNotEqual(result.returncode,0,result.stdout)
            self.assertFalse(out.exists())

if __name__=='__main__':unittest.main()
