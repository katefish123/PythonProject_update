"""Generate separate high-resolution data for the existing independent fixed model."""
from pathlib import Path
import json
import sys
import numpy as np
from PIL import Image

D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/"results"
sys.path.insert(0,str(R/"vendor/b/python"))
from brect.fixed import rectify_fixed
from brect.golden import detect_markers
source_image=Image.open(R/"results/camera_target_large_20261011/source_large_markers_640x480.png").convert("RGB").resize((960,540),Image.Resampling.NEAREST)
source=np.asarray(source_image,dtype=np.uint8)
points,stats=detect_markers(source)
assert points is not None,stats
expected,coefficients=rectify_fixed(source,points,640,904,method="bilinear")
def write_hex(path,pixels):
    packed=(pixels[...,0].astype(np.uint32)<<16)|(pixels[...,1].astype(np.uint32)<<8)|pixels[...,2].astype(np.uint32)
    np.savetxt(path,packed.reshape(-1),fmt="%06x")
write_hex(O/"source_960x540.hex",source)
write_hex(O/"expected_640x904.hex",expected)
source_image.save(O/"source_960x540.png")
Image.fromarray(expected).save(O/"expected_640x904.png")
(O/"fixture.json").write_text(json.dumps({"source":[960,540],"output":[640,904],"pixels":640*904,
    "points":points.tolist(),"marker_stats":stats,"fixed_h_q16_24":coefficients},indent=2)+"\n",encoding="utf-8")
print("Generated independent high-detail reference and unchanged-centre marker fixture.")
