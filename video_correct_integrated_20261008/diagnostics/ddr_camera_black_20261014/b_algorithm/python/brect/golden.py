"""Independent float golden model. RGB888; no OpenCV transform functions."""
import numpy as np

CORNERS = ("TL", "TR", "BR", "BL")
DEFAULT_THRESHOLDS = {"black": ((0, 0, 0), (64, 64, 64))}


def integer_bounds(value, shape, name):
    """Configuration uses integer pixel/channel bounds, never rounded floats."""
    try:
        bounds = np.asarray(value)
    except (TypeError, ValueError) as error:
        raise ValueError(f"{name} must contain integer bounds with shape {shape}") from error
    if bounds.shape != shape or not np.issubdtype(bounds.dtype, np.integer):
        raise ValueError(f"{name} must contain integer bounds with shape {shape}")
    return bounds


def marker_rois(width, height, rois=None):
    """Return validated inclusive rectangles in fixed TL,TR,BR,BL order."""
    if rois is None:
        mx, my = width // 2, height // 2
        rois = {"TL": ((0, 0), (mx-1, my-1)),
                "TR": ((mx, 0), (width-1, my-1)),
                "BR": ((mx, my), (width-1, height-1)),
                "BL": ((0, my), (mx-1, height-1))}
    if not isinstance(rois, dict) or set(rois) != set(CORNERS):
        raise ValueError("ROIs must contain exactly TL, TR, BR, BL")
    rectangles = []
    for name in CORNERS:
        bounds = integer_bounds(rois[name], (2, 2), f"ROI {name}")
        lo, hi = bounds
        if np.any(lo < 0) or np.any(lo > hi) or hi[0] >= width or hi[1] >= height:
            raise ValueError(f"ROI {name} must be a nonempty inclusive rectangle inside the source image")
        xmin, ymin = map(int, lo)
        xmax, ymax = map(int, hi)
        for ax, ay, bx, by in rectangles:
            if xmin <= bx and ax <= xmax and ymin <= by and ay <= ymax:
                raise ValueError("Marker ROIs must not overlap, including their boundary pixels")
        rectangles.append((xmin, ymin, xmax, ymax))
    return rectangles


def validate_image(image):
    if not isinstance(image, np.ndarray) or image.dtype != np.uint8 or image.ndim != 3 or image.shape[2] != 3:
        raise ValueError("Expected uint8 RGB image")
    if not 2 <= image.shape[0] <= 4096 or not 2 <= image.shape[1] <= 4096:
        raise ValueError("Source dimensions must be 2..4096")


def validate_points(points, min_cross=16):
    p = np.asarray(points, dtype=np.float64)
    if p.shape != (4, 2) or not np.isfinite(p).all():
        raise ValueError("Four finite TL,TR,BR,BL points required")
    edges = np.roll(p, -1, axis=0) - p
    cross = edges[:, 0] * np.roll(edges, -1, axis=0)[:, 1] - edges[:, 1] * np.roll(edges, -1, axis=0)[:, 0]
    if np.any(cross < min_cross):
        raise ValueError("Corners must form a sufficiently large clockwise convex quadrilateral in image coordinates")
    return p


