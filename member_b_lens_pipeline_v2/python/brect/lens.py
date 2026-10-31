"""Brown lens mapping followed by one source-image sampling operation.

An explicit destination-to-ideal-source homography is applied first. No marker
detector is involved. Float arrays are evaluated in chunks; the integer model
uses Python integers so the contract's wide intermediate values cannot wrap.
"""
import math
from numbers import Integral
import numpy as np
from .fixed import S as H_SCALE, map_fixed, sample_fixed
from .golden import validate_image

LENS_SCALE = 1 << 26


def _scalars_or_arrays(sx, sy, valid):
    if np.ndim(sx) == 0:
        return float(sx), float(sy), bool(valid)
    return sx, sy, valid


def map_lens_float(profile, u, v):
    """Map ideal source pixel centers to observed source centers, scalar/array.

    ``valid`` describes numerical validity, not whether a coordinate lies inside
    the source image. Out-of-frame coordinates are handled by the sampler.
    """
    u, v = np.broadcast_arrays(np.asarray(u, dtype=np.float64), np.asarray(v, dtype=np.float64))
    finite = np.isfinite(u) & np.isfinite(v)
    if all(getattr(profile, name) == 0 for name in ("k1", "k2", "p1", "p2")):
        return _scalars_or_arrays(np.where(finite, u, 0.), np.where(finite, v, 0.), finite)
    with np.errstate(over="ignore", invalid="ignore", divide="ignore"):
        x, y = (u - profile.cx) / profile.fx, (v - profile.cy) / profile.fy
        valid = finite & (np.abs(x) <= 2.) & (np.abs(y) <= 2.)
        xx, yy, xy = x * x, y * y, x * y
        r2 = xx + yy
        radial = 1. + r2 * (profile.k1 + profile.k2 * r2)
        xd = x * radial + 2. * profile.p1 * xy + profile.p2 * (r2 + 2. * xx)
        yd = y * radial + profile.p1 * (r2 + 2. * yy) + 2. * profile.p2 * xy
        sx, sy = profile.fx * xd + profile.cx, profile.fy * yd + profile.cy
        valid &= np.isfinite(sx) & np.isfinite(sy)
    return _scalars_or_arrays(np.where(valid, sx, 0.), np.where(valid, sy, 0.), valid)


def _map_hardware(hw, u_q8, v_q8, enabled=True, in_error=False):
    if in_error:
        return 0, 0, False
    if isinstance(u_q8, bool) or isinstance(v_q8, bool) or not isinstance(u_q8, Integral) or not isinstance(v_q8, Integral):
        raise ValueError("Fixed lens coordinates must be integer Q8 values")
    u, v = int(u_q8), int(v_q8)
    if not enabled or all(hw[key] == 0 for key in ("K1_Q26", "K2_Q26", "P1_Q26", "P2_Q26")):
        return u, v, True
    x = (((u << 8) - hw["CX_Q16"]) * hw["INV_FX_Q30"]) >> 20
    y = (((v << 8) - hw["CY_Q16"]) * hw["INV_FY_Q30"]) >> 20
    if abs(x) > 2 * LENS_SCALE or abs(y) > 2 * LENS_SCALE:
        return 0, 0, False
    xx, yy, xy = (x * x) >> 26, (y * y) >> 26, (x * y) >> 26
    r2 = xx + yy
    inner = hw["K1_Q26"] + ((hw["K2_Q26"] * r2) >> 26)
    radial = LENS_SCALE + ((r2 * inner) >> 26)
    tx = ((hw["P1_Q26"] * (2 * xy)) >> 26) + ((hw["P2_Q26"] * (r2 + 2 * xx)) >> 26)
    ty = ((hw["P1_Q26"] * (r2 + 2 * yy)) >> 26) + ((hw["P2_Q26"] * (2 * xy)) >> 26)
    xd, yd = ((x * radial) >> 26) + tx, ((y * radial) >> 26) + ty
    sx = ((xd * hw["FX_Q16"]) + (hw["CX_Q16"] << 26)) >> 34
    sy = ((yd * hw["FY_Q16"]) + (hw["CY_Q16"] << 26)) >> 34
    return sx, sy, True


def map_lens_fixed(profile, u_q8, v_q8, enabled=True, in_error=False):
    """Bit-exact Q26 model; shifts round negative values toward minus infinity."""
    if in_error:
        return 0, 0, False
    return _map_hardware(profile.to_hardware(), u_q8, v_q8, enabled, in_error)


