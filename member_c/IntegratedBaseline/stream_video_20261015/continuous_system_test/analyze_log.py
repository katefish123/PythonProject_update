"""Extract publication cadence, exact frame IDs and image ages without inferring camera FPS."""
import argparse, json, re
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('log', type=Path)
p.add_argument('--output', type=Path)
a = p.parse_args()
text = a.log.read_text(encoding='utf-8', errors='ignore')

def records(event):
    out = []
    for line in text.splitlines():
        if event not in line:
            continue
        row = {k: int(v) for k, v in re.findall(r'([a-zA-Z_][a-zA-Z_0-9]*)=(-?\d+)', line)}
        row['event'] = event
        out.append(row)
    return out

captures = records('CONTINUOUS_CAPTURE_BEGIN')
publications = records('CONTINUOUS_FRAME_PUBLISH')
intervals = records('CONTINUOUS_PUBLISH_INTERVAL')
hdmi = records('CONTINUOUS_HDMI_FRAME')
rejections = records('CONTINUOUS_BAD_MARKER_REJECT')
telemetry = records('CONTINUOUS_TELEMETRY')
capture_by_id = {r['gen']: r for r in captures}
steady = []
for previous, current in zip(publications, publications[1:]):
    c0, c1 = capture_by_id.get(previous['id']), capture_by_id.get(current['id'])
    if c0 and c1 and c1['physical_raster'] == c0['physical_raster'] + 1:
        steady.append(current['time_ns'] - previous['time_ns'])

summary = {
    'verified_pass': 'VERIFIED_PASS_BIT=1' in text and not re.search(r'\*\* (?:Fatal|Error):', text),
    'capture_events': captures,
    'publications': publications,
    'publication_intervals': intervals,
    'hdmi_frame_checks': hdmi,
    'rejections': rejections,
    'final_telemetry': telemetry[-1] if telemetry else None,
    'physically_consecutive_valid_frame_intervals_ns': steady,
    'mean_publication_fps_including_rejection_gaps': (
        1e9 * (len(publications)-1) / (publications[-1]['time_ns']-publications[0]['time_ns'])
        if len(publications)>1 else None
    ),
    'mean_fps_for_physically_consecutive_valid_frames': 1e9*len(steady)/sum(steady) if steady else None,
    'limits': 'Simulation cadence under the tested native memory delays; not board, optical quality, or long-term hardware FPS evidence.',
}
dest = a.output or a.log.with_name('metrics.json')
dest.write_text(json.dumps(summary, indent=2)+'\n', encoding='utf-8')
print(json.dumps({k:v for k,v in summary.items() if k in ['verified_pass','mean_publication_fps_including_rejection_gaps','mean_fps_for_physically_consecutive_valid_frames','final_telemetry']}, indent=2))
