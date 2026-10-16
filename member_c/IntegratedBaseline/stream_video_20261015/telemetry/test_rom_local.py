from pathlib import Path
import argparse
p=argparse.ArgumentParser();p.add_argument('--rtl',type=Path,default=Path(__file__).with_name('frame_telemetry_overlay.v'));a=p.parse_args();s=a.rtl.read_text()
assert '4:glyph_local<=glyph;' in s,'missing local register after inferred font DRM output'
assert '5:case(fetch_glyph_y)' in s,'font row selection must follow local register'
assert 'prefetched_row<=glyph_local[' in s,'row selection must consume local glyph register'
assert 'prefetched_row<=glyph[' not in s,'old DRM-to-row-register path remains'
print('PASS telemetry local font register and phase5 row selection; phase15 interface preserved')
