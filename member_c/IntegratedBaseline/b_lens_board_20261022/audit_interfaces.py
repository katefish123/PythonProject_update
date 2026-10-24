"""Offline checks of the exact local integration; never probes hardware."""
from pathlib import Path
import argparse,hashlib,json,re

def require(ok,msg):
    if not ok:raise RuntimeError(msg)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--candidate',type=Path,required=True);args=ap.parse_args()
    root=args.candidate.resolve();src=root/'sources';manifest=json.loads((root/'source_manifest.json').read_text())
    for name,h in manifest['candidate_source_sha256'].items():require(sha(src/name)==h,'Source drift '+name)
    allowed=[['video_correct_ddr_top.v'],['video_correct_ddr_top.v','continuous_source_path.v']]
    if 'status_rom_repair' in manifest:allowed.append(['video_correct_ddr_top.v','continuous_source_path.v','status_overlay.v'])
    if 'display_lookahead' in manifest:allowed.append(['video_correct_ddr_top.v','continuous_source_path.v','status_overlay.v','ddr_result_display_raw_corrected.v'])
    if 'display_lookahead' in manifest and 'writer_credit' in manifest:
        allowed.append(['video_correct_ddr_top.v','continuous_source_path.v','status_overlay.v','ddr_result_display_raw_corrected.v','ddr_result_writer_burst64.v'])
        if 'cache_decision' in manifest:
            allowed.append(['video_correct_ddr_top.v','continuous_source_path.v','status_overlay.v','ddr_result_display_raw_corrected.v','ddr_result_writer_burst64.v','ddr_quad_tile_cache.v'])
            if 'native_payload' in manifest:
                allowed.append(['video_correct_ddr_top.v','continuous_source_path.v','status_overlay.v','ddr_result_display_raw_corrected.v','ddr_result_writer_burst64.v','ddr_quad_tile_cache.v','video_correct_ddr_continuous_core.v'])
    require(manifest['changed'] in allowed,'Unexpected integration scope')
    top=(src/'video_correct_ddr_top.v').read_text();fdc=(src/'board_ddr.fdc').read_text()
    head=top.split(')(\n',1)[1].split('\n);',1)[0]
    ports={};direction=None;width=None
    for part in head.replace('\n',' ').split(','):
        p=part.strip();dm=re.match(r'(input|output|inout)\s+(?:wire|reg)\s*(\[\d+:\d+\])?\s*(\w+)$',p)
        if dm:direction,width,name=dm.groups()
        else:
            nm=re.fullmatch(r'\w+',p);require(nm is not None,'Unparsed port '+p);name=p
        require(direction is not None,'Missing direction')
        if width:
            hi,lo=map(int,re.findall(r'\d+',width))
            for i in range(lo,hi+1):ports[f'{name}[{i}]']=direction
        else:ports[name]=direction
    entries=re.findall(r'define_attribute\s+\{p:([^}]+)\}\s+\{PAP_IO_LOC\}\s+\{([^}]+)\}',fdc)
    pins=dict(entries);require(len(pins)==len(entries),'Duplicate port assignment')
    require(set(ports)==set(pins),'Unassigned/unknown port '+str(set(ports)^set(pins)))
    require(len(set(pins.values()))==len(pins),'Physical pin collision')
    for n,d in re.findall(r'define_attribute\s+\{p:([^}]+)\}\s+\{PAP_IO_DIRECTION\}\s+\{([^}]+)\}',fdc):
        require(n in ports and d.lower()==ports[n],'Pin direction mismatch '+n)
    parent=Path('D:/FPGA/output/b_lens_board_trial_20261022_v5/sources')
    require(sha(src/'board_ddr.fdc')==sha(parent/'board_ddr.fdc'),'Physical constraints changed')
    require('SOURCE_W=1920,SOURCE_H=1080,RESULT_W=1920,RESULT_H=1080' in top,'Wrong dimensions')
    rx=(src/'ms7200_ctl.v').read_text()
    edid={int(a,16)-0xD00:int(v,16) for a,v in re.findall(r"16'h(0[Dd][0-9A-Fa-f]{2}),\s*8'h([0-9A-Fa-f]{2})",rx)}
    require(len(edid)==256 and set(edid)==set(range(256)),'Incomplete EDID')
    require(sum(edid[i] for i in range(128))%256==0 and sum(edid[i] for i in range(128,256))%256==0,'EDID checksum')
    require(edid[131]&0x30==0,'EDID advertises unsupported YCbCr')
    windows={'source0':(0,1920*1080),'result0':(0x200000,1920*1080),'result1':(0x400000,1920*1080),'bist':(0x600000,256*8),'source1':(0x800000,1920*1080)}
    for param,window,count in [('SOURCE_BASE1','source1',2),('RESULT_BASE0','result0',2),('RESULT_BASE1','result1',2),('BIST_BASE','bist',1)]:
        values=[int(x,16) for x in re.findall(r'\.'+param+r"\(28'h([0-9a-fA-F]+)\)",top)]
        require(len(values)==count and all(x==windows[window][0] for x in values),'DDR instance parameter drift '+param)
    require('BIST_BEATS=256' in top and '.SOURCE_WORDS(SOURCE_W*SOURCE_H)' in top and '.RESULT_WORDS(RESULT_W*RESULT_H)' in top,'DDR size binding changed')
    for n,(start,size) in windows.items():
        require(start%8==0 and size%8==0,'DDR beat alignment '+n)
        require(start+size<=1<<28,'DDR address overflow '+n)
        for other,(s,z) in windows.items():
            if other!=n:require(start+size<=s or s+z<=start,'DDR overlap '+n+' '+other)
    b=Path('D:/FPGA/team_downloads/20261022_B_lens_v2/member_b_lens_pipeline_v2/rtl')
    unchanged=[];inherited_variants=[]
    for f in b.rglob('*.v'):
        target=src/f.name
        if target.exists() and f.name not in ['lens_autocrop_instance.v']:
            # Source packaging may normalize text line endings.
            if target.read_text().strip()==f.read_text().strip():unchanged.append(f.name)
            else:
                require(sha(target)==sha(parent/f.name),'New unreviewed B integration change '+f.name)
                inherited_variants.append(f.name)
    require(all(n in unchanged for n in ['perspective_core.v','lens_distort_coord.v','bilinear_interp.v']),'Active B lens math differs')
    build=(root/'build.tcl').read_text();listed=re.findall(r'add_design\s+\{([^}]+)\}',build)
    require(len(listed)==len(set(listed)) and all(Path(f).exists() for f in listed),'Missing/duplicate PDS source')
    constraints=re.findall(r'add_constraint\s+\{([^}]+)\}',build)
    inputs=[Path(f).resolve() for f in listed+constraints]
    require(len(inputs)==len(set(inputs)) and {p.name for p in inputs}==set(manifest['candidate_source_sha256']),'Incomplete/extra PDS input list')
    for p in inputs:require(p.parent==src and sha(p)==manifest['candidate_source_sha256'][p.name],'PDS input not bound to candidate '+str(p))
    project=root/'build/build.pds';project_text=project.read_text()
    project_inputs=[(project.parent/p).resolve() for p in re.findall(r'_file "(\.\./sources/[^"]+)"',project_text)]
    require(project_inputs==inputs,'Actual PDS project source/constraint order differs from build script')
    record=dict(scope='offline static interface checks; electrical and optical tests pending',candidate=str(root),top_sha256=sha(src/'video_correct_ddr_top.v'),physical_port_bits=len(ports),pins=pins,pin_constraints_unchanged=True,edid_two_checksums_valid=True,edid_rgb_only=True,source_and_result_dimensions=[1920,1080],ddr_word_bytes=4,ddr_data_bits=256,ddr_windows_words=windows,b_original_modules_checked=unchanged,older_frozen_integration_variants=inherited_variants,pds_source_count=len(listed),pds_build_tcl_sha256=sha(root/'build.tcl'),pds_input_sha256={str(p):sha(p) for p in inputs},all_pass=True)
    (root/'interface_audit.json').write_text(json.dumps(record,indent=2)+'\n')
    print('OFFLINE_INTERFACE_AUDIT_PASS',len(ports),'physical port bits;',len(listed),'PDS sources;',len(unchanged),'B original modules')
if __name__=='__main__':main()
