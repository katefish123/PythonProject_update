from pathlib import Path
import json,sys,hashlib,re
import numpy as np
R=Path(__file__).resolve().parent
B=Path('D:/FPGA/team_downloads/20261022_B_lens_v2/member_b_lens_pipeline_v2')
O=Path('D:/FPGA/output/b_lens_board_fixtures_20261022');O.mkdir(exist_ok=True)
sys.path.insert(0,str(B/'python'))
from brect.calibration import load_calibration
from brect.viewport import fixed_grid
from brect.lens import _homography_fixed
m=json.loads((B/'examples/r50_18mm_viewport.json').read_text());p=load_calibration(B/'calibration/r50_18mm_hdmi_trial.json',(1920,1080))
h=np.array(m['effective_H']);assert list(_homography_fixed(h))==m['H_q24']
y,x=np.indices((1080,1920));sx,sy,valid=fixed_grid(p,h,x,y)
assert np.all(valid&(sx>=0)&(sy>=0)&(sx<=1919*256)&(sy<=1079*256))
ix=sx>>8;iy=sy>>8;fx=sx&255;fy=sy&255
a00=iy*1920+ix;a10=iy*1920+np.minimum(ix+1,1919);a01=np.minimum(iy+1,1079)*1920+ix;a11=np.minimum(iy+1,1079)*1920+np.minimum(ix+1,1919)
a=np.arange(1920*1080,dtype=np.int64)
source=np.stack(((a*17+3)&255,(a>>3)&255,((a*11)>>7)&255),axis=-1)
def save(n,v):
 with (O/n).open('w',encoding='ascii') as f:
  for row in v.reshape(1080,1920):f.write(''.join('%06x\n'%int(q) for q in row))
for suffix,src in [('',source),('_alt',source^0x55)]:
 q=src[a00]*(256-fx)[...,None]+src[a10]*fx[...,None]
 r=src[a01]*(256-fx)[...,None]+src[a11]*fx[...,None]
 rgb=(q*(256-fy)[...,None]+r*fy[...,None])>>16
 save('source'+suffix+'.hex',(src[:,0]<<16)|(src[:,1]<<8)|src[:,2])
 save('expected'+suffix+'.hex',(rgb[...,0]<<16)|(rgb[...,1]<<8)|rgb[...,2])
(O/'H40.hex').write_text(''.join('%010x\n'%(int(v)&((1<<40)-1)) for v in m['H_q24']),encoding='ascii')
t=(R.parent/'board_next_20261016/integration/tb_raw_pipeline.sv').read_text()
t=t.replace('parameter NATIVE=0,FRAMES=5,CORRECTED=0','parameter NATIVE=1,FRAMES=2,CORRECTED=1')
t=t.replace('OW=NATIVE?768:64','OW=NATIVE?1920:64')
t=t.replace('FRAMES*40000000+100000000','FRAMES*100000000+100000000')
t='\n'.join(line for line in t.split('\n') if 'actual geometry/generation mismatch corners=' not in line and 'trace snapshot did not preserve completed geometry/H/frame ID' not in line)
pos=t.index(' initial begin\n if(CORRECTED)begin');end=t.index(' bank_id[0]=0;',pos)
init=' initial begin\n if(dut.stream_path.processor.FIXED_IDENTITY!=1)$fatal(1,"B_LENS_TRIAL_NOT_CONNECTED");\n'
for n,dest in [('source.hex','source_fixture'),('source_alt.hex','source_alt'),('expected.hex','expected_fixture'),('expected_alt.hex','expected_alt'),('H40.hex','expected_h'),('H40.hex','expected_h_alt')]:init+=f' $readmemh("{(O/n).as_posix()}",{dest});\n'
t=t[:pos]+init+t[end:]
(R/'tb_lens_board.sv').write_text(t,encoding='utf-8')
manifest={'synthetic':True,'width':1920,'height':1080,'reference':'B exact integer fixed_grid + single RGB bilinear interpolation','H_q24':m['H_q24'],'source_sha256':{n:hashlib.sha256((B/n).read_bytes()).hexdigest() for n in ['python/brect/lens.py','python/brect/viewport.py','python/brect/calibration.py','examples/r50_18mm_viewport.json']},'fixtures_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in O.glob('*.hex')}}
(O/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('FIXTURES native2073600 pixels,two different RGB source frames,all fixed coordinates inside')
