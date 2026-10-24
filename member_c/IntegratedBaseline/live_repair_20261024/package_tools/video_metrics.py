"""Analyze declared log time units or sampled IDs; never grants acceptance."""
import argparse,csv,hashlib,json,math,re
from pathlib import Path
from statistics import median

UNITS={'ps':1e-12,'ns':1e-9,'us':1e-6,'ms':1e-3,'s':1}

def analyze_publications(text,unit):
    if unit not in UNITS:raise ValueError('Unknown time unit')
    events=[tuple(map(int,m)) for m in re.findall(r'PIPELINE_PUBLICATION corrected=1 id=(\d+) count=(\d+) time=(\d+)',text)]
    if len(events)<2:raise ValueError('At least two corrected publication events required')
    intervals=[]
    for (old_id,old_count,old_time),(new_id,new_count,new_time) in zip(events,events[1:]):
        if new_count<=old_count or new_id<=old_id:raise ValueError('Reset/duplicate/reversed epoch: analyze separately')
        if new_count!=old_count+1:raise ValueError('Log has missing publication events')
        if new_time<=old_time:raise ValueError('Non-increasing publication time')
        intervals.append((new_time-old_time)*UNITS[unit])
    span=(events[-1][2]-events[0][2])*UNITS[unit]
    return {'new_result_fps_between_events':len(intervals)/span,
            'new_result_events':len(events),'intervals':len(intervals),
            'publication_span_s':span,'interval_min_s':min(intervals),
            'interval_median_s':median(intervals),'interval_max_s':max(intervals),
            'event_source_ids':[e[0] for e in events],
            'declared_time_unit':unit,'evidence_scope':'simulation_sample',
            'hardware_acceptance':False,'end_to_end_latency_s':None,
            'note':'Source-ID distance is not output count. Model timing is not board FPS or optical acceptance.'}

def analyze_display_samples(rows):
    rows=list(rows)
    if len(rows)<2:raise ValueError('At least two samples required')
    parsed=[]
    for row in rows:
        t=float(row['time_s']);i=int(row['frame_id'])
        if not math.isfinite(t) or t<0 or i<=0 or i>0xffffffff:raise ValueError('Invalid time/frame ID')
        if row['mode']!='CORRECTED':raise ValueError('Analyze one continuous CORRECTED segment at a time')
        parsed.append((t,i))
    changed=[];steps=0
    for (t0,i0),(t1,i1) in zip(parsed,parsed[1:]):
        if t1<=t0 or i1<i0:raise ValueError('Time or frame ID reversed/reset; split epoch')
        if i1!=i0:changed.append(t1);steps+=i1-i0
    duration=parsed[-1][0]-parsed[0][0]
    return {'observed_new_display_events':len(changed),
            'observed_change_rate_hz':len(changed)/duration,'samples':len(rows),
            'observation_duration_s':duration,
            'source_id_steps_not_output_frames':steps,
            'maximum_sample_gap_s':max(t1-t0 for (t0,_),(t1,_) in zip(parsed,parsed[1:])),
            'changed_event_sample_times_s':changed,
            'end_to_end_latency_s':None,'hardware_acceptance':False,
            'evidence_scope':'sampled_display_ids_unverified_provenance',
            'note':'Observed changes can miss display events between samples. IDs do not prove unique sensor content; validate movement/recording and acquisition provenance separately.'}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input',type=Path,required=True)
    parser.add_argument('--format',choices=['modelsim','display-csv'],required=True)
    parser.add_argument('--time-unit',choices=list(UNITS))
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():parser.error('Preserve existing report; select a fresh output')
    text=args.input.read_text(encoding='utf-8-sig',errors='replace')
    if args.format=='modelsim':
        if args.time_unit is None:parser.error('ModelSim %t unit must be declared explicitly')
        result=analyze_publications(text,args.time_unit)
    else:result=analyze_display_samples(csv.DictReader(text.splitlines()))
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    result.update(input_file=str(args.input.resolve()),input_sha256=sha(args.input),analyzer_sha256=sha(Path(__file__)))
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))

if __name__=='__main__':main()
