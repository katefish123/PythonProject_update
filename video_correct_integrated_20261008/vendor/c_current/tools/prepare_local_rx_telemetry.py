"""Add a read-only PCLK register probe to an external local RX reference."""
import argparse
from pathlib import Path
import re

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('source', type=Path)
p.add_argument('target', type=Path)
a = p.parse_args()
target = a.target.resolve()
repo_root = next((parent for parent in Path(__file__).resolve().parents
                  if (parent / '.git').exists()), Path(__file__).resolve().parents[1])
if target == a.source.resolve() or target.is_relative_to(repo_root):
    p.error('generated reference must remain outside the repository and source')
s = a.source.read_text(encoding='utf-8-sig')
old = "dri_cnt == 9'd3 && busy_falling && freq_ensure"
if s.count(old) != 2:
    p.error('unexpected status transition layout')
s = s.replace(old, "dri_cnt == 9'd4 && busy_falling && freq_ensure")
pattern = r"(STA_RD\s*: begin\s*if\(busy_falling\)\s*begin\s*if\(dri_cnt == )5'd3(\))"
s, n = re.subn(pattern, r"\g<1>5'd4\2", s)
if n != 1:
    p.error('unexpected status counter layout')
pattern = r"(addr\s*<= 16'h209F;\s*data_in <= 8'h00;\s*end)(\s*default:)"
s, n = re.subn(pattern, r"\1\n 9'd4: begin addr <= 16'h1281; data_in <= 8'h00; end\2", s)
if n != 1:
    p.error('unexpected status address layout')
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(s, encoding='utf-8')
print('Prepared read-only telemetry source:', target)
