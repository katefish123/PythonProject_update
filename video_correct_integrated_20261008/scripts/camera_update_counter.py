"""Optical stimulus/decoder utilities. Synthetic references are never hardware evidence."""
from pathlib import Path
import sys
import numpy as np
from PIL import Image,ImageDraw,ImageFont
R=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(R/'vendor/b/python'))
from brect.golden import detect_markers,homography
ASSET=R/'results/camera_target_large_20261011/source_large_markers_640x480.png'
BASE=Image.open(ASSET).convert('RGB')
BITS=12
STEP=17
XS=[232+i*STEP for i in range(BITS)]
YS=(184,221)
REFS=((239,254),(423,254))
POINTS,STATS=detect_markers(np.asarray(BASE))
assert POINTS is not None
HI=np.linalg.inv(homography(POINTS,320,452))
def output_point(x,y):
    p=HI@np.array([x,y,1.0])
    return tuple(np.rint(p[:2]/p[2]).astype(int))
SAMPLES=[[output_point(x,y) for x in XS] for y in YS]
REFERENCE_SAMPLES=[output_point(x,y) for x,y in REFS]
FONT_PATH=Path('C:/Windows/Fonts/arialbd.ttf')
FONT=ImageFont.truetype(str(FONT_PATH),20) if FONT_PATH.exists() else ImageFont.load_default()
def make_target(value):
    value=int(value)&4095
    gray=value^(value>>1)
    im=BASE.copy()
    draw=ImageDraw.Draw(im)
    draw.rectangle((215,139,447,269),fill='white')
    draw.text((239,143),f'LIVE {value:04d}',font=FONT,fill='black')
    for row,y in enumerate(YS):
        for bit,x in enumerate(XS):
            on=((gray>>bit)&1)^row
            draw.rectangle((x-6,y-6,x+6,y+6),fill='white' if on else 'black',outline='black')
    for (x,y),color in zip(REFS,['black','white']):
        draw.rectangle((x-8,y-8,x+8,y+8),fill=color,outline='black')
    return im
def gray_to_binary(gray):
    n=0
    while gray:
        n^=gray
        gray>>=1
    return n
def decode_counter(frame):
    """Use original target geometry, white/black references and inverse row check."""
    assert frame.shape==(452,320,3)
    def level(point):
        x,y=point
        return float(np.median(frame[y-2:y+3,x-2:x+3].mean(axis=2)))
    black,white=[level(p) for p in REFERENCE_SAMPLES]
    if white-black<60:return None,{'contrast':round(white-black,2)}
    threshold=(black+white)/2
    values=[[level(p) for p in row] for row in SAMPLES]
    bits=[[int(v>threshold) for v in row] for row in values]
    if any(a==b for a,b in zip(*bits)):return None,{'contrast':round(white-black,2),'inverse_rows_match':False}
    gray=sum(v<<i for i,v in enumerate(bits[0]))
    confidence=min(abs(v-threshold) for row in values for v in row)/(white-black)
    if confidence<0.12:return None,{'contrast':round(white-black,2),'confidence':round(confidence,3)}
    return gray_to_binary(gray),{'contrast':round(white-black,2),'confidence':round(confidence,3)}
def prepare_reference():
    import hashlib,json
    O=R/'results/camera_update_counter_20261013'
    O.mkdir(exist_ok=True)
    digest=hashlib.sha256(ASSET.read_bytes()).hexdigest()
    h=homography(POINTS,320,452)
    coeff=tuple((h/h[2,2]).reshape(-1)[:8])
    checked=[]
    for n in (0,1,42,777,1023,4095):
        source=make_target(n)
        p,stats=detect_markers(np.asarray(source))
        assert np.array_equal(p,POINTS) and stats==STATS
        # Independent Pillow raster transform validates sample coordinates,
        # optical counter layout and contrasting bits under a perspective map.
        rect=source.transform((320,452),Image.Transform.PERSPECTIVE,coeff,Image.Resampling.BILINEAR)
        found,details=decode_counter(np.asarray(rect))
        assert found==n,(n,found,details)
        checked.append(n)
        if n==777:
            source.save(O/'stimulus_preview_640x480.png')
            rect.save(O/'synthetic_decoder_reference_320x452.png')
    assert hashlib.sha256(ASSET.read_bytes()).hexdigest()==digest
    record={'original_asset_sha256':digest,'synthetic_values_checked':checked,
        'hardware_picture_or_fps_accepted':False,'source_corner_points':POINTS.tolist(),
        'stimulus_tick_hz':10,'counter_bits':BITS,'gray_coded':True,'inverse_row_check':True,
        'sampling_output_size':[320,452],'note':'Synthetic layout/decoder validation only. Original asset and FPGA code unchanged. Actual rate must be measured from a new physical OBS recording.'}
    (O/'preparation.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(record,indent=2))
if __name__=='__main__':prepare_reference()
