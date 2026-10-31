"""Plan a crop in the output plane; compose it into H before the single sample.

Validity means an available source coordinate, independent of RGB content.
Every accepted viewport is checked on the entire float AND RTL-integer grid.
Planning runs on the host when calibration/H/size changes, not per video pixel.
"""
import copy
import json
from numbers import Integral
from pathlib import Path
import numpy as np
from .lens import LENS_SCALE, _homography_fixed, map_lens_float


def read_homography(path):
    """Read the explicit matrix shared by the image CLI and hardware exporter."""
    if path is None:
        return np.eye(3)
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if isinstance(data, dict):
        if "H" not in data:
            raise ValueError("Homography JSON object requires a 3 by 3 H field")
        data = data["H"]
    result = np.asarray(data, dtype=np.float64)
    if result.shape != (3, 3) or not np.isfinite(result).all():
        raise ValueError("Homography JSON must contain a finite 3 by 3 matrix")
    return result


def _arguments(profile, H, output_size):
    size = (profile.width, profile.height) if output_size is None else tuple(output_size)
    if len(size) != 2 or any(isinstance(v, bool) or not isinstance(v, Integral) or not 2 <= v <= 4096 for v in size):
        raise ValueError('output_size requires integer width, height in 2..4096')
    if not 2 <= profile.width <= 4096 or not 2 <= profile.height <= 4096:
        raise ValueError('Source dimensions must be in 2..4096')
    h = np.eye(3) if H is None else np.asarray(H, dtype=np.float64)
    if h.shape != (3,3) or not np.isfinite(h).all():
        raise ValueError('H must be a finite 3 by 3 destination-to-ideal-source matrix')
    _homography_fixed(h)
    profile.to_hardware()
    return h, tuple(map(int,size))


def _pixel_product(coordinate, focal, center):
    # Legal extreme profiles can exceed int64 in this last multiplication.
    # Decide from Python integers before multiplying, then use arbitrary width.
    bound = int(np.max(np.abs(coordinate))) * abs(focal) + (abs(center) << 26)
    if bound > np.iinfo(np.int64).max:
        return np.asarray(((coordinate.astype(object) * focal + (center << 26)) >> 34), dtype=np.int64)
    return (coordinate * focal + (center << 26)) >> 34


def _fixed_map(hw, q, xx, yy):
    nx=q[0]*xx+q[1]*yy+q[2];ny=q[3]*xx+q[4]*yy+q[5];den=q[6]*xx+q[7]*yy+q[8]
    valid=(den>(1<<20)) & (den<(1<<48)) & (nx>=0) & (ny>=0) & (nx<(1<<48)) & (ny<(1<<48))
    valid &= (nx < (den << 12)) & (ny < (den << 12))
    d=np.where(valid,den,1)
    u=(np.where(valid,nx,0)<<8)//d;v=(np.where(valid,ny,0)<<8)//d
    if all(hw[key]==0 for key in ('K1_Q26','K2_Q26','P1_Q26','P2_Q26')):
        return u,v,valid
    x=(((u<<8)-hw['CX_Q16'])*hw['INV_FX_Q30'])>>20
    y=(((v<<8)-hw['CY_Q16'])*hw['INV_FY_Q30'])>>20
    valid &= (np.abs(x)<=2*LENS_SCALE) & (np.abs(y)<=2*LENS_SCALE)
    # Check before squaring/shrinking, just like the hardware leaf.
    x=np.where(valid,x,0);y=np.where(valid,y,0)
    xxn=(x*x)>>26;yyn=(y*y)>>26;xy=(x*y)>>26;r2=xxn+yyn
    inner=hw['K1_Q26']+((hw['K2_Q26']*r2)>>26)
    radial=LENS_SCALE+((r2*inner)>>26)
    tx=((hw['P1_Q26']*(2*xy))>>26)+((hw['P2_Q26']*(r2+2*xxn))>>26)
    ty=((hw['P1_Q26']*(r2+2*yyn))>>26)+((hw['P2_Q26']*(2*xy))>>26)
    xd=((x*radial)>>26)+tx;yd=((y*radial)>>26)+ty
    sx=_pixel_product(xd,hw['FX_Q16'],hw['CX_Q16'])
    sy=_pixel_product(yd,hw['FY_Q16'],hw['CY_Q16'])
    return np.where(valid,sx,0),np.where(valid,sy,0),valid


def fixed_grid(profile, H, x, y):
    """Exact scalar RTL model evaluated in arrays, with checked wide arithmetic."""
    h,_=_arguments(profile,H,None)
    xx,yy=np.broadcast_arrays(np.asarray(x),np.asarray(y))
    if (xx.dtype.kind not in 'iu' or yy.dtype.kind not in 'iu' or
        np.any(xx<0) or np.any(yy<0) or np.any(xx>4095) or np.any(yy>4095)):
        raise ValueError('Destination coordinates must be integer pixels in 0..4095')
    return _fixed_map(profile.to_hardware(),_homography_fixed(h),xx.astype(np.int64),yy.astype(np.int64))


