"""Small helper for synthetic optical-counter QA using the unchanged B model."""
from pathlib import Path
import sys
import json
import numpy as np
from PIL import Image

D=Path(__file__).resolve().parent
sys.path.insert(0,str(D/"b_algorithm/python"))
from brect.fixed import solve_fixed


def rectify_target(image):
    config=json.loads((D/"config.json").read_text(encoding="utf-8"))
    source=np.asarray(image)[::2,::2].astype(np.int64)
    h=solve_fixed(config["fixture_points"],640,904,960,540)
    yy,xx=np.mgrid[:904,:640].astype(np.int64)
    den=h[6]*xx+h[7]*yy+h[8]
    qx=(h[0]*xx+h[1]*yy+h[2])*256//den;qy=(h[3]*xx+h[4]*yy+h[5])*256//den
    x0,y0=qx>>8,qy>>8;x1,y1=np.minimum(x0+1,959),np.minimum(y0+1,539)
    fx,fy=(qx&255)[...,None],(qy&255)[...,None]
    result=((source[y0,x0]*(256-fx)+source[y0,x1]*fx)*(256-fy)
            +(source[y1,x0]*(256-fx)+source[y1,x1]*fx)*fy)>>16
    return Image.fromarray(result.astype(np.uint8)).resize((320,452))
