"""Bit-exact integer model of the supplied RTL (not a float quantizer).

Coefficients: signed 40 bits, F=24 (Q16.24, integer width includes sign).
Mapped nonnegative coordinates: unsigned 20 bits, F=8 (UQ12.8).
Signed solver division truncates toward zero; pixels truncate at final step.
"""
import numpy as np
from .golden import validate_points, validate_image

CF, PF = 24, 8
S, T = 1 << CF, 1 << PF
DEN_MIN = S // 16


def trunc_div(n, d):
    if not d:
        raise ValueError("division by zero")
    q = abs(int(n)) // abs(int(d))
    return -q if (n < 0) != (d < 0) else q


def signed_checked(n, bits):
    n = int(n)
    if not -(1 << (bits-1)) <= n < (1 << (bits-1)):
        raise ValueError(f"signed {bits}-bit overflow")
    return n


def solve_fixed(points, out_w, out_h, src_w=4096, src_h=4096):
    """Closed form quad-to-square inverse map, mirrored by homography_solver.v."""
    p = validate_points(points)
    if not np.equal(p, np.floor(p)).all() or not np.all((p >= 0) & (p <= 4095)):
        raise ValueError("RTL corners are integer coordinates 0..4095")
    if not (2 <= out_w <= 4096 and 2 <= out_h <= 4096):
        raise ValueError("Output dimensions must be 2..4096")
    if np.any(p[:, 0] >= src_w) or np.any(p[:, 1] >= src_h):
        raise ValueError("Corner outside source frame")
    (x0,y0),(x1,y1),(x2,y2),(x3,y3) = [[int(v) for v in row] for row in p]
    dx1, dx2, dx3 = x1-x2, x3-x2, x0-x1+x2-x3
    dy1, dy2, dy3 = y1-y2, y3-y2, y0-y1+y2-y3
    det = dx1*dy2-dx2*dy1
    if abs(det) < 16:
        raise ValueError("Degenerate quad")
    g = trunc_div((dx3*dy2-dx2*dy3)*S, det)
    k = trunc_div((dx1*dy3-dx3*dy1)*S, det)
    if abs(g) > 4*S or abs(k) > 4*S:
        raise ValueError("Perspective too extreme for demo envelope")
    h = [trunc_div((x1-x0)*S+g*x1, out_w-1),
         trunc_div((x3-x0)*S+k*x3, out_h-1), x0*S,
         trunc_div((y1-y0)*S+g*y1, out_w-1),
         trunc_div((y3-y0)*S+k*y3, out_h-1), y0*S,
         trunc_div(g, out_w-1), trunc_div(k, out_h-1), S]
    h = [signed_checked(v, 40) for v in h]
    for x,y in [(0,0),(out_w-1,0),(out_w-1,out_h-1),(0,out_h-1)]:
        if h[6]*x+h[7]*y+h[8] <= DEN_MIN:
            raise ValueError("Denominator below safe minimum")
    return h


def map_fixed(h, x, y):
    nx, ny = h[0]*x+h[1]*y+h[2], h[3]*x+h[4]*y+h[5]
    d = h[6]*x+h[7]*y+h[8]
    ok = d > DEN_MIN and 0 <= nx < (1<<48) and 0 <= ny < (1<<48) and d < (1<<48)
    ok = ok and nx < (d << 12) and ny < (d << 12)
    if not ok:
        return 0, 0, False
    return (nx << PF)//d, (ny << PF)//d, True


def addresses(sx, sy, width, height, method="bilinear"):
    if method == "nearest":
        x0, y0 = (sx+T//2)//T, (sy+T//2)//T
        inside = 0 <= x0 < width and 0 <= y0 < height
        return inside, [y0*width+x0]*4 if inside else [0]*4, 0, 0
    if method != "bilinear":
        raise ValueError("method must be nearest or bilinear")
    inside = 0 <= sx <= (width-1)*T and 0 <= sy <= (height-1)*T
    if not inside:
        return False, [0]*4, 0, 0
    x0, fx = divmod(sx, T)
    y0, fy = divmod(sy, T)
    x1, y1 = min(x0+1, width-1), min(y0+1, height-1)
    return True, [y0*width+x0, y0*width+x1, y1*width+x0, y1*width+x1], fx, fy


def interpolate(pixels, fx, fy):
    p00,p10,p01,p11 = [[int(c) for c in p] for p in pixels]
    return np.asarray([((p00[c]*(T-fx)+p10[c]*fx)*(T-fy) +
                        (p01[c]*(T-fx)+p11[c]*fx)*fy) >> (2*PF)
                       for c in range(3)], dtype=np.uint8)


def sample_fixed(image, sx, sy, method="bilinear"):
    height,width = image.shape[:2]
    inside, a, fx, fy = addresses(sx,sy,width,height,method)
    if not inside:
        return np.zeros(3,np.uint8)
    return interpolate(image.reshape(-1,3)[a],fx,fy)


def rectify_fixed(image, points, out_w, out_h, method="bilinear"):
    validate_image(image)
    if method not in ("nearest", "bilinear"):
        raise ValueError("method must be nearest or bilinear")
    height,width = image.shape[:2]
    h = solve_fixed(points,out_w,out_h,width,height)
    out = np.zeros((out_h,out_w,3),np.uint8)
    for y in range(out_h):
        for x in range(out_w):
            sx,sy,valid = map_fixed(h,x,y)
            if valid:
                out[y,x] = sample_fixed(image,sx,sy,method)
    return out,h
