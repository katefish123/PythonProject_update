import sys,json,hashlib,shutil
from pathlib import Path
import numpy as np
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'fixtures'))
from generate import solve_h,rectify,audit,save_rgb,chart
BASE=Path('D:/FPGA/output/c_stream_board_v1_20261015')
sys.path.insert(0,str(BASE/'fullhd_tests/reference'))
from brect.golden import detect_markers

def main():
 config=json.loads((BASE/'fullhd_tests/fixture.json').read_text())['configuration']
 for size in ['reduced','fullhd']:
  folder=HERE/'fixtures'/size;folder.mkdir(parents=True,exist_ok=True)
  if size=='fullhd':
   sw,sh,ow,oh,aw=1920,1080,768,1080,765;rois=config['rois'];minimum=64;span=256
  else:
   sw,sh,ow,oh,aw=128,48,32,48,29
   rois={'TL':[[27,0],[42,11]],'TR':[[85,0],[101,14]],'BR':[[95,34],[111,47]],'BL':[[17,31],[33,47]]};minimum=16;span=16
  records=[];words=[]
  for variant,suffix in enumerate(['','variant_','variant2_']):
   if size=='fullhd':
    source=BASE/f'fullhd_tests/source_{suffix}1920x1080.hex'
    packed=np.loadtxt(source,dtype=np.uint32,converters=lambda s:int(s,16))
    image=np.stack(((packed>>16)&255,(packed>>8)&255,packed&255),axis=-1).astype(np.uint8).reshape(sh,sw,3)
   else:
    image=(chart(sw,sh,[11,29,43][variant])//2+128).astype(np.uint8)
    points=np.array([(34,4),(93,6),(103,42),(25,39)])
    points+=np.array([[(0,0)]*4,[(1,1),(-1,1),(1,-1),(-1,-1)],[(2,0),(-2,1),(1,-1),(-1,2)]][variant])
    for x,y in points:image[y-2:y+3,x-2:x+3]=0
   found,stats=detect_markers(image,min_pixels=minimum,max_pixels=16384,max_span=span,rois=rois)
   assert found is not None,(size,variant,stats)
   points=found.tolist();h=solve_h(points,aw,oh,sw,sh)
   result=rectify(image,h,aw,oh,ow,1,'bilinear')
   checks=audit(image,result,h,points,aw,oh,1,'bilinear')
   artifacts={'source':save_rgb(folder/f'source{variant}.hex',image),'expected':save_rgb(folder/f'expected{variant}.hex',result)}
   words.append(''.join(f'{int(v):03x}' for v in found.ravel()))
   records.append({'variant':variant,'corners':points,'corner_word':words[-1],'H_q24':h,'marker_stats':stats,'scalar_checks':checks,'artifacts':artifacts})
   print('MARKER_FIXTURE_READY',size,variant,words[-1],flush=True)
  (folder/'corners96.hex').write_text('\n'.join(words)+'\n')
  (folder/'metadata.json').write_text(json.dumps({'source':[sw,sh],'storage':[ow,oh],'active_w':aw,'active_x':1,'rois':rois,'frames':records,'source_reference':str(BASE/'fullhd_tests/fixture.json')},indent=2)+'\n')
if __name__=='__main__':main()
