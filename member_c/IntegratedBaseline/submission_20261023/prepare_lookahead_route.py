"""Preserve RTL/FDC and reroute an immutable mapped/placed checkpoint."""
from pathlib import Path
import argparse,hashlib,json,shutil

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--candidate',type=Path,required=True);p.add_argument('--seed',type=int,default=137);p.add_argument('--new-placement',action='store_true');p.add_argument('--placement-seed',type=int,default=111);p.add_argument('--name',choices=['performance','placement','placement2']);a=p.parse_args()
    root=a.candidate.resolve();out=root/(a.name or ('placement' if a.new_placement else 'performance'));out.mkdir(exist_ok=False);inputs=out/'inputs';inputs.mkdir()
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();records={}
    files=[root/'build/device_map/video_correct_ddr_top_map.adf',root/'build/device_map/video_correct_ddr_top.pcf']
    if not a.new_placement:files.append(root/'build/place_route/video_correct_ddr_top_plc.adf')
    for f in files:
        target=inputs/f.name;shutil.copyfile(f,target);records[str(target)]={'sha256':sha(target),'upstream':str(f)}
    setup=(root/'build.tcl').read_text().split('compile -top_module')[0]
    tcl=setup+'add_constraint {'+(inputs/'video_correct_ddr_top.pcf').as_posix()+'}\n'
    tcl+='pnr -force_to_run -input_db_file {'+(inputs/'video_correct_ddr_top_map.adf').as_posix()+'}'
    if not a.new_placement:tcl+=' -input_place_db_file {'+(inputs/'video_correct_ddr_top_plc.adf').as_posix()+'}'
    else:tcl+=f' -gplace_seed {a.placement_seed} -refineplacement_mode Swap -refineplacement_iteration 50'
    tcl+=f' -mode performance -groute_seed {a.seed} -optimize_multi_corner_timing -slack_prior_in_global_router TRUE -enable_route_constraint_iterate -route_constraint_iterate_times 3 -route_constraint_slack 0.3 -fix_hold_violation_threshold 50\nreport_timing\ngen_bit_stream\n'
    (out/'route.tcl').write_text(tcl)
    (out/'input_binding.json').write_text(json.dumps({'candidate_manifest_sha256':sha(root/'source_manifest.json'),
        'upstream_build_tcl_sha256':sha(root/'build.tcl'),'route_tcl_sha256':sha(out/'route.tcl'),'inputs':records,
        'scope':'Same mapped design and constraints; '+('fresh placement seed/refinement' if a.new_placement else 'same placed design; new route seed only')},indent=2)+'\n')
    print(out)
