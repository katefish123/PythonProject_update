"""Keep a separate real-recording analyzer for the uniquely tagged D206 image."""
from pathlib import Path

D=Path(__file__).resolve().parent
R=D.parents[1]
source=R/"scripts/analyze_ddr_status_video_20261011.py"
text=source.read_text(encoding="utf-8-sig")
text=text.replace("D205","D206")
text=text.replace("ddr_camera_status_state_20261011.json","hires_status_state_20261011.json")
text=text.replace("diagnostics/ddr_camera_status_20261011/decode_status.py","diagnostics/ddr_camera_hires_status_20261011/decode_status.py")
text=text.replace("ddr_status_fpga_","hires_status_fpga_")
text=text.replace('"ui_written": r["probe"]["ui_packets_written"]',
    '"underrun": r["probe"]["underrun"], "row_cycles": r["probe"]["display_last_row_cycles"],\n'
    '    "max_row_cycles": r["probe"]["display_max_row_cycles"], "row": r["probe"]["display_current_row"],\n'
    '    "fetch_state": r["probe"]["display_fetch_state"], "beat": r["probe"]["display_beat_index"]')
target=R/"scripts/analyze_hires_status_video_20261011.py"
assert target!=source
target.write_text(text,encoding="utf-8")
print("Prepared independent actual-video D206 analyzer; D205 historical evidence unchanged.")
