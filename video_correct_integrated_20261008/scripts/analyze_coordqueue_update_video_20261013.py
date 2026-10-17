"""Measure distinct visible corrected counter updates from real saved OBS media."""
from pathlib import Path
from datetime import datetime,timezone
import csv
import argparse,hashlib,json,re,subprocess
import numpy as np
from PIL import Image
from camera_update_counter import decode_counter,R
ap=argparse.ArgumentParser()
ap.add_argument('video',type=Path)
args=ap.parse_args()
video=args.video.resolve()
hw=R/'results/hardware_20261009'
state=json.loads((hw/'coordqueue_camera_state_20261013.json').read_text(encoding='utf-8-sig'))
main=json.loads((R/'docs/hardware_20261009.json').read_text(encoding='utf-8-sig'))
assert state['current_image_sha256']==main['current_image_sha256']
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(R/state['current_image'])==state['current_image_sha256']
program=R/state['program_log']
assert state['program_verify_passed'] and program==max(hw.glob('program_*.log'),key=lambda p:p.stat().st_mtime)
assert sha(program)==state['program_log_sha256']
assert video.stat().st_size>0 and video.stat().st_mtime>program.stat().st_mtime
O=hw/('coordqueue_update_'+video.stem.replace(' ','_').replace('-',''))
O.mkdir(exist_ok=False)
ff=R/'tools/python_packages/imageio_ffmpeg/binaries/ffmpeg-win-x86_64-v7.1.exe'
info=subprocess.run([str(ff),'-hide_banner','-i',str(video)],capture_output=True)
meta=info.stderr.decode('utf-8',errors='replace')
(O/'metadata.txt').write_text(meta,encoding='utf-8')
match=re.search(r'Duration: (\d+):(\d+):([\d.]+)',meta)
assert match and '1920x1080' in meta and '30 fps' in meta
duration=int(match[1])*3600+int(match[2])*60+float(match[3])
frames=[]
valid_samples=[]
groups=[]
last_value=None
with (O/'decode.log').open('wb') as log:
    # One frame in memory. Analyze at most180 seconds, with genuine video PTS
    # logged by showinfo. Passthrough avoids adding decoder-generated duplicates.
    p=subprocess.Popen([str(ff),'-hide_banner','-loglevel','info','-i',str(video),'-t','180',
        '-an','-vf','crop=640:904:640:88,scale=320:452,showinfo','-fps_mode','passthrough',
        '-pix_fmt','rgb24','-f','rawvideo','pipe:1'],stdout=subprocess.PIPE,stderr=log)
    nbytes=320*452*3
    while True:
        data=p.stdout.read(nbytes)
        if not data:break
        assert len(data)==nbytes
        frame=np.frombuffer(data,dtype=np.uint8).reshape(452,320,3)
        value,detail=decode_counter(frame)
        rowmean=frame.mean(axis=(1,2))
        rowstd=frame.std(axis=(1,2))
        dark_rows=int(((rowmean<55)&(rowstd<12)).sum())
        sample={'frame':len(frames),'counter':value,'dark_rows':dark_rows,**detail}
        frames.append(sample)
        if value is not None:
            valid_samples.append(sample)
            if value!=last_value:
                groups.append({'first_frame':sample['frame'],'counter':value,'frame_count':1})
                last_value=value
                if len(groups) in (1,2,5,10):Image.fromarray(frame).save(O/f'actual_decoded_group_{len(groups):02d}_{value:04d}.png')
            else:groups[-1]['frame_count']+=1
    assert p.wait()==0
text=(O/'decode.log').read_text(encoding='utf-8',errors='replace')
pts=[float(v) for v in re.findall(r' n:\s*\d+.*? pts_time:([\d.\-]+)',text)]
assert len(pts)==len(frames),(len(pts),len(frames))
for i,sample in enumerate(frames):sample['encoded_seconds']=pts[i]
for group in groups:group['encoded_seconds']=pts[group['first_frame']]
intervals=np.diff([g['encoded_seconds'] for g in groups]).tolist()
tick_steps=[(b['counter']-a['counter'])&4095 for a,b in zip(groups,groups[1:])]
valid_span=pts[valid_samples[-1]['frame']]-pts[valid_samples[0]['frame']] if valid_samples else 0
window=frames[valid_samples[0]['frame']:valid_samples[-1]['frame']+1] if valid_samples else []
valid_ratio=sum(s['counter'] is not None for s in window)/len(window) if window else 0
observed_rate=(len(groups)-1)/(groups[-1]['encoded_seconds']-groups[0]['encoded_seconds']) if len(groups)>1 else None
confident=len(groups)>=6 and valid_span>=15 and valid_ratio>0.90 and all(0<s<250 for s in tick_steps)
stimuli=list((R/'results/camera_update_counter_20261013').glob('actual_stimulus_*.csv'))
creation=re.search(r"creation_time\s*:\s*([^\s]+)",meta)
creation_epoch=datetime.fromisoformat(creation[1].replace("Z","+00:00")).timestamp() if creation else None
stimulus_matches=[]
for candidate in stimuli:
    rows=list(csv.DictReader(candidate.open(encoding="utf-8")))
    if not rows or creation_epoch is None:continue
    first=float(rows[0]["pc_wall_unix_seconds"])
    last=float(rows[-1]["pc_wall_unix_seconds"])
    overlap=max(0,min(last,creation_epoch+duration)-max(first,creation_epoch))
    if overlap>0:stimulus_matches.append((overlap,candidate))
stimulus=max(stimulus_matches,key=lambda item:item[0])[1] if stimulus_matches else None
record={'analyzed_at_utc':datetime.now(timezone.utc).isoformat(),'current_image':state['current_image'],
    'image_sha256':state['current_image_sha256'],'program_log':state['program_log'],'program_log_sha256':state['program_log_sha256'],
    'original_video':str(video),'original_bytes':video.stat().st_size,'original_sha256':sha(video),
    'encoded_duration_seconds':duration,'analyzed_frames':len(frames),'valid_counter_frames':len(valid_samples),
    'valid_counter_span_seconds':round(valid_span,4),'valid_decode_fraction_in_span':round(valid_ratio,5),
    'observed_distinct_result_groups':len(groups),'observed_distinct_update_hz':round(observed_rate,5) if observed_rate is not None else None,
    'inter_update_intervals_seconds':intervals,'captured_input_counter_tick_steps':tick_steps,'groups':groups,'frames':frames,
    'counter_decode_sufficient_for_observed_rate':confident,'visual_picture_checked':False,
    'exact_internal_algorithm_publish_fps_proven':False,'maximum_possible_algorithm_fps_proven':False,
    'long_term_stability_verified':False,'original_video_modified':False,
    'stimulus_csv':str(stimulus.relative_to(R)) if stimulus else None,'stimulus_csv_sha256':sha(stimulus) if stimulus else None,
    'scope':'Visible distinct corrected counter results per video timestamp under a10Hz optical stimulus. Holds/duplicates do not count. This is an observed output-update rate, not HDMI carrier/OBS FPS or a proof of maximum processing throughput; missed/aliased input values can undercount.',
    'source_and_fpga_unchanged':True}
(O/'measurement.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:record[k] for k in ['analyzed_frames','valid_counter_frames','valid_counter_span_seconds','valid_decode_fraction_in_span','observed_distinct_result_groups','observed_distinct_update_hz','counter_decode_sufficient_for_observed_rate']},indent=2))
print(O/'measurement.json')
