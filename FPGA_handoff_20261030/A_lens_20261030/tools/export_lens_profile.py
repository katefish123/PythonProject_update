"""Stage a fresh candidate bound to one native1920x1080 calibration.

Writes new files only; never edits the active/frozen candidate or programs a board.
An exported candidate must be rebuilt and qualified before hardware acceptance.
"""
from pathlib import Path
import argparse,datetime,hashlib,json,re,shutil,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,'C:/D/FPGA/A_software_20261024/deps')
sys.path.insert(0,'C:/D/FPGA/A_software_20261024/reference/B_lens_v2/python')
from brect.calibration import load_calibration
from brect.viewport import plan_viewport
from send_lens_angle import hardware_binding
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()

def substitute(text,pattern,value):
    text,n=re.subn(pattern,lambda _:value,text,flags=re.MULTILINE)
    if n!=1:raise ValueError('Expected exactly one binding: '+pattern)
    return text

def stage(calibration,output,template):
    calibration=calibration.resolve();output=output.resolve();template=template.resolve()
    if output.exists():raise ValueError('Output exists; select a new candidate directory')
    if output.is_relative_to(template):raise ValueError('Output must be outside the template candidate')
    profile=load_calibration(calibration,(1920,1080));hw=profile.to_hardware()
    _,report=plan_viewport(profile,output_size=(1920,1080));q=report['H_q24']
    if q[6:]!=[0,0,1<<24]:raise ValueError('Default viewport must be affine')
    sources={p.name:p.read_text(encoding='utf-8') for p in (template/'sources').glob('*.v')
             if p.name in ['lens_affine_instance.v','lens_autocrop_instance.v','frame_processor_stream.v','lens_parameter_mailbox.v']}
    runtime=sources['lens_affine_instance.v'];legacy=sources['lens_autocrop_instance.v']
    for key,value in hw.items():
        runtime=substitute(runtime,r'\.'+key+r"\(32'sh[0-9a-fA-F]{8}\)",'.'+key+"(32'sh%08x)"%(value&0xffffffff))
        legacy=substitute(legacy,r'^`define SAFE_'+key+r" 32'sh[0-9a-fA-F]{8}", '`define SAFE_'+key+" 32'sh%08x"%(value&0xffffffff))
    for i,value in enumerate(q):
        name='H%d%d_Q24'%(i//3,i%3)
        legacy=substitute(legacy,r'^`define SAFE_'+name+r" 40'sh[0-9a-fA-F]{10}", '`define SAFE_'+name+" 40'sh%010x"%(value&((1<<40)-1)))
    sources['lens_affine_instance.v']=runtime;sources['lens_autocrop_instance.v']=legacy
    packed=sum((value&((1<<40)-1))<<(40*i) for i,value in enumerate(q[:6]))
    for name in ['frame_processor_stream.v','lens_parameter_mailbox.v']:
        sources[name]=substitute(sources[name],r'localparam\[239:0\]DEFAULT_AFFINE=\{[^;]+\};',
                                 "localparam[239:0]DEFAULT_AFFINE=240'h%060x;"%packed)
    packed_h=sum((value&((1<<40)-1))<<(40*i) for i,value in enumerate(q))
    sources['frame_processor_stream.v']=substitute(sources['frame_processor_stream.v'],
        r"assign math_debug_h=\{40'sh[^\r\n;]+\};assign pending", "assign math_debug_h=360'h%090x;assign pending"%packed_h)
    template_hashes={p.name:sha(p) for p in (template/'sources').iterdir() if p.is_file()}
    output.mkdir(parents=True);(output/'sources').mkdir();(output/'project').mkdir();(output/'calibration').mkdir();(output/'build').mkdir()
    for name in template_hashes:
        if name in sources:(output/'sources'/name).write_text(sources[name],encoding='utf-8')
        else:shutil.copyfile(template/'sources'/name,output/'sources'/name)
    shutil.copyfile(calibration,output/'calibration/profile.json')
    tcl=(template/'project/build_full.tcl').read_text()
    tcl=substitute(tcl,r'^set root \{[^}]+\}','set root {'+output.as_posix()+'}')
    (output/'project/build_full.tcl').write_text(tcl)
    actual={p.name:sha(p) for p in (output/'sources').iterdir() if p.is_file()}
    manifest=json.loads((template/'project/source_manifest.json').read_text())
    manifest.update(created=datetime.datetime.now().astimezone().isoformat(),baseline=str(template),
                    source_sha256=actual,calibration=str(output/'calibration/profile.json'),calibration_sha256=sha(calibration),
                    qualified=False,hardware_accessed=False,build_tcl_sha256=sha(output/'project/build_full.tcl'),
                    changed_sources={n:{'template':template_hashes[n],'current':actual[n]} for n in actual if template_hashes[n]!=actual[n]})
    (output/'project/source_manifest.json').write_text(json.dumps(manifest,indent=2))
    binding=hardware_binding(output/'calibration/profile.json',output,[1920,1080]);assert binding['compatible']
    binding.update(default_affine_q24=q[:6],viewport_report=report,calibration_sha256=sha(calibration),
                   source_sha256=actual,software_qualified=False,hardware_accepted=False,optical_acceptance_pending=True,
                   exporter_sha256=sha(Path(__file__)),template_source_sha256=template_hashes)
    (output/'project/lens_binding.json').write_text(json.dumps(binding,indent=2))
    assert template_hashes=={p.name:sha(p) for p in (template/'sources').iterdir() if p.is_file()}
    return binding

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--calibration',type=Path,required=True)
    ap.add_argument('--output',type=Path,required=True);ap.add_argument('--template',type=Path,default=ROOT/'candidate_host_angle_v2_product_stage')
    a=ap.parse_args();b=stage(a.calibration,a.output,a.template)
    print(json.dumps({'candidate':str(a.output.resolve()),'source_inputs':len(b['source_sha256']),'binding_compatible':b['compatible'],
                      'template_unchanged':True,'compiled':False,'hardware_accessed':False,'optical_acceptance_pending':True},indent=2))

if __name__=='__main__':main()