def mapping_mask(profile, H=None, output_size=None, fixed=False):
    """Strict bilinear source availability for every output pixel, in 64-row chunks.

    This strict bound also guarantees nearest sampling is inside the source.
    It does not classify naturally black source content as a missing pixel.
    """
    h,(width,height)=_arguments(profile,H,output_size)
    result=np.zeros((height,width),dtype=bool)
    hw=profile.to_hardware();q=_homography_fixed(h)
    for first in range(0,height,64):
        xx,yy=np.meshgrid(np.arange(width,dtype=np.int64),np.arange(first,min(first+64,height),dtype=np.int64))
        if fixed:
            sx,sy,valid=_fixed_map(hw,q,xx,yy)
            valid &= (sx>=0)&(sy>=0)&(sx<=(profile.width-1)*256)&(sy<=(profile.height-1)*256)
        else:
            den=h[2,0]*xx+h[2,1]*yy+h[2,2]
            with np.errstate(divide='ignore',invalid='ignore',over='ignore'):
                u=(h[0,0]*xx+h[0,1]*yy+h[0,2])/den
                v=(h[1,0]*xx+h[1,1]*yy+h[1,2])/den
            sx,sy,valid=map_lens_float(profile,u,v)
            valid &= np.isfinite(den)&(den>1./16.)
            valid &= (sx>=-1e-9)&(sy>=-1e-9)&(sx<=profile.width-1+1e-9)&(sy<=profile.height-1+1e-9)
        result[first:first+len(yy)]=valid
    return result


def _masks(profile,h,size):
    floating=mapping_mask(profile,h,size)
    integer=mapping_mask(profile,h,size,fixed=True)
    counts={'float_outside_pixels':int((~floating).sum()),'fixed_outside_pixels':int((~integer).sum())}
    return floating & integer,counts


def _largest_rectangle(mask):
    heights=np.zeros(mask.shape[1],dtype=np.int64);best=None;area=0
    for y,row in enumerate(mask):
        heights=np.where(row,heights+1,0)
        stack=[]
        for x,height in enumerate(heights.tolist()+[0]):
            start=x
            while stack and stack[-1][1]>height:
                left,tall=stack.pop();start=left
                if tall>=2 and x-left>=2 and tall*(x-left)>area:
                    area=tall*(x-left);best=(left,y-tall+1,x-1,y)
            if height and (not stack or stack[-1][1]<height):stack.append((start,height))
    if best is None:raise ValueError('No usable two-dimensional valid source region for this H/calibration')
    return best


def plan_viewport(profile, H=None, output_size=None):
    """Return effective H and a full-grid proof for one specific geometry.

    Keep aspect ratio and pixel dimensions; cropping discards peripheral FOV.
    A failed plan raises rather than disguising invalid data as a black-free view.
    No claim is made that the chosen crop maximizes the retained field of view.
    """
    h,size=_arguments(profile,H,output_size);width,height=size
    mask,before=_masks(profile,h,size)
    viewport=np.eye(3);effective=h.copy();scale=1.;rectangle=[0,0,width-1,height-1]
    after=before
    if not mask.all():
        rectangle=list(_largest_rectangle(mask));x0,y0,x1,y1=rectangle
        centerx,centery=(x0+x1)/2.,(y0+y1)/2.
        spanx,spany=x1-x0,y1-y0
        scale=min((spanx-2*min(1.,.05*spanx))/(width-1),
                  (spany-2*min(1.,.05*spany))/(height-1),1.)
        for attempt in range(24):
            viewport=np.array([[scale,0.,centerx-scale*(width-1)/2.],
                               [0.,scale,centery-scale*(height-1)/2.],[0.,0.,1.]])
            effective=h @ viewport
            verified,after=_masks(profile,effective,size)
            if verified.all():break
            scale*=.98
        else:raise ValueError('No fully valid viewport could be verified after quantization')
    report={'policy':'auto','source_size':[profile.width,profile.height],'output_size':list(size),
            'base_H':h.tolist(),'effective_H':effective.tolist(),'H_q24':_homography_fixed(effective),
            'viewport':viewport.tolist(),'valid_integer_rectangle':rectangle,'scale':float(scale),
            'zoom':float(1./scale),'retained_canvas_area_fraction':float(scale*scale),
            'aspect_ratio_preserved':True,'sampling_bound':'strict bilinear (also safe for nearest)',
            'before':before,'after':after,'verified_pixels':width*height,
            'proof':'Every output center checked using float mapping and exact quantized H/lens arithmetic',
            'binding':'Valid only for this calibration, base H, effective H and source/output sizes; replan on change',
            'calibration_metadata':copy.deepcopy(profile.metadata)}
    return effective,report
