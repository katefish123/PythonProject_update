"""Prepare a bounded media probe; never capture or manipulate the desktop."""
from pathlib import Path
R=Path(__file__).resolve().parents[1]
source=(R/'scripts/probe_prefetch_flicker_20261012.py').read_text(encoding='utf-8-sig')
source=source.replace('import hashlib\n','import hashlib\nimport argparse\n')
source=source.replace('prefetch_camera_state_20261012.json','rowtrain_camera_state_20261013.json')
source=source.replace('original=Path("C:/Users/夏菲/Videos/2026-10-12 23-06-49.mp4")', '''parser=argparse.ArgumentParser()
parser.add_argument("video",type=Path)
args=parser.parse_args()
original=args.video.resolve()
assert state["program_verify_passed"]
assert state["current_image"].startswith("release/ddr_camera_hires_rowtrain_20261013/")
assert hashlib.sha256((R/state["current_image"]).read_bytes()).hexdigest()==state["current_image_sha256"]
assert (R/state["program_log"])==max(hw.glob("program_*.log"),key=lambda p:p.stat().st_mtime)''')
source=source.replace('out=hw/"prefetch_flicker_20261012_230649"', 'out=hw/("rowtrain_probe_"+original.stem.replace(" ","_").replace("-",""))')
source=source.replace('out.mkdir(exist_ok=True)','out.mkdir(exist_ok=False)')
source=source.replace('spans=[span(0,75),span(max(0,duration-25),25)]',
    'spans=[span(0,min(75,duration))]\nif duration>100:spans.append(span(duration-25,25))')
source=source.replace('times=[2,8,15,25,40,55,70,max(0,duration-20),max(0,duration-5)]',
    'times=sorted(set(round(t,2) for t in [1,2,5,8,15,25,duration/3,2*duration/3,max(0,duration-2)] if 0<=t<duration))[:9]')
(R/'scripts/probe_rowtrain_video_20261013.py').write_text(source,encoding='utf-8')
print('Bounded streamed probe prepared for the new image; originals preserved and no full-video RAM copy.')
