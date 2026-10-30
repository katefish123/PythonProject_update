"""Build a center-rotation affine command. Serial access occurs only with --port.

All matrices map destination pixels to the ideal (undistorted) source plane.
The optional base matrix binds B's independently verified lens-safe viewport.
"""
from __future__ import annotations
import argparse
import binascii
import json
import math
import hashlib
import re
from pathlib import Path
import struct
import sys
import time

Q = 1 << 24
MAGIC = b"\xa5\x5a"
DEFAULT_CANDIDATE = Path(__file__).resolve().parents[1]/"candidate_host_angle_v2_product_stage"


def crc16(data: bytes) -> int:
    return binascii.crc_hqx(data, 0xFFFF)


def encode_packet(sequence: int, coefficients: list[int]) -> bytes:
    if not 0 <= sequence <= 65535 or len(coefficients) != 6:
        raise ValueError("Need sequence0..65535 and six coefficients")
    if any(not -(1 << 39) <= n < (1 << 39) for n in coefficients):
        raise ValueError("Coefficient exceeds signed40/Q24")
    payload = b"\x01" + struct.pack("<H", sequence) + b"\x00"
    payload += b"".join((n & ((1 << 40) - 1)).to_bytes(5, "little") for n in coefficients)
    return MAGIC + payload + struct.pack("<H", crc16(payload))


def encode_ack(sequence: int) -> bytes:
    payload = b"\x81" + struct.pack("<H", sequence) + b"\x00"
    return MAGIC + payload + struct.pack("<H", crc16(payload))


def read_base(path: Path | None) -> list[list[float]]:
    if path is None:
        return [[1., 0., 0.], [0., 1., 0.], [0., 0., 1.]]
    obj = json.loads(path.read_text(encoding="utf-8-sig"))
    matrix = obj.get("H", obj.get("matrix")) if isinstance(obj, dict) else obj
    if not isinstance(matrix, list) or len(matrix) != 3 or any(len(row) != 3 for row in matrix):
        raise ValueError("Base JSON must contain3x3 H or matrix")
    matrix = [[float(x) for x in row] for row in matrix]
    if not all(math.isfinite(x) for row in matrix for x in row):
        raise ValueError("Base coefficients must be finite")
    if abs(matrix[2][0]) > 1e-12 or abs(matrix[2][1]) > 1e-12 or matrix[2][2] == 0:
        raise ValueError("Only affine base matrices with fixed bottom row are supported")
    k = matrix[2][2]
    matrix = [[v / k for v in row] for row in matrix]
    if abs(matrix[0][0]*matrix[1][1]-matrix[0][1]*matrix[1][0]) < 1e-12:
        raise ValueError("Base affine matrix must be invertible")
    return matrix


