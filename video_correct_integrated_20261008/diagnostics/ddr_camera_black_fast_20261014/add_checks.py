"""Prepare independent cache checks and sparse/full-scan equivalence fixtures."""
from pathlib import Path
import json
import numpy as np
import sys

D=Path(__file__).resolve().parent
O=D/"results"
sys.path.insert(0,str(D/"b_algorithm/python"))
from brect.fixed import solve_fixed,map_fixed,sample_fixed


def main():
    for n,points,mode in [(0,[(10,8),(52,13),(56,40),(7,38)],"bilinear"),
                          (1,[(12,9),(51,14),(55,39),(8,37)],"nearest")]:
        yy,xx=np.mgrid[:48,:64]
        image=np.stack([80+(xx*7+yy*3)%176,80+(xx*2+yy*11)%176,80+(xx*13+yy*5)%176],axis=-1).astype(np.uint8)
        for x,y in points:image[y-2:y+3,x-2:x+3]=0
        # Deliberate black content outside all four windows is ignored in both scans.
        image[20:28,25:39]=0
        h=solve_fixed(points,32,24,64,48)
        out=np.zeros((24,32,3),np.uint8)
        for y in range(24):
            for x in range(32):
                sx,sy,ok=map_fixed(h,x,y)
                assert ok
                out[y,x]=sample_fixed(image,sx,sy,mode)
        for name,arr in [(f"roi_source{n}",image),(f"roi_expected{n}",out)]:
            rgb=(arr[...,0].astype(np.uint32)<<16)|(arr[...,1].astype(np.uint32)<<8)|arr[...,2]
            np.savetxt(O/(name+".hex"),rgb.ravel(),fmt="%06x")
    template=(O/"tb_coord_queue_control.do").read_text(encoding="utf-8")
    cases=json.loads((O/"simulation_cases.json").read_text(encoding="utf-8"))
    for top,marker in [("tb_black_fast_cache","BLACK_FAST_CACHE_PASS"),("tb_black_roi_scan","BLACK_ROI_SCAN_PASS")]:
        (O/(top+".do")).write_text(template.replace("tb_coord_queue_control",top),encoding="utf-8")
        cases[top]=marker
    (O/"simulation_cases.json").write_text(json.dumps(cases,indent=2)+"\n",encoding="utf-8")
    print("FAST_ADDITIONAL_CHECKS_READY")


if __name__=="__main__":main()
