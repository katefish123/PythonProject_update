"""Preserve the unresolved HDMI sink event before restoring the verified baseline."""
from datetime import datetime,timedelta,timezone
from pathlib import Path
import hashlib
import json
import shutil

R=Path(__file__).resolve().parents[1]
hw=R/"results/hardware_20261009"
stamp=datetime.now(timezone.utc)
name="capture_hdmi_recovery_"+(stamp+timedelta(hours=8)).strftime("%Y%m%d_%H%M%S")
state=hw/"hires_status_state_20261011.json"
current=json.loads(state.read_text(encoding="utf-8-sig"))
copies={}
for p in [state,hw/"clean_camera_state_20261011.json",R/"docs/hardware_20261009.json"]:
    dest=hw/(name+"_"+p.name)
    shutil.copyfile(p,dest)
    copies[str(p.relative_to(R))]=str(dest.relative_to(R))
scan=hw/"scan_board_1mhz_20261011_234202.log"
text=scan.read_text(encoding="utf-8-sig",errors="replace")
assert "0x00602899" in text and "configure situation (done bit): 1" in text
record={"recorded_at_utc":stamp.isoformat(),"board_last_programmed_image":current["current_image"],
    "image_sha256":current["current_image_sha256"],"state_copies":copies,
    "capture_usb_present":True,"capture_usb_status":"OK VC-002Pro, same device path",
    "obs_last_device_settings":"1920x1080 NV12 30fps, source reopened at23:38:15 and23:39:04",
    "physical_action_reported":"User unplugged capture HDMI, FPGA power remained on.",
    "after_reseat_KEY0_and_source_refresh":"User reports still no video input signal.",
    "camera_direct_to_capture":"User confirms real live image with camera connected directly after this event.",
    "scan":str(scan.relative_to(R)),"scan_sha256":hashlib.sha256(scan.read_bytes()).hexdigest(),
    "fpga_identified_and_configured":True,"current_bitstream_readback_identity_checked_during_scan":False,
    "conclusion":"Current camera/capture direct path works; missing signal remains on FPGA output route. HDMI output cable/link and D206 startup are not yet separated.",
    "next":"Restore retained physically verified clean a4 bitstream, then reconnect FPGA output path and check HDMI signal.",
    "high_detail_picture_accepted":False,"d206_real_grid_decoded":False,"flash_modified":False,
    "computer_use_paused_by_user":True}
(hw/(name+".json")).write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
(hw/"capture_hdmi_recovery_latest_20261011.json").write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print("Saved the HDMI unplug/direct-camera comparison and state snapshots before baseline restore.")