def affine_for_angle(angle_deg: float, zoom: float, width: int = 1920,
                     height: int = 1080, center_x: float | None = None,
                     center_y: float | None = None,
                     base: list[list[float]] | None = None,
                     safe_crop: bool = True) -> dict:
    if width < 2 or height < 2 or not math.isfinite(angle_deg) or not math.isfinite(zoom) or zoom <= 0:
        raise ValueError("Need finite angle, positive zoom and dimensions>=2")
    hx, hy = (width - 1) / 2, (height - 1) / 2
    cx, cy = hx if center_x is None else center_x, hy if center_y is None else center_y
    if not all(math.isfinite(v) for v in [cx, cy]) or not 0 < cx < width - 1 or not 0 < cy < height - 1:
        raise ValueError("Rotation center must lie strictly inside the ideal viewport")
    c, s = math.cos(math.radians(angle_deg)), math.sin(math.radians(angle_deg))
    mx, my = min(cx, width - 1 - cx), min(cy, height - 1 - cy)
    # Slight guard covers all fixed-point coefficient rounding at the corners.
    guard = (width + height) / Q
    required_zoom = max((abs(c) * hx + abs(s) * hy) / (mx - guard),
                        (abs(s) * hx + abs(c) * hy) / (my - guard)) if safe_crop else zoom
    applied_zoom = max(zoom, required_zoom)
    r = [[c / applied_zoom, s / applied_zoom, cx - (c * hx + s * hy) / applied_zoom],
         [-s / applied_zoom, c / applied_zoom, cy - (-s * hx + c * hy) / applied_zoom],
         [0., 0., 1.]]
    base = base or [[1., 0., 0.], [0., 1., 0.], [0., 0., 1.]]
    h = [[sum(base[i][k] * r[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    coeff = [round(h[i][j] * Q) for i in range(2) for j in range(3)]
    if coeff[0]*coeff[4]-coeff[1]*coeff[3] == 0:
        raise ValueError("Affine matrix becomes singular after Q24 quantization")
    encode_packet(0, coeff)  # Enforce exact hardware range before any serial access.
    return {"angle_deg_clockwise_display": angle_deg, "requested_zoom": zoom,
            "applied_zoom": applied_zoom, "automatic_safe_crop": safe_crop,
            "rotation_center": [cx, cy], "resolution": [width, height],
            "matrix": [[coeff[i * 3 + j] / Q for j in range(3)] for i in range(2)] + [[0, 0, 1]],
            "coefficients_q24": coeff,
            "safety_scope": "Rotation footprint stays inside base-input viewport; actual lens-safe coverage depends on separately validated base matrix."}


def plan_lens_viewport(result: dict, calibration: Path, no_autocrop: bool) -> dict:
    """Reuse the exact existing B integer/float complete-grid coverage planner."""
    import hashlib
    deps = Path("C:/D/FPGA/A_software_20261024/deps")
    reference = Path("C:/D/FPGA/A_software_20261024/reference/B_lens_v2/python")
    for p in [deps, reference]:
        if str(p) not in sys.path:
            sys.path.insert(0, str(p))
    from brect.calibration import load_calibration
    from brect.viewport import plan_viewport
    profile = load_calibration(calibration, tuple(result["resolution"]))
    requested = result["matrix"]
    result["requested_matrix"] = requested
    # Near-horizontal rotation otherwise nearly fills a128x128 source-cache
    # footprint. A modest zoom bounds that footprint and avoids cache churn.
    # Keep0/180degree axis-aligned views on the proven uncropped raster path.
    cross = max(abs(requested[0][1]), abs(requested[1][0]))
    diagonal = max(abs(requested[0][0]), abs(requested[1][1]))
    locality_zoom = 1.2 if cross > .5/Q and cross < .18*diagonal and not no_autocrop else 1.
    factor = max(1., locality_zoom/result['applied_zoom'])
    if factor > 1:
        width,height=result['resolution'];s=1/factor
        crop=[[s,0,(width-1)/2*(1-s)],[0,s,(height-1)/2*(1-s)],[0,0,1]]
        requested=[[sum(requested[i][k]*crop[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
        result['applied_zoom']*=factor
    result.update(memory_locality_minimum_zoom=locality_zoom,extra_zoom_for_memory_locality=factor)
    if no_autocrop:
        result.update(automatic_safe_crop=False,
                      safety_scope="Explicit --no-autocrop: source-unavailable pixels may be filled black; no full-grid coverage claim.")
    else:
        effective, report = plan_viewport(profile, H=requested, output_size=tuple(result["resolution"]))
        q = report["H_q24"]
        if q[6:] != [0, 0, Q]:
            raise ValueError("Lens viewport returned a non-affine matrix")
        result.update(matrix=[[q[i*3+j]/Q for j in range(3)] for i in range(2)]+[[0,0,1]],
                      coefficients_q24=q[:6], viewport_report=report, automatic_safe_crop=True,
                      pre_viewport_zoom=result['applied_zoom'],
                      applied_zoom=result['applied_zoom']*report['zoom'],
                      safety_scope="B viewport checked every output center with float and exact quantized H/lens arithmetic; valid only for bound trial calibration and this matrix.")
    result.update(calibration=str(calibration.resolve()),
                  calibration_sha256=hashlib.sha256(calibration.read_bytes()).hexdigest(),
                  viewport_reference=str(reference / "brect/viewport.py"),
                  viewport_reference_sha256=hashlib.sha256((reference/"brect/viewport.py").read_bytes()).hexdigest())
    return result


def hardware_binding(calibration: Path, candidate: Path, size: list[int]) -> dict:
    """Compare the actual compile-time lens constants, not a profile filename."""
    from brect.calibration import load_calibration
    source = candidate / "sources/lens_affine_instance.v"
    expected = load_calibration(calibration, tuple(size)).to_hardware()
    text = source.read_text(encoding="utf-8")
    actual = {}
    for key in expected:
        values = re.findall(r"\." + key + r"\(32'sh([0-9a-fA-F]{8})\)", text)
        if len(values) != 1:
            raise ValueError(f"Cannot bind exactly one RTL value for {key}")
        value = int(values[0], 16)
        actual[key] = value - (1 << 32) if value >= (1 << 31) else value
    differences = {key: {"host": expected[key], "rtl": actual[key]}
                   for key in expected if expected[key] != actual[key]}
    return {"candidate": str(candidate.resolve()), "source": str(source.resolve()),
            "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "hardware_params": actual, "resolution": [1920, 1080],
            "compatible": not differences and size == [1920, 1080],
            "differences": differences,
            "scope": "Matches source constants; this does not identify the program currently loaded on the board."}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--angle-deg", type=float, default=0)
    ap.add_argument("--zoom", type=float, default=1)
    ap.add_argument("--width", type=int, default=1920)
    ap.add_argument("--height", type=int, default=1080)
    ap.add_argument("--center-x", type=float)
    ap.add_argument("--center-y", type=float)
    ap.add_argument("--sequence", type=int, default=1)
    ap.add_argument("--base-matrix-json", type=Path)
    ap.add_argument("--calibration", type=Path, default=Path(__file__).resolve().parents[1]/"calibration/r50_18mm_hdmi_trial.json")
    ap.add_argument("--hardware-candidate", type=Path,
                    default=DEFAULT_CANDIDATE)
    ap.add_argument("--no-autocrop", action="store_true", help="Allow unavailable edge pixels; no lens-safe coverage guarantee")
    ap.add_argument("--dry-run", action="store_true", help="Generate packet/matrix without importing serial")
    ap.add_argument("--output", type=Path, help="JSON output; sibling.bin contains exact command")
    ap.add_argument("--port", help="Explicit COM port; omit for offline-only generation")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--timeout", type=float, default=3)
    a = ap.parse_args()
    try:
        result = affine_for_angle(a.angle_deg, a.zoom, a.width, a.height, a.center_x,
                                  a.center_y, read_base(a.base_matrix_json), safe_crop=False)
        result = plan_lens_viewport(result, a.calibration, a.no_autocrop)
        result["hardware_binding"] = hardware_binding(a.calibration, a.hardware_candidate, result["resolution"])
        if a.port and not a.dry_run and not result["hardware_binding"]["compatible"]:
            raise ValueError("Host calibration/resolution differs from the candidate RTL. Rebuild the matching lens binding before sending.")
        packet = encode_packet(a.sequence, result["coefficients_q24"])
        ack = encode_ack(a.sequence)
    except (ValueError, TypeError, OverflowError) as e:
        ap.error(str(e))
    result.update(sequence=a.sequence, packet_hex=packet.hex(), expected_ack_hex=ack.hex(),
                  packet_bytes=len(packet), serial_accessed=False,
                  protocol="lens-affine-uart-v1/CRC16-CCITT-FALSE")
    if a.port and not a.dry_run:
        # A COM port is never selected automatically. Host CRC/ACK checks refer
        # to actual frame commit, not merely reception of the command bytes.
        import serial
        with serial.Serial(a.port, a.baud, timeout=.05, write_timeout=a.timeout) as link:
            link.reset_input_buffer()
            link.write(packet)
            link.flush()
            received = bytearray()
            deadline = time.monotonic() + a.timeout
            while time.monotonic() < deadline and ack not in received:
                received.extend(link.read(64))
            if ack not in received:
                raise SystemExit("No matching committed-frame ACK before timeout")
        result.update(serial_accessed=True, committed_ack=True)
    if a.output:
        a.output.parent.mkdir(parents=True, exist_ok=True)
        a.output.write_text(json.dumps(result, indent=2), encoding="utf-8")
        a.output.with_suffix(".bin").write_bytes(packet)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
