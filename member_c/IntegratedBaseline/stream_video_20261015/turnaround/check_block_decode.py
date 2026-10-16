from pathlib import Path
import re,sys
p=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).with_name('ddr_word_engine_result_burst.v')
s=p.read_text()
if re.search(r"request_block\s*(?:\+|>=|<)",s):
 print('FAIL LIVE_BLOCK_SPAN_ARITHMETIC: complete-block region bounds must be constant-predecoded, not derived from request_block arithmetic/comparisons')
 sys.exit(1)
print('PASS CONSTANT_BLOCK_REGION_DECODE: no per-request complete-span arithmetic')
