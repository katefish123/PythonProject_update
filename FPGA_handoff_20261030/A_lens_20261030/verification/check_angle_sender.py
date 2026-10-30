"""Full-grid lens-safe command generation and CLI no-serial regression."""
from pathlib import Path
import datetime
import hashlib
import importlib.util
import json
import math
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
spec=importlib.util.spec_from_file_location('angle_host',ROOT/'tools/send_lens_angle.py')
host=importlib.util.module_from_spec(spec);spec.loader.exec_module(host)


def main():
    out=ROOT/'verification'/('host_angle_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
    profile=ROOT/'calibration/r50_18mm_hdmi_trial.json'
    cases=[]
    for index,(angle,zoom,no_crop) in enumerate([(0,1,False),(12,1,False),(-12,1.1,False),(90,1,False),(-17,1.2,True)]):
        d=host.affine_for_angle(angle,zoom,safe_crop=False)
        # Inverse angle must leave the destination center at the chosen source center.
        h=d['matrix'];cx,cy=959.5,539.5
        assert abs(h[0][0]*cx+h[0][1]*cy+h[0][2]-cx)<.0002
        assert abs(h[1][0]*cx+h[1][1]*cy+h[1][2]-cy)<.0002
        d=host.plan_lens_viewport(d,profile,no_crop)
        if not no_crop:
            assert d['viewport_report']['after']=={'float_outside_pixels':0,'fixed_outside_pixels':0}
            assert d['viewport_report']['verified_pixels']==2073600
        if angle==0:
            assert d['coefficients_q24']==[16668374,0,146376934,0,16668374,100663296]
        packet=host.encode_packet(100+index,d['coefficients_q24'])
        assert len(packet)==38 and packet[:3]==b'\xa5\x5a\x01'
        assert [int.from_bytes(packet[6+5*k:11+5*k],'little',signed=True) for k in range(6)]==d['coefficients_q24']
        (out/f'case_{index}.bin').write_bytes(packet);(out/f'case_{index}.json').write_text(json.dumps(d,indent=2))
        cases.append({'angle_deg':angle,'zoom':zoom,'no_autocrop':no_crop,'coefficients_q24':d['coefficients_q24'],
                      'mapping_pixels_checked':0 if no_crop else 2073600,'packet_sha256':sha(out/f'case_{index}.bin')})
    # Exercise the real CLI with --dry-run AND an explicit port. A sentinel makes
    # any accidental attempt to construct a Serial object an immediate failure.
    wrapper="""import runpy,sys,types
block=types.ModuleType('serial')
def forbidden(*args,**kwargs):raise RuntimeError('SERIAL_ACCESS_FORBIDDEN_IN_DRY_RUN')
block.Serial=forbidden
sys.modules['serial']=block
sys.argv=[sys.argv[1],*sys.argv[2:]]
runpy.run_path(sys.argv[0],run_name='__main__')
"""
    result=subprocess.run([sys.executable,'-c',wrapper,str(ROOT/'tools/send_lens_angle.py'),'--dry-run','--port','COM_NEVER_OPEN','--angle-deg','0','--output',str(out/'cli_zero.json')],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
    (out/'cli.log').write_bytes(result.stdout);assert result.returncode==0,(out/'cli.log')
    cli=json.loads((out/'cli_zero.json').read_text());assert not cli['serial_accessed']
    assert cli['coefficients_q24']==cases[0]['coefficients_q24']
    for invalid in [[1<<39]*6,[-(1<<39)-1]*6]:
        try:host.encode_packet(1,invalid)
        except ValueError:pass
        else:raise AssertionError('Invalid signed40 coefficient accepted')
    inputs={'tool':str(ROOT/'tools/send_lens_angle.py'),'tool_sha256':sha(ROOT/'tools/send_lens_angle.py'),
            'calibration':str(profile),'calibration_sha256':sha(profile),'checker_sha256':sha(Path(__file__)),
            'viewport_reference':cli['viewport_reference'],'viewport_reference_sha256':cli['viewport_reference_sha256']}
    (out/'inputs.json').write_text(json.dumps(inputs,indent=2))
    record={'passed':True,'hardware_accessed':False,'serial_ports_opened':False,'dry_run_with_port_sentinel_passed':True,
            'full_grid_cases':4,'mapping_pixels_checked':8294400,'cases':cases,'input_sha256':sha(out/'inputs.json'),
            'evidence_sha256':{p.name:sha(p) for p in out.iterdir() if p.is_file()}}
    (out/'verification.json').write_text(json.dumps(record,indent=2));print(json.dumps({'directory':str(out),'passed':True,'full_grid_cases':4,'mapping_pixels_checked':8294400,'hardware_accessed':False},indent=2))


if __name__=='__main__':main()