def detect_markers(image, thresholds=None, min_pixels=16, max_pixels=4096, max_span=128, rois=None):
    """Black RGB threshold + centroid in four disjoint spatial search windows.

    Bounds are inclusive; centroids round to nearest integer, ties up.
    Default windows are quadrants. Black text inside a window also contributes:
    use tight custom windows when other black objects appear in the image.
    """
    validate_image(image)
    th = DEFAULT_THRESHOLDS if thresholds is None else thresholds
    if not isinstance(th, dict) or set(th) != {"black"}:
        raise ValueError('Thresholds must contain exactly "black": [[Rmin,Gmin,Bmin],[Rmax,Gmax,Bmax]]')
    lo, hi = integer_bounds(th["black"], (2, 3), "Black RGB threshold")
    if np.any(lo < 0) or np.any(hi > 255) or np.any(lo > hi):
        raise ValueError("Black thresholds must be inclusive bounds in 0..255")
    for name, value in (("min_pixels", min_pixels), ("max_pixels", max_pixels), ("max_span", max_span)):
        if isinstance(value, bool) or not isinstance(value, (int, np.integer)):
            raise ValueError(f"{name} must be an integer")
    if not 1 <= min_pixels <= max_pixels <= 16777216 or not 0 <= max_span <= 4095:
        raise ValueError("Require 1 <= MIN_PIXELS <= MAX_PIXELS <= 16777216 and 0 <= MAX_SPAN <= 4095")
    height, width = image.shape[:2]
    rectangles = marker_rois(width, height, rois)
    points, stats = [], {}
    good = True
    for name, (xmin, ymin, xmax, ymax) in zip(CORNERS, rectangles):
        region = image[ymin:ymax+1, xmin:xmax+1]
        black = np.all((region >= lo) & (region <= hi), axis=2)
        yy, xx = np.nonzero(black)
        xx, yy = xx + xmin, yy + ymin
        n = len(xx)
        span = (int(np.ptp(xx)), int(np.ptp(yy))) if n else (0, 0)
        stats[name] = {"count": n, "span": span, "roi": [[xmin, ymin], [xmax, ymax]]}
        if not min_pixels <= n <= max_pixels or max(span) > max_span:
            good = False
        if n:
            centroid = ((int(xx.sum()) + n // 2) // n, (int(yy.sum()) + n // 2) // n)
            points.append(centroid)
            stats[name]["centroid"] = centroid
    if not good:
        return None, stats
    try:
        validate_points(points)
    except ValueError:
        return None, stats
    return np.asarray(points, dtype=np.int64), stats


def homography(points, out_w, out_h):
    """Solve an 8x8 system, mapping output pixel centers to source corners."""
    p = validate_points(points)
    if not 2 <= out_w <= 4096 or not 2 <= out_h <= 4096:
        raise ValueError("Output dimensions must be 2..4096")
    dst = [(0, 0), (out_w - 1, 0), (out_w - 1, out_h - 1), (0, out_h - 1)]
    a, b = [], []
    for (x, y), (u, v) in zip(dst, p):
        a.extend([[x, y, 1, 0, 0, 0, -u*x, -u*y], [0, 0, 0, x, y, 1, -v*x, -v*y]])
        b.extend([u, v])
    h = np.r_[np.linalg.solve(np.asarray(a, float), b), 1.0].reshape(3, 3)
    if not np.isfinite(h).all():
        raise ValueError("Non-finite homography")
    return h


def map_float(h, x, y):
    d = h[2, 0]*x + h[2, 1]*y + h[2, 2]
    if not np.isfinite(d) or d <= 1/16:
        return 0.0, 0.0, False
    return (h[0, 0]*x + h[0, 1]*y + h[0, 2])/d, (h[1, 0]*x + h[1, 1]*y + h[1, 2])/d, True


def sample_float(image, x, y, method="bilinear"):
    height, width = image.shape[:2]
    if method == "nearest":
        ix, iy = int(np.floor(x + .5)), int(np.floor(y + .5))
        return image[iy, ix] if 0 <= ix < width and 0 <= iy < height else np.zeros(3, np.uint8)
    if method != "bilinear":
        raise ValueError("method must be nearest or bilinear")
    # Tiny tolerance only for floating-point corner roundoff.
    if not -1e-9 <= x <= width-1+1e-9 or not -1e-9 <= y <= height-1+1e-9:
        return np.zeros(3, np.uint8)
    x, y = np.clip(x, 0, width-1), np.clip(y, 0, height-1)
    x0, y0 = int(np.floor(x)), int(np.floor(y))
    x1, y1 = min(x0+1, width-1), min(y0+1, height-1)
    fx, fy = x-x0, y-y0
    top = image[y0, x0].astype(float)*(1-fx) + image[y0, x1]*fx
    bot = image[y1, x0].astype(float)*(1-fx) + image[y1, x1]*fx
    return np.clip(np.floor(top*(1-fy)+bot*fy+1e-9), 0, 255).astype(np.uint8)


def rectify_float(image, points, out_w, out_h, method="bilinear"):
    validate_image(image)
    if method not in ("nearest", "bilinear"):
        raise ValueError("method must be nearest or bilinear")
    h = homography(points, out_w, out_h)
    result = np.zeros((out_h, out_w, 3), dtype=np.uint8)
    for y in range(out_h):
        for x in range(out_w):
            sx, sy, valid = map_float(h, x, y)
            if valid:
                result[y, x] = sample_float(image, sx, sy, method)
    return result, h
