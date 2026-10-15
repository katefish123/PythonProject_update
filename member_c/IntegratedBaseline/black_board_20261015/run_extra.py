"""Run additional fault/preview checks against a pinned candidate, unmodified."""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
import numpy as np
from merge_board import add_ports,finalize_ports,CAND

HERE=Path(__file__).resolve().parent
BOARD_TESTS=HERE/'board_snapshot/fullhd_tests'
CASES={
 'tb_rx_preview':'PREVIEW_COMPLETE_BAD_FRAME_RECOVERY_PASS',
 'tb_preview_display':'PREVIEW_DISPLAY_ALIGNMENT_PASS',
 'tb_reason':'MARKER_REJECTION_REASON_PASS',
 'tb_selftest_status':'DDR_SELFTEST_STATUS_PASS',
 'tb_tag_status':'PIXEL_ORDER_STATUS_PASS',
 'tb_capture_batch_recovery':'CAPTURE_BATCH_PARTIAL_RESET_RECOVERY_PASS',
 'tb_capture_burst_protocol':'CAPTURE_BURST_PROTOCOL_FAULT_RESET_PASS',
 'tb_core_recovery':'CORE_RECOVERY_PASS',
 'tb_geometry_reset':'GEOMETRY_RESET_PASS',
}


def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()


def fixtures(root,out):
    sys.path.insert(0,str(root/'fullhd_tests/reference'))
    from brect.fixed import solve_fixed,map_fixed,sample_fixed
    folder=out/'recovery';folder.mkdir()
    for kind in range(5):
        yy,xx=np.mgrid[:48,:64]
        image=np.stack([80+(xx+kind*9)%100,80+(yy+kind*11)%100,80+(xx+yy+kind*7)%100],axis=-1).astype(np.uint8)
        points=[(8,6),(55,6),(55,41),(8,41)] if kind!=4 else [(10,8),(53,8),(53,39),(10,39)]
        if kind==3:points=[(31,23),(32,23),(32,24),(31,24)]
        for n,(x,y) in enumerate(points):
            if kind==2 and n==3:continue
            radius=0 if kind==3 else 2
            image[y-radius:y+radius+1,x-radius:x+radius+1]=0
        packed=(image[:,:,0].astype(np.uint32)<<16)|(image[:,:,1].astype(np.uint32)<<8)|image[:,:,2]
        np.savetxt(folder/f'source{kind}.hex',packed.reshape(-1),fmt='%06x')
        if kind in (0,4):
            h=solve_fixed(points,32,24,64,48)
            expected=[]
            for y in range(24):
                for x in range(32):
                    sx,sy,inside=map_fixed(h,x,y);assert inside
                    r,g,b=map(int,sample_fixed(image,sx,sy,'bilinear'));expected.append((r<<16)|(g<<8)|b)
            np.savetxt(folder/f'expected{kind}.hex',expected,fmt='%06x')


