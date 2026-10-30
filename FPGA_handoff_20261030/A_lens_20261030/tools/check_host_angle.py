"""Host angle/profile binding regression; serial is replaced by an import trap."""
from pathlib import Path
import datetime
import hashlib
import json
import os
import subprocess
import sys
from send_lens_angle import affine_for_angle, plan_lens_viewport, hardware_binding, encode_packet, encode_ack, DEFAULT_CANDIDATE

ROOT=Path(__file__).resolve().parents[1]
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()


def independent_crc(data):
    crc=65535
    for b in data:
        crc^=b<<8
        for _ in range(8):crc=((crc<<1)^0x1021)&65535 if crc&32768 else (crc<<1)&65535
    return crc


def main():
    out=ROOT/'verification'/('host_angle_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
    profile=ROOT/'calibration/r50_18mm_hdmi_trial.json'
    cases=[]
    for i,angle in enumerate([0,1,5,12,-12,45,90,180,270]):
        plan=plan_lens_viewport(affine_for_angle(angle,1,safe_crop=False),profile,False)
        q=plan['coefficients_q24'];packet=encode_packet(65530+i if i<6 else 0,q)
        assert len(packet)==38 and packet[:3]==b'\xa5\x5a\x01'
        assert independent_crc(packet[2:-2])==int.from_bytes(packet[-2:],'little')
        assert [int.from_bytes(packet[6+k*5:11+k*5],'little',signed=True) for k in range(6)]==q
        assert plan['viewport_report']['after']=={'float_outside_pixels':0,'fixed_outside_pixels':0}
        binding=hardware_binding(profile,DEFAULT_CANDIDATE,[1920,1080]);assert binding['compatible']
        if angle==0:assert q==[16668374,0,146376934,0,16668374,100663296]
        if angle in [1,5]:assert plan['memory_locality_minimum_zoom']==1.2 and plan['pre_viewport_zoom']>=1.2
        (out/f'case_{i}.json').write_text(json.dumps(plan,indent=2));(out/f'case_{i}.bin').write_bytes(packet)
        cases.append({'angle':angle,'all_output_centers_verified':2073600,'packet_bytes':len(packet),'binding_compatible':True})
    assert independent_crc(b'123456789')==0x29b1
    ack=encode_ack(0x1234);assert independent_crc(ack[2:-2])==int.from_bytes(ack[-2:],'little')
    trap=out/'import_trap';trap.mkdir();(trap/'serial.py').write_text('raise RuntimeError("SERIAL_IMPORT_FORBIDDEN_IN_OFFLINE_TEST")\n')
    env=os.environ.copy();env['PYTHONPATH']=str(trap)
    host=ROOT/'tools/send_lens_angle.py'
    def cli(name,args,ok,needle=None):
        p=subprocess.run([sys.executable,str(host),*map(str,args)],env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,creationflags=subprocess.CREATE_NO_WINDOW)
        (out/(name+'.log')).write_text(p.stdout,encoding='utf-8')
        assert (p.returncode==0)==ok,(name,p.stdout)
        assert 'SERIAL_IMPORT_FORBIDDEN' not in p.stdout,(name,p.stdout)
        if needle:assert needle in p.stdout
        return {'name':name,'returncode':p.returncode,'serial_imported':False,'log_sha256':sha(out/(name+'.log'))}
    checks=[cli('dry_run_with_port',['--dry-run','--port','COM_IMPORT_TRAP','--output',out/'dry.json'],True)]
    checks.append(cli('quantized_singular',['--zoom','1e100','--port','COM_IMPORT_TRAP'],False,'singular after Q24'))
    changed=json.loads(profile.read_text());changed['model']['fx']+=7
    changed['model']['K'][0][0]=changed['model']['fx'];changed['model']['output_camera_matrix_for_preview'][0][0]=changed['model']['fx']
    other=out/'mismatched_profile.json';other.write_text(json.dumps(changed))
    checks.append(cli('mismatch_before_serial',['--calibration',other,'--port','COM_IMPORT_TRAP'],False,'differs from the candidate RTL'))
    checks.append(cli('mismatch_dry_run',['--calibration',other,'--dry-run','--port','COM_IMPORT_TRAP','--output',out/'mismatch_dry.json'],True))
    assert json.loads((out/'mismatch_dry.json').read_text())['hardware_binding']['compatible'] is False
    for name,matrix,needle in [('singular',[[1,2,0],[2,4,0],[0,0,1]],'invertible'),('perspective',[[1,0,0],[0,1,0],[.01,0,1]],'Only affine')]:
        p=out/(name+'.json');p.write_text(json.dumps({'H':matrix}))
        checks.append(cli(name,['--base-matrix-json',p,'--port','COM_IMPORT_TRAP'],False,needle))
    manifest={'host_sha256':sha(host),'checker_sha256':sha(Path(__file__)),'calibration_sha256':sha(profile),
              'rtl_sha256':sha(DEFAULT_CANDIDATE/'sources/lens_affine_instance.v'),
              'viewport_reference_sha256':sha(Path('C:/D/FPGA/A_software_20261024/reference/B_lens_v2/python/brect/viewport.py'))}
    (out/'inputs.json').write_text(json.dumps(manifest,indent=2))
    result={'passed':True,'hardware_accessed':False,'serial_ports_opened':False,'cases':cases,'cli_checks':checks,
            'inputs_sha256':sha(out/'inputs.json'),'scope':__doc__}
    (out/'verification.json').write_text(json.dumps(result,indent=2))
    print(json.dumps({'directory':str(out),**result},indent=2))


if __name__=='__main__':main()
