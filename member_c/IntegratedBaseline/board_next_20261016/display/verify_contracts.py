"""Check the CDC ownership structure that zero-delay simulation cannot skew."""
from pathlib import Path
import re

text=(Path(__file__).resolve().parent/'ddr_result_display_raw_corrected.v').read_text()
chains=re.findall(r'(\w+)\s*<=\s*\{\s*\1\[1:0\]\s*,\s*ui_ack_toggle\s*\}',text)
assert len(chains)==1, f'ACK_SINGLE_SYNC_REQUIRED: duplicated physical return synchronizers: {chains}'
ack=chains[0]
assert f'req_toggle=={ack}[2]' in text, 'request credit must use the metadata acknowledgement synchronizer'
assert f'if({ack}[2]!=ack_seen_pix)' in text, 'metadata must use the same acknowledgement synchronizer'
assert text.count(') timing(')==1, 'exactly one VTC required'
for slot in ['0','1']:
    assert text.count(f'line_raw{slot}==display_raw')>=3, 'all current/next/row0 line hits must compare mode'
assert 'cmd_source_block=ui_line_raw' in text, 'command mode must be owned UI request payload'
print('PASS CDC single ACK synchronizer, mode-qualified metadata, one VTC, registered UI request mode')
