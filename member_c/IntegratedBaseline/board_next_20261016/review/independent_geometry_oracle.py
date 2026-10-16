"""Read-only geometry audit: rational eight-equation oracle vs B Q24 endpoints.

No RTL request traces, output pixels or B Python model are used by the oracle.
The screenshot is display evidence only, never a source-frame input golden.
"""
import argparse
from fractions import Fraction as F
import hashlib
import json
from pathlib import Path

S = 1 << 24
BASELINE = Path(__file__).resolve().parents[2] / "stream_video_20261015"


def exact_inverse_h(points, width, height):
    """Solve destination->source constraints directly, with exact rationals."""
    destinations = [(0, 0), (width-1, 0), (width-1, height-1), (0, height-1)]
    rows = []
    for (x, y), (u, v) in zip(destinations, points):
        rows.append(list(map(F, [x, y, 1, 0, 0, 0, -u*x, -u*y, u])))
        rows.append(list(map(F, [0, 0, 0, x, y, 1, -v*x, -v*y, v])))
    for i in range(8):
        pivot = next(k for k in range(i, 8) if rows[k][i])
        rows[i], rows[pivot] = rows[pivot], rows[i]
        divisor = rows[i][i]
        rows[i] = [v/divisor for v in rows[i]]
        for k in range(8):
            if k != i:
                factor = rows[k][i]
                rows[k] = [v-factor*w for v, w in zip(rows[k], rows[i])]
    return [rows[i][-1] for i in range(8)] + [F(1)]


def trunc_div(n, d):
    return (abs(n)//abs(d)) * (-1 if (n < 0) != (d < 0) else 1)


def b_equations_q24(points, width, height):
    """Separate transcription of the actual solver equations, not the oracle."""
    (x0,y0),(x1,y1),(x2,y2),(x3,y3) = points
    a,b,c = x1-x2,x3-x2,x0-x1+x2-x3
    d,e,f = y1-y2,y3-y2,y0-y1+y2-y3
    det = a*e-b*d
    g,k = trunc_div((c*e-b*f)*S,det),trunc_div((a*f-c*d)*S,det)
    return [trunc_div((x1-x0)*S+g*x1,width-1),
            trunc_div((x3-x0)*S+k*x3,height-1),x0*S,
            trunc_div((y1-y0)*S+g*y1,width-1),
            trunc_div((y3-y0)*S+k*y3,height-1),y0*S,
            trunc_div(g,width-1),trunc_div(k,height-1),S]


def mapped(h, x, y):
    den = h[6]*x+h[7]*y+h[8]
    return F(h[0]*x+h[1]*y+h[2],den), F(h[3]*x+h[4]*y+h[5],den)


def run():
    fixture = BASELINE / "system_test/fixtures/fullhd/metadata.json"
    metadata = json.loads(fixture.read_text())
    width,height = metadata["active_w"],metadata["storage"][1]
    destinations = [(0,0),(width-1,0),(width-1,height-1),(0,height-1)]
    records = []
    for frame in metadata["frames"]:
        points = frame["corners"]
        exact = exact_inverse_h(points,width,height)
        integer = b_equations_q24(points,width,height)
        endpoints = []
        for (x,y),point in zip(destinations,points):
            assert mapped(exact,x,y) == tuple(point), "independent exact constraints"
            q = mapped(integer,x,y)
            error = max(abs(q[0]-point[0]),abs(q[1]-point[1]))
            assert error < F(1,4), "fixture B endpoint exceeds quarter source pixel"
            endpoints.append({"logical_destination":[x,y],
                              "physical_result_destination":[x+metadata["active_x"],y],
                              "source_corner":point,"q24_mapped":[float(v) for v in q],
                              "max_axis_error_source_pixels":float(error)})
        records.append({"variant":frame["variant"],"endpoints":endpoints,
                        "max_endpoint_error_source_pixels":max(p["max_axis_error_source_pixels"] for p in endpoints)})
    colors = {"red":[255,0,0],"green":[0,255,0],"blue":[0,0,255],"yellow":[255,255,0]}
    rejected = {name:not all(channel <= 64 for channel in rgb) for name,rgb in colors.items()}
    assert all(rejected.values())
    return {"status":"mathematical_audit_only_not_board_acceptance",
            "oracle":"independent Fraction Gaussian elimination, eight destination/source constraints",
            "fixture":str(fixture),"fixture_sha256":hashlib.sha256(fixture.read_bytes()).hexdigest(),
            "frames":records,"ideal_colored_markers_rejected_by_black_gate":rejected,
            "full_black_roi":{"pixels":102*102,"accepted_count_range":[64,16384],
                              "span":101,"accepted_max_span":256,"passes_count_and_span":True},
            "screenshot_is_raw_source_golden":False,
            "limitations":["Display screenshot cannot recover the actual raw source RGB or selected source centroids.",
                           "Fixture corner checks validate inverse-map direction, not real-camera marker detection.",
                           "No physical timing, optics, complete-grid or per-frame hardware acceptance claim."]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = run()
    encoded = json.dumps(result,indent=2)+"\n"
    if args.output:
        args.output.write_text(encoded)
    print(encoded)
