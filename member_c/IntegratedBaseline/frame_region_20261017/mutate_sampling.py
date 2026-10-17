"""Intentional regression controls, isolated test snapshots only."""
from pathlib import Path
import sys
name,directory=sys.argv[1:]
p=Path(directory).resolve()
assert p.parent.parent==Path('D:/FPGA/output').resolve() and p.name=='source_snapshot'
f=p/'region_sample.v';s=f.read_text()
mutations={
 'ignore_response_bank':('&&r_bank==cb',''),
 'skip_marker_cleanup':('.p00(clean_pixels[23:0]),.p10(clean_pixels[47:24]),.p01(clean_pixels[71:48]),.p11(clean_pixels[95:72])',
  '.p00(r_pixels[23:0]),.p10(r_pixels[47:24]),.p01(r_pixels[71:48]),.p11(r_pixels[95:72])'),
 'live_profile':('.profile_params(cp),.profile_h(ch)','.profile_params(profile_params),.profile_h(profile_h)'),
}
old,new=mutations[name];assert s.count(old)==1
f.write_text(s.replace(old,new))
