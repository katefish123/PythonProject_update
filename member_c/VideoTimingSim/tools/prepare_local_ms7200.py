"""Prepare a local diagnostic RX controller from a separately obtained reference.

The reference source has no verified license and must remain outside this repo.
This script changes only its input-detection condition, preserving vendor headers.
"""
import argparse
import hashlib
from pathlib import Path
import re

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("reference", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
source = args.reference.resolve(strict=True)
target = args.output.resolve()
if source == target:
    parser.error("output must differ from the original reference")
repo_root = next((parent for parent in Path(__file__).resolve().parents
                  if (parent / '.git').exists()), Path(__file__).resolve().parents[1])
if target.is_relative_to(repo_root):
    parser.error("keep the unlicensed reference and generated source outside the repo")
original_bytes = source.read_bytes()
try:
    original = original_bytes.decode("utf-8-sig")
except UnicodeDecodeError:
    original = original_bytes.decode("gb18030")
condition = r"\(freq_rec_2d\[17:16\]\s*==\s*2'b00\)\s*&&\s*\(freq_rec_1d\[17:16\]\s*==\s*2'b10\)"
if len(re.findall(condition, original)) != 1:
    parser.error("expected exactly one original input-detection condition")
patched = re.sub(condition,
    "(freq_rec_1d[17] == 1'b1) && (freq_rec_1d[15:0] != 16'h0000) && "
    "(!init_over || ((freq_rec_2d[17:16] == 2'b00) && (freq_rec_1d[17:16] == 2'b10)))",
    original)
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(patched, encoding="utf-8")
print(f"Prepared local diagnostic source: {target}")
print(f"Reference SHA256: {hashlib.sha256(original_bytes).hexdigest()}")
print("This is an experimental reference-derived patch, not a production RX driver.")
