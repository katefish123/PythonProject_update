"""Validated camera profiles and the shared compile-time hardware format."""
from dataclasses import dataclass, field
import copy
import json
import math
from numbers import Real
from pathlib import Path


def _finite(value, name):
    if isinstance(value, bool) or not isinstance(value, Real) or not math.isfinite(value):
        raise ValueError(f"{name} must be a finite number")
    return float(value)


def _dimension(value, name):
    result = _finite(value, name)
    if not result.is_integer() or not 1 <= result <= 4096:
        raise ValueError(f"{name} must be an integer in 1..4096")
    return int(result)


def _agree(a, b, name):
    if not math.isclose(a, b, rel_tol=1e-12, abs_tol=1e-12):
        raise ValueError(f"Inconsistent redundant calibration field: {name}")


def _quantize(value, fractional_bits, name):
    scaled = _finite(value, name) * (1 << fractional_bits)
    if not math.isfinite(scaled):
        raise ValueError(f"{name} is outside signed 32-bit hardware range")
    quantized = int(math.copysign(math.floor(abs(scaled) + .5), scaled))
    if not -(1 << 31) <= quantized < (1 << 31):
        raise ValueError(f"{name} is outside signed 32-bit hardware range")
    return quantized


@dataclass(frozen=True)
class CalibrationProfile:
    fx: float
    fy: float
    cx: float
    cy: float
    k1: float
    k2: float
    p1: float
    p2: float
    width: int
    height: int
    metadata: dict = field(default_factory=dict, compare=False)

    def to_hardware(self):
        """Round constants to nearest with ties away from zero; never wrap."""
        if _finite(self.fx, "fx") <= 0 or _finite(self.fy, "fy") <= 0:
            raise ValueError("fx and fy must be positive")
        result = {}
        for name in ("fx", "fy", "cx", "cy"):
            result[f"{name.upper()}_Q16"] = _quantize(getattr(self, name), 16, name)
        for name in ("fx", "fy"):
            key = f"INV_{name.upper()}_Q30"
            result[key] = _quantize(1. / getattr(self, name), 30, key)
            if result[key] == 0 or result[f"{name.upper()}_Q16"] <= 0:
                raise ValueError(f"{name} or its reciprocal rounds to zero")
        for name in ("k1", "k2", "p1", "p2"):
            value = _finite(getattr(self, name), name)
            if abs(value) > 2.:
                raise ValueError(f"{name} magnitude exceeds the hardware limit of 2")
            result[f"{name.upper()}_Q26"] = _quantize(value, 26, name)
        return result


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON field: {key}")
        result[key] = value
    return result


def _invalid_constant(value):
    raise ValueError(f"Non-finite JSON number: {value}")


def load_calibration(path, image_size=None):
    """Load nested ``model``/``video`` JSON without changing its pixel grid.

    ``image_size`` is (width, height), and must exactly match the profile.
    Deployment evidence and provisional status are retained in ``metadata``;
    software experiments do not imply approval for physical deployment.
    """
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"),
                          object_pairs_hook=_unique_object, parse_constant=_invalid_constant)
    except (json.JSONDecodeError, UnicodeError) as error:
        raise ValueError(f"Invalid calibration JSON: {error}") from error
    if not isinstance(data, dict) or not isinstance(data.get("model"), dict) or not isinstance(data.get("video"), dict):
        raise ValueError("Calibration requires model and video objects")
    model, video = data["model"], data["video"]
    try:
        width, height = (_dimension(video[key], f"video.{key}") for key in ("width", "height"))
        k = model["K"]
        if not isinstance(k, list) or len(k) != 3 or any(not isinstance(row, list) or len(row) != 3 for row in k):
            raise ValueError("model.K must be a 3 by 3 matrix")
        k = [[_finite(value, f"K[{row}][{col}]") for col, value in enumerate(values)] for row, values in enumerate(k)]
        if k[0][1] != 0 or k[1][0] != 0 or k[2] != [0., 0., 1.]:
            raise ValueError("model.K requires zero skew and last row [0,0,1]")
        values = dict(zip(("fx", "fy", "cx", "cy"), (k[0][0], k[1][1], k[0][2], k[1][2])))
        if values["fx"] <= 0 or values["fy"] <= 0:
            raise ValueError("fx and fy must be positive")
        for name, value in values.items():
            if name in model:
                _agree(_finite(model[name], name), value, name)
        distortion = model.get("distortion_opencv_order")
        if distortion is not None:
            if not isinstance(distortion, list) or len(distortion) not in (4, 5):
                raise ValueError("distortion_opencv_order must contain 4 or 5 numbers")
            distortion = [_finite(value, "distortion_opencv_order") for value in distortion]
            if len(distortion) == 5 and distortion[4] != 0:
                raise ValueError("Nonzero k3 is unsupported by the k1/k2/p1/p2 pipeline")
        for index, name in enumerate(("k1", "k2", "p1", "p2")):
            if distortion is None:
                values[name] = _finite(model[name], name)
            else:
                values[name] = distortion[index]
                if name in model:
                    _agree(_finite(model[name], name), values[name], name)
        for name in ("k3", "k3_fixed"):
            if name in model and _finite(model[name], name) != 0:
                raise ValueError("Nonzero k3 is unsupported by the k1/k2/p1/p2 pipeline")
    except KeyError as error:
        raise ValueError(f"Missing required calibration field: {error.args[0]}") from error
    if image_size is not None:
        try:
            requested = tuple(image_size)
            if len(requested) != 2:
                raise ValueError("image_size requires width and height")
            requested = tuple(_dimension(value, "image_size") for value in requested)
        except TypeError as error:
            raise ValueError("image_size requires width and height") from error
        if requested != (width, height):
            raise ValueError(f"Calibration size {width}x{height} does not match source {requested[0]}x{requested[1]}; implicit resize/crop is forbidden")
    metadata = copy.deepcopy({key: value for key, value in data.items() if key != "model"})
    return CalibrationProfile(**values, width=width, height=height, metadata=metadata)
