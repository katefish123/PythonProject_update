"""Synthetic-only host preparation: raw corners -> ideal corners -> ideal H.

Local damped Newton inversion rejects singular/nonconvergent points. Residual
convergence does not establish global uniqueness or physical calibration.
"""
from pathlib import Path
import math,sys
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'lens_model_20261015'))
from lens_golden import Profile,FrameMap
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'a_black_sync_20261014/upstream/diagnostics/ddr_camera_black_20261014/b_algorithm/python'))
from brect.golden import homography

def _forward_jacobian(p,x,y):
 r2=x*x+y*y;radial=1+p.k1*r2+p.k2*r2*r2
 dx=2*x*(p.k1+2*p.k2*r2);dy=2*y*(p.k1+2*p.k2*r2)
 xx=x*radial+2*p.p1*x*y+p.p2*(r2+2*x*x)
 yy=y*radial+p.p1*(r2+2*y*y)+2*p.p2*x*y
 return xx,yy,(radial+x*dx+2*p.p1*y+6*p.p2*x,
  x*dy+2*p.p1*x+2*p.p2*y,y*dx+2*p.p1*x+2*p.p2*y,
  radial+y*dy+6*p.p1*y+2*p.p2*x)

def undistort_point(profile,raw_u,raw_v):
 if not isinstance(profile,Profile):raise ValueError('validated synthetic profile required')
 if not all(isinstance(v,(float,int)) and not isinstance(v,bool) and math.isfinite(v) for v in (raw_u,raw_v)):
  raise ValueError('finite source point required')
 if not any((profile.k1,profile.k2,profile.p1,profile.p2)):return float(raw_u),float(raw_v)
 tx=(raw_u-profile.cx)/profile.fx;ty=(raw_v-profile.cy)/profile.fy
 x,y=tx,ty
 if max(abs(x),abs(y))>4:raise ValueError('initial inverse point exceeds normalized envelope')
 for iteration in range(40):
  xx,yy,j=_forward_jacobian(profile,x,y);ex,ey=xx-tx,yy-ty
  det=j[0]*j[3]-j[1]*j[2]
  if not math.isfinite(det) or det<=1e-10:raise ValueError('nonpositive/singular local inverse Jacobian')
  if max(abs(ex),abs(ey))<1e-12:return profile.fx*x+profile.cx,profile.fy*y+profile.cy
  sx=(j[3]*ex-j[1]*ey)/det;sy=(-j[2]*ex+j[0]*ey)/det
  norm=ex*ex+ey*ey;step=1.
  for backtrack in range(20):
   nx,ny=x-step*sx,y-step*sy
   if max(abs(nx),abs(ny))<=4:
    qx,qy,_=_forward_jacobian(profile,nx,ny)
    if (qx-tx)**2+(qy-ty)**2<norm:x,y=nx,ny;break
   step*=.5
  else:raise ValueError('inverse step did not reduce residual')
 raise ValueError('inverse did not converge')

def fit_ideal_h(profile,raw_corners,out_width,out_height):
 if len(raw_corners)!=4:raise ValueError('four ordered raw corners required')
 ideal=tuple(undistort_point(profile,*p) for p in raw_corners)
 h=tuple(float(v) for v in homography(ideal,out_width,out_height).ravel())
 # Existing independent oracle validates finite coefficients and H envelope.
 FrameMap(profile,h)
 return h,ideal
