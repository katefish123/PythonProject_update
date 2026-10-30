"""Prepare RGB-only EDID in an externally held RX reference; no vendor code is bundled."""
import argparse
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("target", type=Path)
args = parser.parse_args()
source = args.source.resolve(strict=True)
target = args.target.resolve()
repo_root = next((parent for parent in Path(__file__).resolve().parents
                  if (parent / '.git').exists()), Path(__file__).resolve().parents[1])
if target == source or target.is_relative_to(repo_root):
    parser.error("output must remain outside this repository and differ from source")
text = source.read_text(encoding="utf-8-sig")
for address, before, after in (("0D83", "F0", "C0"), ("0DFF", "A8", "D8")):
    pattern = rf"(16'h{address},\s*8'h){before}(\}})"
    text, count = re.subn(pattern, rf"\g<1>{after}\2", text, flags=re.IGNORECASE)
    if count != 1:
        parser.error(f"expected exactly one original EDID byte at {address}")
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(text, encoding="utf-8")
print("Prepared external RGB-only EDID source:", target)
