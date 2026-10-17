"""Record actual incomplete high-detail output; do not equate synthesis with acceptance."""
from datetime import datetime,timezone
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image

R=Path(__file__).resolve().parents[1]
hw=R/"results/hardware_20261009"
path=hw/"hires_camera_state_20261011.json"
state=json.loads(path.read_text(encoding="utf-8-sig"))
assert state["current_image_sha256"]=="7aed1ed5af2d32994a620f7bd3f198253365ceeccd967528daa6694e52dac2e0"
records=[]
for name in ["hires_211309_t20.png","hires_211430_t15.png"]:
    frame=np.asarray(Image.open(hw/name).convert("RGB"))
    assert frame.shape==(1080,1920,3)
    roi=frame[88:992,640:1280]
    contrast=np.ptp(roi.astype(np.int16),axis=1).max(axis=1)
    records.append({"frame":str((hw/name).relative_to(R)),"sha256":hashlib.sha256((hw/name).read_bytes()).hexdigest(),
        "nonuniform_window_rows":np.flatnonzero(contrast>20).tolist(),
        "dark_uniform_window_rows":int(np.sum((roi.mean(axis=(1,2))<55)&(contrast<20))),
        "visually_reviewed":True,"observed":"Only a thin top strip of the prescribed result window is visible; 900 of its 904 encoded rows are dark. Encoding can spread a single physical line across adjacent rows."})
evidence={"recorded_at_utc":datetime.now(timezone.utc).isoformat(),"image":state["current_image"],
    "image_sha256":state["current_image_sha256"],"program_log":state["program_log"],
    "videos":[str((hw/"hires_corrected_camera_20261011_211309.mp4").relative_to(R)),
              str((hw/"hires_corrected_camera_20261011_211430.mp4").relative_to(R))],
    "frames":records,"observed_failure":"Initial colorbars followed by a single visible top result row, no complete corrected page.",
    "hypothesis":"Published result display cannot fetch later rows before scanout; require physical per-row fetch counters to confirm.",
    "actual_camera_correction_accepted":False,"clarity_improvement_accepted":False,
    "verified_fallback":"results/hardware_20261009/working_clean_baseline_verified_20261011.json",
    "next":"Independent D206 image retaining 960x540 source, 640x904 result and unchanged thresholds, with row-fetch timing/progress."}
evidence_path=hw/"hires_display_failure_20261011_211430.json"
evidence_path.write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
state.update(actual_camera_correction_accepted=False,actual_camera_display_accepted=False,
    actual_camera_display_accepted_for_current_image=False,clarity_accepted=False,clarity_improvement_accepted=False,
    current_failed_stage="Incomplete high-detail display: only first row; row-fetch deadline hypothesis awaiting physical counters.",
    current_failure_evidence=str(evidence_path.relative_to(R)),pending=evidence["next"])
path.write_text(json.dumps(state,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
main_path=R/"docs/hardware_20261009.json"
main=json.loads(main_path.read_text(encoding="utf-8-sig"))
main.update(state,last_update_utc=evidence["recorded_at_utc"],capture_result=evidence["observed_failure"])
main_path.write_text(json.dumps(main,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(json.dumps({"failure_record":str(evidence_path),"frames":records},ensure_ascii=False,indent=2))
