"""Bind simulation evidence to actual generated and authored RTL, without accepting hardware."""
from pathlib import Path
import argparse,hashlib,json,re,shutil
HERE=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read_hashes(path):
    text=Path(path).read_text(encoding='utf-8-sig')
    records={}
    for block in re.split(r'\r?\n\s*\r?\n',text):
        h=re.search(r'Hash\s*:\s*([a-fA-F0-9]{64})',block)
        p=re.search(r'Path\s*:\s*(.*)',block,re.S)
        if h and p:
            name=''.join(x.strip() for x in p[1].splitlines())
            records[name]=h[1].lower()
    assert records, path
    for name,digest in records.items():assert sha(name)==digest, 'stale evidence: '+name
    return records
def main(root,evidence):
    manifest=json.loads((root/'stream_sources.json').read_text())
    for name,digest in manifest['files'].items():assert sha(root/name)==digest,name
    # Each currently authored module must equal the generated PDS input.
    authored=[]
    for folder in ('processor','bridge','cache','writer','integration','preview'):
        for p in (HERE/folder).glob('*.v'):
            q=root/'rtl/stream'/p.name;assert p.read_bytes()==q.read_bytes(),p
            authored.append(p)
    assert (HERE/'engine/ddr_word_engine.v').read_bytes()==(root/'diagnostics/ddr_camera_hires_prefetch_20261012/results/ddr_word_engine.v').read_bytes()
    # B remains a byte-for-byte dependency, including its original math.
    baseline=Path('D:/FPGA/output/c_black_burst_merge_v3_20261015/vendor/b')
    bfiles=[p for p in baseline.rglob('*') if p.is_file()]
    for p in bfiles:assert p.read_bytes()==(root/'vendor/b'/p.relative_to(baseline)).read_bytes(),p
    cases={
      'native_full_bilinear':('D:/FPGA/output/c_stream_native_integration_20261015_v2_full_solver_bilinear','PASS stream native integration complete publications=3'),
      'system_full_eager':('D:/FPGA/output/c_stream_system_20261015_v2_fullhd_eager_bound','VERIFIED_PASS_BIT=1'),
      'cache64':('D:/FPGA/output/c_quad_tile_unit_20261015_v2_orderedkeys','PASS invalid address and wrong response hard faults'),
      'bridge':('D:/FPGA/output/c_quad_bridge_unit_20261015_v2_pipeline','PASS quad bridge'),
      'preview_raster':('D:/FPGA/output/c_preview_row_20261015_row_verified','PASS preview registered row raster'),
    }
    results={};evidence.mkdir(parents=True,exist_ok=True)
    for name,(folder,marker) in cases.items():
        folder=Path(folder);log=folder/('console.log' if name.startswith('system') else 'simulation.log')
        text=log.read_text(errors='strict');assert marker in text,log
        assert not re.search(r'\*\* (?:Fatal|Error|Warning):',text),log
        assert 'Errors: 0, Warnings: 0' in text,log
        hashes=read_hashes(folder/'source_hashes.txt')
        after=folder/'source_hashes_after.txt'
        if after.exists():assert hashes==read_hashes(after),after
        if name=='native_full_bilinear':assert len(re.findall('PASS native path publication=',text))==3
        if name=='system_full_eager':assert 'corrected_pixels=2488320 display_pixels=2488320' in text
        target=evidence/name;target.mkdir(exist_ok=True)
        for n in ('simulation.log','console.log','compile.log','source_hashes.txt','source_hashes_after.txt'):
            if (folder/n).exists():shutil.copyfile(folder/n,target/n)
        results[name]={'passed':True,'log_sha256':sha(log),'source_files':len(hashes),'marker':marker}
    # Freeze every physical implementation input as well as the added modules.
    build=root/'diagnostics/ddr_camera_hires_prefetch_20261012/results/build.tcl'
    inputs=re.findall(r'add_(?:design|constraint)[^\n]*\{([^}]+)\}',build.read_text())
    inputs.append(str(build));inputs.append(str(root/'stream_sources.json'))
    binding={str(Path(p)):sha(p) for p in inputs}
    report={'status':'simulation_passed','hardware_accepted':False,'board_replacement_allowed':False,
            'effective_pixels':[765,1080],'storage_pixels':[768,1080],'source_pixels':[1920,1080],
            'b_files_unchanged':len(bfiles),'authored_generated_modules_equal':len(authored),
            'tests':results,'implementation_inputs':binding,
            'limitations':['Timing qualification required separately','No board programming or camera optical-sharpness acceptance','Distinct corrected camera refresh remains below60fps']}
    (evidence/'qualification.json').write_text(json.dumps(report,indent=2)+'\n')
    print('SIMULATION_BINDING_PASS cases='+str(len(results))+' implementation_inputs='+str(len(binding)))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--evidence',type=Path,default=HERE/'evidence/v2');a=p.parse_args();main(a.root.resolve(),a.evidence.resolve())
