"""Native full-HD, per-pixel detail; reference is B's pinned independent Python model."""
from pathlib import Path
import argparse,json,subprocess,sys
import numpy as np
from PIL import Image
REV='6b0b2e257efcfbb379d3f447403beb5ad08e0086'
PREFIX='video_correct_integrated_20261008/vendor/b/python/'
def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True)
    out=p.parse_args().output.resolve();dest=out/'fullhd_tests';dest.mkdir(exist_ok=True)
    repo=Path(__file__).resolve().parents[3]
    files=subprocess.check_output(['git','ls-tree','-r','--name-only',REV,'--',PREFIX+'brect'],cwd=repo,text=True).splitlines()
    for name in files:
        if name.endswith('.py'):
            target=dest/'reference'/name[len(PREFIX):];target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(subprocess.check_output(['git','show',f'{REV}:{name}'],cwd=repo))
    sys.path.insert(0,str(dest/'reference'))
    from brect.fixed import rectify_fixed
    from brect.golden import detect_markers
    yy,xx=np.indices((1080,1920))
    gray=(32+((xx*13+yy*7)%96)).astype(np.uint8)
    source=np.repeat(gray[:,:,None],3,axis=2)
    for (x,y),color in zip([(600,100),(1400,220),(1300,950),(540,880)],[(220,30,30),(30,210,30),(220,210,30),(30,30,220)]):
        source[y-30:y+30,x-40:x+40]=color
    old_points,_=detect_markers(source)
    if old_points is not None:raise RuntimeError('Fixture must expose old marker-area rejection')
    points,stats=detect_markers(source,min_pixels=64,max_pixels=16384,max_span=256)
    if points is None:raise RuntimeError(stats)
    expected,coefficients=rectify_fixed(source,points,640,904,method='bilinear')
    for name,pixels in [('source_1920x1080',source),('expected_640x904',expected)]:
        packed=(pixels[:,:,0].astype(np.uint32)<<16)|(pixels[:,:,1].astype(np.uint32)<<8)|pixels[:,:,2]
        np.savetxt(dest/(name+'.hex'),packed.reshape(-1),fmt='%06x')
        Image.fromarray(pixels).save(dest/(name+'.png'))
    (dest/'fixture.json').write_text(json.dumps(dict(source=[1920,1080],output=[640,904],
        points=points.tolist(),marker_stats=stats,fixed_h_q16_24=coefficients,
        native_detail=True,upstream_commit=REV),indent=2)+'\n')
    print('NATIVE_FULLHD_GOLDEN_READY pixels=2073600 marker_area=4800 output_pixels=578560')
if __name__=='__main__':main()
