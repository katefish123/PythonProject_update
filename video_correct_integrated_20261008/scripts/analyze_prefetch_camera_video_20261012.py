"""Keep actual prefetch media assigned to its own image and program event."""
import sys
from pathlib import Path
R=Path(__file__).resolve().parents[1]
source=R/"scripts/analyze_clean_camera_video_20261011.py"
text=source.read_text(encoding="utf-8-sig")
text=text.replace('state_file = "hires_camera_state_20261011.json" if args.hires else "clean_camera_state_20261011.json"',
    'assert not args.hires, "Use this dedicated prefetch entry without --hires"\nstate_file = "prefetch_camera_state_20261012.json"')
text=text.replace('name = ("hires_corrected_camera_" if args.hires else "clean_corrected_camera_")',
    'name = "prefetch_corrected_camera_"')
text=text.replace('("hires_camera_video_latest_20261011.json" if args.hires else "clean_camera_video_latest_20261011.json")',
    '"prefetch_camera_video_latest_20261012.json"')
text=text.replace('assert state["program_verify_passed"] and not state["diagnostic_grid_present"]',
'''assert state["program_verify_passed"] and not state["diagnostic_grid_present"]
assert state["current_image"] == "release/ddr_camera_hires_prefetch_20261012/video_correct_ddr_top.sbit"
assert hashlib.sha256((root / state["current_image"]).read_bytes()).hexdigest() == state["current_image_sha256"]
main = json.loads((root / "docs/hardware_20261009.json").read_text(encoding="utf-8-sig"))
assert main["current_image_sha256"] == state["current_image_sha256"], "Another image was loaded after this prefetch state"
''')
exec(compile(text,str(source),"exec"),{"__file__":str(source),"__name__":"__main__"})
