"""Move only the cache lookup decision tails into the existing miss start edge.

The source RTL is never edited. transform() rejects an unexpected version;
the command line writes a new directory with the generated RTL and review diff.
"""
from pathlib import Path
import argparse
import difflib
import hashlib
import json


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def transform(text):
    def replace(old, new, count=1):
        nonlocal text
        if text.count(old) != count:
            raise ValueError('Unexpected cache version at: ' + old)
        text = text.replace(old, new)

    replace('reg l_valid,l_inside,l_missing,l_relookup,l_boundary,l_victim_found;',
            'reg l_valid,l_inside,l_missing,l_relookup,l_boundary;')
    replace('reg[WB-1:0]l_victim;reg[75:0]l_miss_tag;',
            '''// Preserve lookup-time protection, replacement pointer and corner.
 // Only misses consume the registered decision tails at fill_start.
 reg[LINES-1:0]l_protected_ways;reg[WB-1:0]l_replace_way;
 reg[1:0]l_miss_corner;
 reg[WB-1:0]l_victim;reg l_victim_found;''')
    replace(' reg victim_found;reg[WB-1:0]victim;\n', '')
    replace('integer p,w,v;', 'integer p,w;')
    replace('''  victim_found=0;victim=replace_way;
  // At most four distinct ways are protected by a quad; five candidates
  // suffice and keep the replacement chain bounded independently of LINES.
  for(v=0;v<5;v=v+1)if(!victim_found&&!protected_ways[(replace_way+v)%LINES])begin victim=(replace_way+v)%LINES;victim_found=1;end
''', '')
    replace(' wire l_advance=', ''' // The same five candidates and their order use the lookup-time snapshot.
 // This chain no longer follows the live tag comparisons in one UI cycle.
 integer lv;
 always @*begin
  l_victim_found=0;l_victim=l_replace_way;
  for(lv=0;lv<5;lv=lv+1)if(!l_victim_found&&!l_protected_ways[(l_replace_way+lv)%LINES])begin l_victim=(l_replace_way+lv)%LINES;l_victim_found=1;end
 end
 wire[75:0]l_selected_miss_tag={l_generation,l_base,
  (l_miss_corner[1]?l_y1[11:2]:l_y[11:2]),
  (l_miss_corner[0]?l_x1[11:6]:l_x[11:6])};
 wire l_advance=''')
    replace('l_boundary<=0;l_victim_found<=0;', 'l_boundary<=0;')
    replace('l_victim<=0;l_miss_tag<=0;',
            'l_protected_ways<=0;l_replace_way<=0;l_miss_corner<=0;')
    replace('l_victim<=victim;l_victim_found<=victim_found;l_miss_tag<=key[missing_corner];',
            'l_protected_ways<=protected_ways;l_replace_way<=replace_way;l_miss_corner<=missing_corner;', count=2)
    replace('fill_tag<=l_miss_tag;', 'fill_tag<=l_selected_miss_tag;')
    return text


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    source = args.source.resolve()
    out = args.output.resolve()
    before = source.read_text()
    after = transform(before)
    source_hash = sha(source)
    out.mkdir(parents=True, exist_ok=False)
    generated = out/source.name
    generated.write_text(after)
    (out/'rtl.diff').write_text(''.join(difflib.unified_diff(
        before.splitlines(keepends=True), after.splitlines(keepends=True),
        fromfile=str(source), tofile=str(generated))))
    (out/'source_binding.json').write_text(json.dumps({
        'source': str(source), 'source_sha256': source_hash,
        'generated': str(generated), 'generated_sha256': sha(generated),
        'transform_sha256': sha(Path(__file__)),
        'physical_timing_qualified': False, 'hardware_acceptance': False,
    }, indent=2)+'\n')
    if sha(source) != source_hash:
        raise RuntimeError('Source changed concurrently')
    print(generated)


if __name__ == '__main__':
    main()