def main():
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--only',choices=list(CASES));p.add_argument('--verify-held-display',action='store_true');a=p.parse_args()
    cases={a.only:CASES[a.only]} if a.only else CASES
    root,out=a.root.resolve(),a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    mp=root/'reproduction_manifest.json';m=json.loads(mp.read_text());binding=digest(mp)
    for name,item in m['files'].items():assert digest(root/name)==item['local_sha256'],name
    fixtures(root,out)
    template=(root/CAND/'tb_scheduler.do').read_text()
    sources={}
    for name in cases:
        src=HERE/(name+'.sv') if name in ('tb_core_recovery','tb_geometry_reset') else BOARD_TESTS/(name+'.sv')
        s=src.read_text().replace('@OUT@',out.as_posix())
        if name=='tb_core_recovery' and a.verify_held_display:
            s=s.replace(' reg active_d=0,', ''' reg[11:0]hx1=0,hx2=0,vy1=0,vy2=0;integer display0_pixels=0,display4_pixels=0;
 always @(posedge pix)begin hx1<=dut.display_reader.hc;hx2<=hx1;vy1<=dut.display_reader.vc;vy2<=vy1;end
 always @(negedge pix)if(rst&&iv)begin
  if(good<2&&(dut.display_reader.display_gen!=1||dut.display_reader.display_bank!=1))$fatal(1,"old complete display bank changed during rejection");
  if(de&&hx2>=20&&hx2<52&&vy2>=14&&vy2<38)begin
   if(rgb!==expected(dut.display_reader.display_gen==1?0:1,(vy2-14)*32+hx2-20))$fatal(1,"held/recovered displayed pixel mismatch x=%d y=%d",hx2,vy2);
   if(dut.display_reader.display_gen==1)display0_pixels=display0_pixels+1;else display4_pixels=display4_pixels+1;
  end
 end
 reg active_d=0,''')
            s=s.replace('  test_passed=1;', '''  wait(display4_pixels>=OP);
  if(display0_pixels<OP)$fatal(1,"old displayed frame insufficiently checked");
  $display("RECOVERY_DISPLAY_CHECK_PASS old_pixels=%0d new_pixels=%0d",display0_pixels,display4_pixels);
  test_passed=1;''')
        if name in ('tb_reason','tb_tag_status'):
            s=add_ports(s,'frame_processor',".input_geometry_valid(1'b0),.input_corners(96'd0),")
        if name=='tb_reason':
            # Under B's black detector an all-black 8x8 image has valid
            # quadrant statistics. White is the actual missing-marker scene.
            s=s.replace('.mem_rgb(24\'d0)',".mem_rgb(24'h808080)")
        if name=='tb_preview_display':s=add_ports(s,'ddr_result_display',".capture_guard(1'b0),.prefetch_busy(),")
        target=out/(name+'.sv');target.write_text(s);sources[name]=digest(src)
    finalize_ports(out)
    inputs={str(p):digest(p) for p in out.rglob('*') if p.is_file()}
    results={}
    for name,marker in cases.items():
        work=out/name;work.mkdir()
        script=template.replace((root/'fullhd_tests/tb_scheduler.sv').as_posix(),(out/(name+'.sv')).as_posix())
        script=script.replace('work_scheduler','work_'+name).replace('tb_scheduler',name)
        script=re.sub(r'^transcript file .*$', 'transcript file {'+(work/'transcript.log').as_posix()+'}',script,flags=re.M)
        script=re.sub(r'-wlf \{[^}]*\}', '-wlf {'+(work/'wave.wlf').as_posix()+'}',script)
        do=work/'run.do';do.write_text(script);inputs[str(do)]=digest(do)
        log=work/'simulation.log'
        with log.open('w') as stream:
            proc=subprocess.run(['D:/softwares/modelsim/win64/vsim.exe','-c','-do',str(do)],cwd=work,stdout=stream,stderr=subprocess.STDOUT)
        text=log.read_text();passed=proc.returncode==0 and marker in text and 'VERIFIED_PASS_BIT=1' in text and not re.search(r'\*\* (Error|Warning|Fatal)',text)
        results[name]=dict(passed=passed,exit_code=proc.returncode,log_sha256=digest(log))
        print(('PASS ' if passed else 'FAIL ')+name,flush=True)
        if not passed:print(text[-3500:],flush=True);break
    assert digest(mp)==binding
    for name,item in m['files'].items():assert digest(root/name)==item['local_sha256'],name
    for path,sha in inputs.items():assert digest(Path(path))==sha,path
    passed=len(results)==len(cases) and all(r['passed'] for r in results.values())
    (out/'qualification.json').write_text(json.dumps(dict(passed=passed,source_manifest_sha256=binding,root=str(root),
        tests=results,inputs=inputs,original_test_sources=sources,held_display_pixel_check=a.verify_held_display,hardware_accepted=False),indent=2)+'\n')
    raise SystemExit(0 if passed else 1)


if __name__=='__main__':main()
