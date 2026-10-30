"""Decode the optical Gray counter; measure visible updates, not absolute delay."""
from pathlib import Path
from collections import deque
import argparse
import json
import subprocess
import numpy as np
from PIL import Image

D=Path(__file__).resolve().parent
FFMPEG=D.parents[1]/"tools/python_packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe"


def decode(image):
    a=np.asarray(image,dtype=np.int16)
    r,g,b=a[...,0],a[...,1],a[...,2]
    mask=((r>85)&(r>g*1.30)&(r>b*1.15))|((g>85)&(g>r*1.25)&(g>b*1.15))
    remaining=mask.copy()
    objects=[]
    height,width=mask.shape
    for sy,sx in np.argwhere(mask):
        if not remaining[sy,sx]:continue
        q=deque([(int(sy),int(sx))]);remaining[sy,sx]=False
        x0=x1=int(sx);y0=y1=int(sy);count=0;colors=np.zeros(3,dtype=np.int64)
        while q:
            y,x=q.popleft();count+=1;colors+=a[y,x]
            x0=min(x0,x);x1=max(x1,x);y0=min(y0,y);y1=max(y1,y)
            for ny,nx in ((y-1,x),(y+1,x),(y,x-1),(y,x+1)):
                if 0<=ny<height and 0<=nx<width and remaining[ny,nx]:
                    remaining[ny,nx]=False;q.append((ny,nx))
        w,h=x1-x0+1,y1-y0+1
        if count>=12 and w>=3 and h>=5 and count/(w*h)>.35:
            objects.append({"x":(x0+x1)/2,"y":(y0+y1)/2,"h":h,"w":w,
                            "area":count,"green":bool(colors[1]>colors[0])})
    best=None
    for seed in objects:
        row=[o for o in objects if abs(o["y"]-seed["y"])<max(32,2*seed["h"])
             and .45<o["h"]/seed["h"]<2.2]
        row.sort(key=lambda o:o["x"])
        for start in range(max(0,len(row)-15)):
            parts=row[start:start+16]
            if len(parts)!=16:continue
            xs=np.asarray([p["x"] for p in parts]);ys=np.asarray([p["y"] for p in parts])
            spacing=np.diff(xs);pitch=np.median(spacing)
            if pitch<4 or np.max(abs(spacing-pitch))>pitch*.45:continue
            fit=np.polyfit(xs,ys,1)
            residual=float(np.max(abs(ys-np.polyval(fit,xs))))
            if residual>max(3,np.median([p["h"] for p in parts])*.4):continue
            gray=0
            for p in parts:gray=(gray<<1)|int(p["green"])
            counter=0
            while gray:counter^=gray;gray>>=1
            candidate={"counter":counter,"fit_error_px":residual,"components":parts}
            if best is None or residual<best["fit_error_px"]:best=candidate
    return best


def self_check():
    from show_latency_target import frame
    from brect_path import rectify_target
    for n in (0,1,2,3,12345,65535):
        direct=frame(n,"12:34:56.7").resize((480,270))
        assert decode(direct)["counter"]==n,n
        corrected=rectify_target(frame(n,"12:34:56.7"))
        assert decode(corrected)["counter"]==n,n
    print("COUNTER_DECODER_CHECK_PASS direct_and_rectified=12")


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("video",nargs="?",type=Path)
    ap.add_argument("--self-check",action="store_true")
    ap.add_argument("--fps",type=int,default=10)
    ap.add_argument("--out",type=Path)
    args=ap.parse_args()
    if args.self_check:self_check();return
    assert args.video and args.video.is_file()
    out=args.out or args.video.parent/(args.video.stem+"_counter")
    out.mkdir(exist_ok=True)
    width,height=320,452
    command=[str(FFMPEG),"-v","error","-i",str(args.video),"-vf",
             f"crop=640:904:640:88,scale={width}:{height},fps={args.fps}",
             "-f","rawvideo","-pix_fmt","rgb24","pipe:1"]
    records=[];changes=[];rejected=[];last=None;first=None;index=0
    with (out/"decode.log").open("wb") as log:
        p=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=log)
        try:
            while True:
                raw=p.stdout.read(width*height*3)
                if not raw:break
                assert len(raw)==width*height*3,"partial decoded frame"
                image=Image.frombytes("RGB",(width,height),raw)
                result=decode(image)
                if result:
                    counter=result["counter"];t=index/args.fps
                    record={"sample":index,"video_seconds":t,"counter":counter,"fit_error_px":result["fit_error_px"]}
                    if last is None or 0<=(counter-last["counter"])%65536<=200:
                        records.append(record)
                        if first is None:first=record;image.save(out/"first_counter.png")
                        if last is None or counter!=last["counter"]:changes.append(record)
                        last=record
                    else:rejected.append(record)
                index+=1
        finally:p.stdout.close()
        assert p.wait()==0,log
    intervals=np.diff([x["video_seconds"] for x in changes])
    ticks=np.asarray([(b["counter"]-a["counter"])%65536 for a,b in zip(changes,changes[1:])])
    # Exclude a missing-code interval; decoding failure is not evidence of a frozen FPGA.
    usable=intervals<=1.5
    valid_intervals=intervals[usable]
    report={"video":str(args.video),"sampled_frames":index,"valid_samples":len(records),
            "sample_fps":args.fps,"counter_period_seconds":.1,"counter_changes":len(changes),
            "sample_time_quantization_seconds":1/args.fps,"absolute_latency_measured":False,
            "processing_fps_directly_measured":False,
            "limitations":["Output-only capture measures visible counter changes, not source-to-display delay",
                           "Counter stimulus is capped at 10 Hz; repeated counter values may hide updates",
                           "Failed counter decoding must not be classified as a frozen result"],
            "first_valid_sample":first,"last_valid_sample":last,
            "visible_change_interval_median_seconds":float(np.median(valid_intervals)) if len(valid_intervals) else None,
            "visible_change_interval_p90_seconds":float(np.percentile(valid_intervals,90)) if len(valid_intervals) else None,
            "visible_changes_per_second":float(len(valid_intervals)/valid_intervals.sum()) if len(valid_intervals) else None,
            "median_source_counter_step":float(np.median(ticks[usable])) if len(valid_intervals) else None,
            "decoded":records,"changes":changes,"rejected_nonmonotonic_or_large_jumps":rejected}
    (out/"counter_report.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({k:v for k,v in report.items() if k not in ("decoded","changes","rejected_nonmonotonic_or_large_jumps")},indent=2))


if __name__=="__main__":main()
