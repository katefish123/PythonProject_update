"""Optical test stimulus: changing Gray counter within the unchanged black ROIs."""
from pathlib import Path
from datetime import datetime,timezone
import argparse
import json
import time
from PIL import Image,ImageDraw,ImageFont

D=Path(__file__).resolve().parent
PERIOD_NS=100_000_000
BIT_ORIGIN=(650,430)
BIT_PITCH=40
BIT_SIZE=(32,40)


def frame(counter,clock_text):
    image=Image.open(D/"results/camera_target_1920x1080.png").convert("RGB")
    draw=ImageDraw.Draw(image)
    draw.rectangle((620,396,1370,648),fill="white")
    font=ImageFont.truetype("C:/Windows/Fonts/arial.ttf",52)
    small=ImageFont.truetype("C:/Windows/Fonts/arial.ttf",32)
    code=(counter&65535)^((counter&65535)>>1)
    for i in range(16):
        x,y=BIT_ORIGIN[0]+i*BIT_PITCH,BIT_ORIGIN[1]
        draw.rectangle((x,y,x+BIT_SIZE[0]-1,y+BIT_SIZE[1]-1),fill=(40,190,90) if ((code>>(15-i))&1) else (215,65,35))
    draw.text((650,493),f"COUNT {counter:06d}",fill="black",font=font)
    draw.text((650,559),clock_text,fill="black",font=small)
    draw.text((650,607),"Changes every 0.1 second",fill="#555555",font=small)
    return image


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--preview",action="store_true")
    ap.add_argument("--stop-file",type=Path)
    args=ap.parse_args()
    if args.preview:
        path=D/"results/latency_target_preview.png"
        frame(12345,"12:34:56.7").save(path)
        print(path)
        return
    import tkinter as tk
    from PIL import ImageTk
    root=tk.Tk()
    root.title("黑标动态计数测试 · Esc退出 · F11切换全屏")
    root.configure(bg="#b4b4b4")
    root.attributes("-fullscreen",True)
    label=tk.Label(root,bg="#b4b4b4",borderwidth=0)
    label.pack(fill="both",expand=True)
    root.bind("<Escape>",lambda event:root.destroy())
    root.bind("<F11>",lambda event:root.attributes("-fullscreen",not root.attributes("-fullscreen")))
    start=time.monotonic_ns()
    logs=D.parents[1]/"results/hardware_20261014_black_fast"
    logs.mkdir(parents=True,exist_ok=True)
    stamp=datetime.now(timezone.utc).astimezone().strftime("%Y%m%d_%H%M%S")
    stream=(logs/f"latency_target_{stamp}.jsonl").open("w",encoding="utf-8",buffering=1)
    stream.write(json.dumps({"event":"start","utc":datetime.now(timezone.utc).isoformat(),
                             "monotonic_ns":start,"period_ns":PERIOD_NS,"code":"gray16",
                             "nominal_size":[1920,1080],"absolute_board_latency_measured":False})+"\n")
    saved=-1
    def update():
        nonlocal saved
        if args.stop_file and args.stop_file.exists():
            root.destroy()
            return
        now=time.monotonic_ns()
        counter=(now-start)//PERIOD_NS
        if counter!=saved:
            saved=counter
            clock_text=datetime.now().strftime("%H:%M:%S.%f")[:-5]
            target=frame(counter,clock_text)
            width,height=max(1,root.winfo_width()),max(1,root.winfo_height())
            if width>1 and height>1:
                ratio=min(width/1920,height/1080)
                target=target.resize((round(1920*ratio),round(1080*ratio)),Image.Resampling.LANCZOS)
            photo=ImageTk.PhotoImage(target)
            label.configure(image=photo)
            label.image=photo
            stream.write(json.dumps({"event":"present_requested","counter":int(counter),
                                     "utc":datetime.now(timezone.utc).isoformat(),
                                     "monotonic_ns":time.monotonic_ns(),
                                     "screen_scanout_time_known":False})+"\n")
        root.after(max(1,int((PERIOD_NS-(time.monotonic_ns()-start)%PERIOD_NS)/1_000_000)),update)
    root.after(100,update)
    try:root.mainloop()
    finally:
        stream.write(json.dumps({"event":"closed","utc":datetime.now(timezone.utc).isoformat()})+"\n")
        stream.close()


if __name__=="__main__":main()
