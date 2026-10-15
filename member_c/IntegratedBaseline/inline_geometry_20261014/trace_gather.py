"""Replay complete B coordinate traces against candidate processor caches.

This measures command locality only, not cycle throughput or hardware speed.
The existing native UI cache/prefetch, arbitration and DDR stalls are excluded.
"""
import argparse, hashlib, json, sys
from collections import OrderedDict
from pathlib import Path
import numpy as np


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    binding = json.loads((a.root/'reproduction_manifest.json').read_text())['files']
    for name in ['fullhd_tests/fixture.json', 'fullhd_tests/reference/brect/fixed.py']:
        if hashlib.sha256((a.root/name).read_bytes()).hexdigest() != binding[name]['local_sha256']:
            raise RuntimeError('Trace reference changed: '+name)
    sys.path.insert(0, str(a.root/'fullhd_tests/reference'))
    from brect.fixed import map_fixed
    fixture = json.loads((a.root/'fullhd_tests/fixture.json').read_text())
    sw, sh = fixture['configuration']['source']
    ow, oh = fixture['configuration']['output']
    yy, xx = np.mgrid[:oh,:ow].astype(np.int64)
    results = []
    for frame in fixture['frames']:
        h = frame['H_q']
        den = h[6]*xx+h[7]*yy+h[8]
        qx = (h[0]*xx+h[1]*yy+h[2])*256//den
        qy = (h[3]*xx+h[4]*yy+h[5])*256//den
        x0, y0 = qx>>8, qy>>8
        if not ((den>2**20).all() and (x0>=0).all() and (x0<sw).all() and (y0>=0).all() and (y0<sh).all()):
            raise RuntimeError('Trace outside valid B geometry')
        x1, y1 = np.minimum(x0+1,sw-1), np.minimum(y0+1,sh-1)
        addresses = np.stack([y0*sw+x0,y0*sw+x1,y1*sw+x0,y1*sw+x1],axis=-1).reshape(-1,4)
        for index in [0,ow-1,ow*(oh-1),ow*oh-1,*range(0,ow*oh,10007)]:
            x, y = index%ow,index//ow
            sx, sy, valid = map_fixed(h,x,y)
            if not valid or (sx,sy) != (int(qx[y,x]),int(qy[y,x])):
                raise RuntimeError('B scalar coordinate mismatch')
        # LRU2 reproduces current processor cache replacement and read order.
        # Larger policies retain the same eight-pixel line; no larger burst.
        lru2, lru4, sets = [], [], [[] for _ in range(128)]
        strip_sets = [[] for _ in range(128)]
        tile_sets = [[] for _ in range(32)]
        tile_lru = OrderedDict()
        tile_fifo = OrderedDict()
        misses_strip = misses_tile_set = misses_tile_lru = misses_tile_fifo = 0
        misses2 = misses4 = misses256 = deduplicated = four_line_pixels = 0
        if sw%64 or sh%4:
            raise RuntimeError('This prototype requires source aligned to 64x4 tiles')
        strip_tags = addresses>>6
        tile_tags = addresses//(sw*4)*(sw//64)+(addresses%sw)//64
        for row, strip_row, tile_row in zip(addresses>>3,strip_tags,tile_tags):
            tags = tuple(map(int,row))
            unique = tuple(dict.fromkeys(tags))
            deduplicated += len(unique)
            four_line_pixels += len(unique)==4
            for tag in tags:
                if tag in lru2:
                    lru2.remove(tag)
                else:
                    misses2 += 1
                    if len(lru2)==2:lru2.pop(0)
                lru2.append(tag)
                if tag in lru4:
                    lru4.remove(tag)
                else:
                    misses4 += 1
                    if len(lru4)==4:lru4.pop(0)
                lru4.append(tag)
                bucket = sets[tag%128]
                if tag in bucket:
                    bucket.remove(tag)
                else:
                    misses256 += 1
                    if len(bucket)==2:bucket.pop(0)
                bucket.append(tag)
            for tag in map(int,strip_row):
                bucket = strip_sets[tag%128]
                if tag in bucket:bucket.remove(tag)
                else:
                    misses_strip += 1
                    if len(bucket)==2:bucket.pop(0)
                bucket.append(tag)
            for tag in map(int,tile_row):
                bucket = tile_sets[tag%32]
                if tag in bucket:bucket.remove(tag)
                else:
                    misses_tile_set += 1
                    if len(bucket)==2:bucket.pop(0)
                bucket.append(tag)
                if tag in tile_lru:tile_lru.move_to_end(tag)
                else:
                    misses_tile_lru += 1
                    if len(tile_lru)==64:tile_lru.popitem(last=False)
                    tile_lru[tag] = None
                if tag not in tile_fifo:
                    misses_tile_fifo += 1
                    if len(tile_fifo)==64:tile_fifo.popitem(last=False)
                    tile_fifo[tag] = None
        results.append(dict(kind=frame['kind'], output_pixels=ow*oh,
                            pixel_read_requests=4*ow*oh,
                            per_pixel_unique_line_requests=deduplicated,
                            pixels_needing_four_distinct_lines=four_line_pixels,
                            lru2_line_misses=misses2,lru4_line_misses=misses4,
                            set128_way2_line_misses=misses256,
                            lru4_miss_reduction_percent=100*(misses2-misses4)/misses2,
                            set128_way2_miss_reduction_percent=100*(misses2-misses256)/misses2,
                            hypothetical_fill_bytes=dict(line8_set128_way2=32*misses256,
                                strip64_set128_way2=256*misses_strip,
                                tile64x4_set32_way2=1024*misses_tile_set,
                                tile64x4_fully_associative64=1024*misses_tile_lru,
                                tile64x4_fully_associative_fifo64=1024*misses_tile_fifo),
                            hypothetical_fill_commands=dict(line8_set128_way2=misses256,
                                strip64_set128_way2=misses_strip,
                                tile64x4_set32_way2=4*misses_tile_set,
                                tile64x4_fully_associative64=4*misses_tile_lru,
                                tile64x4_fully_associative_fifo64=4*misses_tile_fifo)))
    record = dict(evidence='full_result_coordinate_locality_trace_not_cycle_simulation',
                  hardware_accepted=False, source_size=[sw,sh],result_size=[ow,oh],
                  cache_line_pixels=8, cache_line_bytes=32,
                  larger_policy_data_bytes=dict(strip64_set128_way2=65536,
                      tile64x4_set32_way2=65536,tile64x4_fully_associative64=65536,
                      tile64x4_fully_associative_fifo64=65536),
                  policies_start_invalid_each_frame=True,
                  excluded=['native UI cache and prefetch','memory timing and arbitration',
                            'gather port conflicts','pipeline backpressure and clocks'],
                  results=results)
    a.output.write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps(record,indent=2))


if __name__ == '__main__':
    main()
