"""Inspect bounded portions of an actual long recording using streamed row metrics."""
from datetime import datetime,timezone
from pathlib import Path
import hashlib
import json
import re
import subprocess
import numpy as np
from PIL import Image,ImageDraw

R=Path(__file__).resolve().parents[1]
hw=R/"results/hardware_20261009"
state=json.loads((hw/"prefetch_camera_state_20261012.json").read_text(encoding="utf-8-sig"))
main=json.loads((R/"docs/hardware_20261009.json").read_text(encoding="utf-8-sig"))
assert main["current_image_sha256"]==state["current_image_sha256"]
original=Path("C:/Users/夏菲/Videos/2026-10-12 23-06-49.mp4")
assert original.stat().st_size>0 and original.stat().st_mtime>(R/state["program_log"]).stat().st_mtime
out=hw/"prefetch_flicker_20261012_230649"
out.mkdir(exist_ok=True)
ffmpeg=R/"tools/python_packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe"
info=subprocess.run([str(ffmpeg),"-hide_banner","-i",str(original)],capture_output=True)
metadata=info.stderr.decode("utf-8",errors="replace")
m=re.search(r"Duration: (\d+):(\d+):([\d.]+)",metadata)
assert m,metadata[-1000:]
duration=int(m[1])*3600+int(m[2])*60+float(m[3])
(out/"metadata.txt").write_text(metadata,encoding="utf-8")
h=hashlib.sha256()
with original.open("rb") as f:
    for chunk in iter(lambda:f.read(8*1024*1024),b""):h.update(chunk)
def span(start,seconds):
    command=[str(ffmpeg),"-hide_banner","-loglevel","error","-ss",str(start),"-i",str(original),"-t",str(seconds),
        "-an","-vf","crop=640:904:640:88,scale=32:904","-pix_fmt","rgb24","-f","rawvideo","pipe:1"]
    rows=[]
    with (out/f"span_{int(start)}.decode.log").open("wb") as log:
        process=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=log)
        nbytes=32*904*3
        while True:
            data=process.stdout.read(nbytes)
            if not data:break
            assert len(data)==nbytes
            frame=np.frombuffer(data,dtype=np.uint8).reshape(904,32,3)
            rowmean=frame.mean(axis=(1,2))
            rowstd=frame.std(axis=(1,2))
            dark=(rowmean<55)&(rowstd<12)
            bright=rowmean>100
            rows.append({"frame":len(rows),"encoded_seconds":round(start+len(rows)/30,4),
                "roi_mean":round(float(frame.mean()),2),"dark_rows":int(dark.sum()),"bright_rows":int(bright.sum()),
                "dark_row_ranges":[[int(a[0]),int(a[-1])] for a in np.split(np.flatnonzero(dark),np.flatnonzero(np.diff(np.flatnonzero(dark))>1)+1) if len(a)]})
        assert process.wait()==0
    return {"start_seconds":start,"seconds_requested":seconds,"frames":len(rows),"metrics":rows}
spans=[span(0,75),span(max(0,duration-25),25)]
times=[2,8,15,25,40,55,70,max(0,duration-20),max(0,duration-5)]
sheet=Image.new("RGB",(960*3,570*3),"#202020")
draw=ImageDraw.Draw(sheet)
frames=[]
for i,t in enumerate(times):
    p=out/f"sample_{i:02d}_{t:.1f}s.png"
    result=subprocess.run([str(ffmpeg),"-hide_banner","-loglevel","error","-ss",str(t),"-i",str(original),"-frames:v","1","-y",str(p)],capture_output=True)
    assert result.returncode==0
    im=Image.open(p).convert("RGB")
    assert im.size==(1920,1080)
    im.thumbnail((960,540))
    x,y=i%3*960,i//3*570
    sheet.paste(im,(x,y));draw.text((x+5,y+545),f"{t:.1f}s | ACTUAL RECORDING",fill="white")
    frames.append({"encoded_seconds":t,"frame":str(p.relative_to(R))})
sheet.save(out/"contact_sheet.jpg",quality=90)
record={"recorded_at_utc":datetime.now(timezone.utc).isoformat(),"original_video":str(original),
    "original_bytes":original.stat().st_size,"original_sha256":h.hexdigest(),"duration_encoded_seconds":duration,
    "current_image":state["current_image"],"image_sha256":state["current_image_sha256"],"program_log":state["program_log"],
    "spans":spans,"sample_frames":frames,"contact_sheet":str((out/"contact_sheet.jpg").relative_to(R)),
    "actual_full_page_visually_checked":False,"stable_picture_accepted":False,"algorithm_fps_measured":False,
    "limit":"Bounded segments of the original physical OBS recording. Row metrics need picture review. Encoded time/FPS is not algorithm update speed."}
(out/"probe.json").write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
for s in spans:
    a=s["metrics"]
    print(json.dumps({"start":s["start_seconds"],"frames":len(a),"whole_dark_frames":sum(x["dark_rows"]>890 for x in a),
        "partial_dark_frames":sum(0<x["dark_rows"]<=890 for x in a),"min_dark_rows":min(x["dark_rows"] for x in a),
        "max_dark_rows":max(x["dark_rows"] for x in a),"roi_mean_min":min(x["roi_mean"] for x in a),"roi_mean_max":max(x["roi_mean"] for x in a)},ensure_ascii=False))
print(json.dumps({"probe":str((out/"probe.json").relative_to(R)),"contact_sheet":str((out/"contact_sheet.jpg").relative_to(R))},ensure_ascii=False))
