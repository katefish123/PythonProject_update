"""Isolated native lens-only candidate. Frozen V5C/B delivery are read-only."""
from pathlib import Path
import hashlib,json,re,shutil
R=Path(__file__).resolve().parent
F=Path('D:/FPGA/output/c_board_next_v5c_20261016')
B=Path('D:/FPGA/team_downloads/20261022_B_lens_v2/member_b_lens_pipeline_v2')
O=Path('D:/FPGA/output/b_lens_board_trial_20261022_v5')
assert not O.exists(),'Use fresh candidate'
(O/'sources').mkdir(parents=True);(O/'build').mkdir()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def rep(s,a,b):assert s.count(a)==1,(a,s.count(a));return s.replace(a,b)
for p in (F/'sources').iterdir():
 if p.is_file():shutil.copyfile(p,O/'sources'/p.name)
def edit(name,fn):
 p=O/'sources'/name;p.write_text(fn(p.read_text()),encoding='utf-8')
original={p.name:sha(p) for p in (F/'sources').iterdir() if p.is_file()}
for n in ['perspective_core.v','lens_distort_coord.v']:shutil.copyfile(B/'rtl'/n,O/'sources'/n)
header=(B/'examples/r50_18mm_viewport.vh').read_text()
example=(B/'examples/lens_autocrop_instance.v').read_text().replace('`include "examples/r50_18mm_viewport.vh"',header)
(O/'sources/lens_autocrop_instance.v').write_text(example,encoding='utf-8')
constants=dict(re.findall(r'`define\s+(SAFE_H\d\d_Q24)\s+(\S+)',header))
packed='{'+','.join(constants['SAFE_H'+str(i//3)+str(i%3)+'_Q24'] for i in reversed(range(9)))+'}'
def processor(s):
 s=rep(s,"assign math_debug_h={40'd16777216,120'd0,40'd16777216,120'd0,40'd16777216};",'assign math_debug_h='+packed+';')
 s=rep(s,'perspective_core #(.SRC_W(SRC_W),.SRC_H(SRC_H)) algorithm(','lens_autocrop_instance algorithm(')
 s=rep(s,".in_valid(issue),.nearest(mode),.geometry_valid(1'b1),",".in_valid(issue),.nearest(mode),")
 a=s.index(".dst_x(logical_x),.dst_y(iy),.h00(");b=s.index(' .req_valid(req_valid)',a)
 s=s[:a]+'.dst_x(logical_x),.dst_y(iy),\n'+s[b:]
 return s
edit('frame_processor_stream.v',processor)
edit('video_correct_ddr_continuous_core.v',lambda s:rep(rep(s,'.ACTIVE_W(OUT_W-3),.ACTIVE_X(1),','.ACTIVE_W(OUT_W),.ACTIVE_X(0),.FIXED_IDENTITY(1),'),'.frame_valid(frame_valid),.frame_bank(descriptor_bank),.frame_geometry_valid(geometry_valid),',".frame_valid(frame_valid),.frame_bank(descriptor_bank),.frame_geometry_valid(1'b1),"))
def display_priority(s):
 # Defer long background source reads across a complete row fill. Short
 # capture writes remain serviceable during local line-buffer stores.
 # The arbiter already retains any accepted owner until its response retires.
 s=rep(s,'.c0_valid(br_v),.c0_ready(br_r),','.c0_valid(br_v&&!display_prefetch_busy),.c0_ready(br_r),')
 return s
edit('video_correct_ddr_continuous_core.v',display_priority)
def source(s):
 return rep(s,'.clk(proc_clk),.rst_n(rst_n),.raw_requested(raw_requested),.allocation_valid',".clk(proc_clk),.rst_n(rst_n),.raw_requested(1'b1),.allocation_valid")
edit('continuous_source_path.v',source)
def top(s):
 s=rep(s,'RESULT_W=768,RESULT_H=1080','RESULT_W=1920,RESULT_H=1080')
 s=rep(s,'raw_sync<=7;','raw_sync<=0;')
 return rep(s,'raw_sync<={raw_sync[1:0],key1_pattern_n};','raw_sync<={raw_sync[1:0],!key1_pattern_n};')
edit('video_correct_ddr_top.v',top)
t=(F/'build.tcl').read_text().replace((F/'sources').as_posix(),(O/'sources').as_posix())
anchor='compile -top_module video_correct_ddr_top'
t=rep(t,anchor,f'add_design {{{(O/"sources/lens_distort_coord.v").as_posix()}}}\nadd_design {{{(O/"sources/lens_autocrop_instance.v").as_posix()}}}\n'+anchor)
(O/'build.tcl').write_text(t,encoding='utf-8')
after={p.name:sha(p) for p in (O/'sources').iterdir() if p.is_file()}
m={'candidate':'B V2 R50/18mm lens-only native1920x1080 trial','original_inputs_sha256':original,'candidate_source_sha256':after,'changed_or_added':[n for n,h in after.items() if original.get(n)!=h],
'B_delivery_sha256':{n:sha(B/n) for n in ['rtl/perspective_core.v','rtl/lens_distort_coord.v','examples/lens_autocrop_instance.v','examples/r50_18mm_viewport.vh','calibration/r50_18mm_hdmi_trial.json']},'hardware_programmed':False,'timing_qualified':False,'calibration_deploy_to_fpga':False,'scope':'experimental lens-only whole-image crop,not paper-only composition'}
(O/'source_manifest.json').write_text(json.dumps(m,indent=2)+'\n')
print('CANDIDATE',O,'CHANGES',m['changed_or_added'])