def _render_arguments(image, profile, H, output_size, method):
    validate_image(image)
    if (image.shape[1], image.shape[0]) != (profile.width, profile.height):
        raise ValueError("Source image dimensions do not match calibration; implicit resize/crop is forbidden")
    if method not in ("bilinear", "nearest"):
        raise ValueError("method must be nearest or bilinear")
    h = np.eye(3) if H is None else np.asarray(H, dtype=np.float64)
    if h.shape != (3, 3) or not np.isfinite(h).all():
        raise ValueError("H must be a finite 3 by 3 destination-to-ideal-source matrix")
    size = (profile.width, profile.height) if output_size is None else tuple(output_size)
    if len(size) != 2 or any(isinstance(value, bool) or not isinstance(value, Integral) or not 2 <= value <= 4096 for value in size):
        raise ValueError("output_size requires integer width, height in 2..4096")
    return h, int(size[0]), int(size[1])


def _sample_float_array(image, sx, sy, valid, method):
    height, width = image.shape[:2]
    out = np.zeros(sx.shape + (3,), dtype=np.uint8)
    if method == "nearest":
        inside = valid & (sx >= -.5) & (sy >= -.5) & (sx < width - .5) & (sy < height - .5)
        x = np.floor(sx[inside] + .5).astype(np.int64)
        y = np.floor(sy[inside] + .5).astype(np.int64)
        out[inside] = image[y, x]
        return out
    inside = valid & (sx >= -1e-9) & (sy >= -1e-9) & (sx <= width - 1 + 1e-9) & (sy <= height - 1 + 1e-9)
    x, y = np.clip(sx[inside], 0, width - 1), np.clip(sy[inside], 0, height - 1)
    x0, y0 = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64)
    x1, y1 = np.minimum(x0 + 1, width - 1), np.minimum(y0 + 1, height - 1)
    fx, fy = (x - x0)[:, None], (y - y0)[:, None]
    top = image[y0, x0].astype(float) * (1. - fx) + image[y0, x1] * fx
    bottom = image[y1, x0].astype(float) * (1. - fx) + image[y1, x1] * fx
    out[inside] = np.clip(np.floor(top * (1. - fy) + bottom * fy + 1e-9), 0, 255).astype(np.uint8)
    return out


def render_lens_float(image, profile, H=None, output_size=None, method="bilinear"):
    """Compose H and lens coordinates, then sample the original RGB image once."""
    h, width, height = _render_arguments(image, profile, H, output_size, method)
    result = np.zeros((height, width, 3), dtype=np.uint8)
    for first in range(0, height, 64):
        xx, yy = np.meshgrid(np.arange(width, dtype=float), np.arange(first, min(first + 64, height), dtype=float))
        d = h[2, 0] * xx + h[2, 1] * yy + h[2, 2]
        with np.errstate(divide="ignore", invalid="ignore", over="ignore"):
            u = (h[0, 0] * xx + h[0, 1] * yy + h[0, 2]) / d
            v = (h[1, 0] * xx + h[1, 1] * yy + h[1, 2]) / d
        sx, sy, valid = map_lens_float(profile, u, v)
        valid &= np.isfinite(d) & (d > 1. / 16.)
        result[first:first + len(yy)] = _sample_float_array(image, sx, sy, valid, method)
    return result


def _homography_fixed(h):
    # Match the existing Q24 homography coordinate stage. Each coefficient is
    # explicitly quantized; no perspective solve or marker inference occurs.
    result = []
    for value in h.ravel():
        scaled = float(value) * H_SCALE
        if not math.isfinite(scaled) or not -(1 << 39) <= scaled < (1 << 39):
            raise ValueError("H coefficient exceeds signed 40-bit Q24 range")
        q = int(math.copysign(math.floor(abs(scaled) + .5), scaled))
        if not -(1 << 39) <= q < (1 << 39):
            raise ValueError("H coefficient exceeds signed 40-bit Q24 range")
        result.append(q)
    return result


def render_lens_fixed(image, profile, H=None, output_size=None, method="bilinear", enabled=True):
    """Compose Q24 H, Q26 lens and the existing Q8 cache/bilinear model.

    This scalar integer implementation is a correctness reference, not a PC
    throughput claim. Invalid H/lens geometry and outside samples become black.
    """
    h, width, height = _render_arguments(image, profile, H, output_size, method)
    coefficients, hw = _homography_fixed(h), profile.to_hardware()
    result = np.zeros((height, width, 3), dtype=np.uint8)
    for y in range(height):
        for x in range(width):
            u, v, valid = map_fixed(coefficients, x, y)
            if valid:
                sx, sy, valid = _map_hardware(hw, u, v, enabled)
                if valid:
                    result[y, x] = sample_fixed(image, sx, sy, method)
    return result
