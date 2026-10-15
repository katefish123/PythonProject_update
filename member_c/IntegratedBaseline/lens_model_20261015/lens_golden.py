"""Synthetic-only scalar float64 lens oracle. No camera or hardware acceptance.

Destination -> optional H -> undistorted camera pixel -> Brown -> raw source.
Pixel centers are integers; x right, y down. Sampling is outside this module.
"""
from dataclasses import dataclass, fields
import json
import math
from pathlib import Path


def _finite(value, name):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"{name} must be a finite number")
    return float(value)


@dataclass(frozen=True)
class Profile:
    width: int
    height: int
    fx: float
    fy: float
    cx: float
    cy: float
    k1: float
    k2: float
    p1: float
    p2: float
    profile_id: str
    provenance: str = "synthetic"

    def __post_init__(self):
        for name in ("width", "height"):
            value = getattr(self, name)
            if type(value) is not int or not 2 <= value <= 4096:
                raise ValueError(f"{name} must be an integer in 2..4096")
        for name in ("fx", "fy", "cx", "cy", "k1", "k2", "p1", "p2"):
            object.__setattr__(self, name, _finite(getattr(self, name), name))
        if not (1 <= self.fx <= 65536 and 1 <= self.fy <= 65536):
            raise ValueError("focal lengths must be in 1..65536 pixels")
        if not (0 <= self.cx <= self.width-1 and 0 <= self.cy <= self.height-1):
            raise ValueError("principal point must lie in source active image")
        if abs(self.k1) > 1 or abs(self.k2) > 1 or abs(self.p1) > .25 or abs(self.p2) > .25:
            raise ValueError("synthetic envelope: abs(k1,k2)<=1; abs(p1,p2)<=0.25")
        if self.provenance != "synthetic" or not isinstance(self.profile_id,str) or not self.profile_id.strip():
            raise ValueError("this infrastructure accepts named synthetic profiles only")


@dataclass(frozen=True)
class Mapped:
    x: float
    y: float
    inside: bool


@dataclass(frozen=True)
class FrameMap:
    """Immutable H/profile snapshot; create a new instance for a new frame.

    This is a software ownership contract, not an RTL bank or frame controller.
    """
    profile: Profile
    h: tuple = (1.,0.,0.,0.,1.,0.,0.,0.,1.)

    def __post_init__(self):
        if not isinstance(self.profile, Profile):
            raise ValueError("profile must be a validated Profile")
        try:
            values = tuple(_finite(v,"H coefficient") for v in self.h)
        except TypeError as exc:
            raise ValueError("H must be an iterable of nine numbers") from exc
        if len(values) != 9 or any(abs(v) > 65536 for v in values):
            raise ValueError("H must contain nine coefficients of magnitude <=65536")
        object.__setattr__(self,"h",values)

    def map(self, u, v):
        u,v = _finite(u,"u"),_finite(v,"v")
        h,p = self.h,self.profile
        d=h[6]*u+h[7]*v+h[8]
        if not math.isfinite(d) or d <= 1e-12:
            raise ValueError("H denominator must be finite and >1e-12")
        ideal_u=(h[0]*u+h[1]*v+h[2])/d
        ideal_v=(h[3]*u+h[4]*v+h[5])/d
        x,y=(ideal_u-p.cx)/p.fx,(ideal_v-p.cy)/p.fy
        if not math.isfinite(x) or not math.isfinite(y) or abs(x)>4 or abs(y)>4:
            raise ValueError("normalized mapping outside abs(x,y)<=4 envelope")
        r2=x*x+y*y
        radial=1+p.k1*r2+p.k2*r2*r2
        xd=x*radial+2*p.p1*x*y+p.p2*(r2+2*x*x)
        yd=y*radial+p.p1*(r2+2*y*y)+2*p.p2*x*y
        sx,sy=p.fx*xd+p.cx,p.fy*yd+p.cy
        if not math.isfinite(sx) or not math.isfinite(sy):
            raise ValueError("nonfinite projection")
        return Mapped(sx,sy,0<=sx<=p.width-1 and 0<=sy<=p.height-1)


def load_profile(path, expected_size):
    """Read synthetic JSON with exact schema and explicit active-source size.

    This loader does not configure existing B RTL or any camera.
    """
    try:
        data=json.loads(Path(path).read_text(encoding="utf-8"))
        required={f.name for f in fields(Profile)}
        if not isinstance(data,dict) or set(data)!=required:
            raise ValueError("profile JSON must contain exactly the Profile fields")
        profile=Profile(**data)
        if tuple(expected_size)!=(profile.width,profile.height):
            raise ValueError("profile and active source dimensions differ; recalibration or explicit K transformation required")
        return profile
    except (TypeError,KeyError) as exc:
        raise ValueError("invalid synthetic profile schema") from exc
