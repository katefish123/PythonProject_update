"""Executable synthetic integer model, Q34.30; this is not FPGA RTL.

Arithmetic uses explicit 64-bit storage/128-bit intermediates and signed
nearest-even rounding. Numeric rejection is separate from source bounds.
"""
from dataclasses import dataclass
from lens_golden import Profile,FrameMap

SCALE=1<<30


class NumericReject(ValueError):pass


def round_ratio(n,d):
    if d==0:raise NumericReject('division by zero')
    sign=-1 if (n<0)!=(d<0) else 1
    q,r=divmod(abs(n),abs(d))
    if r*2>abs(d) or (r*2==abs(d) and q&1):q+=1
    return sign*q


def checked(value,bits=64):
    if not -(1<<(bits-1))<=value<(1<<(bits-1)):
        raise NumericReject(f'signed {bits}-bit overflow')
    return value


def encode(value):
    n,d=float(value).as_integer_ratio()
    return checked(round_ratio(n*SCALE,d))


def mul(a,b):return checked(round_ratio(checked(a*b,128),SCALE))
def div(a,b):return checked(round_ratio(checked(a*SCALE,128),b))
def add(*values):return checked(sum(values))


@dataclass(frozen=True)
class FixedMapped:
    x_q:int
    y_q:int
    inside:bool


@dataclass(frozen=True)
class FixedFrameMap:
    profile:Profile
    h:tuple=(1.,0.,0.,0.,1.,0.,0.,0.,1.)

    def __post_init__(self):
        validated=FrameMap(self.profile,self.h)
        object.__setattr__(self,'h',validated.h)
        object.__setattr__(self,'h_q',tuple(encode(v) for v in validated.h))
        names=('fx','fy','cx','cy','k1','k2','p1','p2')
        object.__setattr__(self,'parameters_q',tuple(encode(getattr(self.profile,n)) for n in names))

    def map(self,u,v):
        if type(u) is not int or type(v) is not int or not (0<=u<4096 and 0<=v<4096):
            raise NumericReject('destination must be unsigned 12-bit integer pixels')
        h=self.h_q
        # Multiplication by integer pixel indices has no fractional rounding.
        den=add(h[6]*u,h[7]*v,h[8])
        if den<SCALE//16:raise NumericReject('H denominator below 1/16')
        ideal_u=div(add(h[0]*u,h[1]*v,h[2]),den)
        ideal_v=div(add(h[3]*u,h[4]*v,h[5]),den)
        fx,fy,cx,cy,k1,k2,p1,p2=self.parameters_q
        x,y=div(add(ideal_u,-cx),fx),div(add(ideal_v,-cy),fy)
        if abs(x)>4*SCALE or abs(y)>4*SCALE:raise NumericReject('normalized domain exceeds 4')
        if k1==k2==p1==p2==0:
            # Avoid normalization/reprojection quantization at exact image
            # edges when lens correction is disabled.
            sx,sy=ideal_u,ideal_v
        else:
            x2,y2,xy=mul(x,x),mul(y,y),mul(x,y)
            r2=add(x2,y2);r4=mul(r2,r2)
            radial=add(SCALE,mul(k1,r2),mul(k2,r4))
            xd=add(mul(x,radial),mul(2*p1,xy),mul(p2,add(r2,2*x2)))
            yd=add(mul(y,radial),mul(p1,add(r2,2*y2)),mul(2*p2,xy))
            sx,sy=add(mul(fx,xd),cx),add(mul(fy,yd),cy)
        inside=0<=sx<=(self.profile.width-1)*SCALE and 0<=sy<=(self.profile.height-1)*SCALE
        return FixedMapped(sx,sy,inside)
