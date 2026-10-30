"""Count real B fixed-point sample addresses, without claiming board latency."""
from pathlib import Path
from collections import OrderedDict
import json
import sys
import numpy as np

D = Path(__file__).resolve().parent
BASE = D.parent / "ddr_camera_black_20261014"
sys.path.insert(0, str(BASE / "b_algorithm/python"))
from brect.fixed import solve_fixed


def addresses():
    config = json.loads((BASE / "config.json").read_text(encoding="utf-8"))
    sw, sh = config["source"]
    ow, oh = config["output"]
    h = solve_fixed(config["fixture_points"], ow, oh, sw, sh)
    yy, xx = np.mgrid[:oh, :ow].astype(np.int64)
    den = h[6]*xx + h[7]*yy + h[8]
    qx = (h[0]*xx+h[1]*yy+h[2])*256//den
    qy = (h[3]*xx+h[4]*yy+h[5])*256//den
    x0, y0 = qx>>8, qy>>8
    x1, y1 = np.minimum(x0+1, sw-1), np.minimum(y0+1, sh-1)
    samples = np.stack([y0*sw+x0, y0*sw+x1, y1*sw+x0, y1*sw+x1], axis=-1).ravel()
    roi = []
    for lo, hi in config["rois"].values():
        for y in range(lo[1], hi[1]+1):
            roi.extend(range(y*sw+lo[0], y*sw+hi[0]+1))
    return samples, np.asarray(roi, np.int64), sw*sh


def lru(trace, entries):
    cache = OrderedDict()
    misses = 0
    for tag in trace:
        tag = int(tag)
        if tag in cache:
            cache.move_to_end(tag)
        else:
            misses += 1
            cache[tag] = None
            if len(cache) > entries:
                cache.popitem(last=False)
    return misses


def set_lru(trace, bits, ways=2):
    sets = [OrderedDict() for _ in range(1<<bits)]
    misses = 0
    for tag in trace:
        tag = int(tag)
        cache = sets[tag & ((1<<bits)-1)]
        if tag in cache:
            cache.move_to_end(tag)
        else:
            misses += 1
            cache[tag] = None
            if len(cache) > ways:
                cache.popitem(last=False)
    return misses


def main():
    samples, roi, size = addresses()
    full = np.concatenate([np.arange(size), samples])>>3
    reduced = np.concatenate([roi, samples])>>3
    result = {"synthetic": True, "board_latency_measured": False,
              "sample_requests": int(samples.size), "roi_pixels": int(roi.size),
              "full_scan_pixels": size, "old_two_entry_full_scan_reads": lru(full, 2),
              "roi_scan_cache_reads": {}}
    for n in [2, 4, 8, 16]:
        result["roi_scan_cache_reads"][f"fully_associative_{n}"] = lru(reduced, n)
    for n in [3, 4, 5, 6, 7, 8]:
        result["roi_scan_cache_reads"][f"two_way_{1<<n}_sets"] = set_lru(reduced, n)
    (D/"cache_profile.json").write_text(json.dumps(result, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
