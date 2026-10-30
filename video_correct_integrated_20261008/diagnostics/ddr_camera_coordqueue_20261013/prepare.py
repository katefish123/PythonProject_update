"""Independent coordinate-lookahead clone, preserving all qualified hardware sources."""
from pathlib import Path
import hashlib,json,re,shutil
D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/'results'
O.mkdir(exist_ok=True)
base=R/'diagnostics/ddr_camera_hires_rowtrain_20261013'
sealed=R/'release/ddr_camera_hires_rowtrain_20261013'
manifest=json.loads((sealed/'source_hashes.json').read_text(encoding='utf-8-sig'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for p,h in manifest.items():assert sha(Path(p))==h,p
original=next(Path(p) for p in manifest if Path(p).name=='frame_processor.v')
s=original.read_text(encoding='utf-8-sig')
s=s.replace("// One pixel is in flight: conservative credit control includes B's 22-cycle pipe.",
    "// Coordinate lookahead reserves credits before B's 22-cycle pipe. Pixel\n// sampling/interpolation and the public source read remain single-outstanding.")
s=s.replace('parameter TIMEOUT_CYCLES=1000000','parameter TIMEOUT_CYCLES=1000000,COORD_QUEUE_BITS=4')
anchor=' wire req_valid,req_inside,req_error,out_valid,pending,reject_marker,reject_solver;'
assert s.count(anchor)==1
s=s.replace(anchor,''' localparam COORD_DEPTH=1<<COORD_QUEUE_BITS;
 reg [COORD_QUEUE_BITS-1:0] coord_wptr,coord_rptr;
 reg [COORD_QUEUE_BITS:0] coord_count,coord_reserved;
 reg [95:0] coord_addresses[0:COORD_DEPTH-1];
 reg [23:0] coord_tags[0:COORD_DEPTH-1];
 reg [15:0] coord_fractions[0:COORD_DEPTH-1];
 reg coord_inside[0:COORD_DEPTH-1];
 reg [23:0] coordinates_issued;
 reg [11:0] issue_x,issue_y;
 wire compute_phase=(state>=ISSUE && state<=WRITE);
 wire coord_pop=(state==WAIT_REQ && coord_count!=0);
'''+anchor)
s=s.replace(' wire dst_valid=(state==ISSUE);', ''' wire dst_valid=compute_phase && coordinates_issued<OUT_W*OUT_H && coord_reserved<COORD_DEPTH;
 wire coord_push=compute_phase && req_valid && (coord_count<COORD_DEPTH || coord_pop);
 wire coord_overflow=compute_phase && req_valid && coord_count==COORD_DEPTH && !coord_pop;''')
s=s.replace('.dst_x(dx),.dst_y(dy)','.dst_x(issue_x),.dst_y(issue_y)')
s=s.replace(' for(i=0;i<4;i=i+1)begin a[i]<=0;p[i]<=0;end', ''' coord_wptr<=0;coord_rptr<=0;coord_count<=0;coord_reserved<=0;
   coordinates_issued<=0;issue_x<=0;issue_y<=0;
   for(i=0;i<4;i=i+1)begin a[i]<=0;p[i]<=0;end''',1)
anchor='   done<=0;error<=fault;'
assert s.count(anchor)==1
s=s.replace(anchor,anchor+'''
   // Credits cover coordinates inside the pipeline, queued requests and the
   // actively sampled pixel. Returning a credit requires a real writer accept.
   if(compute_phase)begin
    if(dst_valid)begin
     coordinates_issued<=coordinates_issued+1'b1;
     if(issue_x==OUT_W-1)begin issue_x<=0;issue_y<=issue_y+1'b1;end
     else issue_x<=issue_x+1'b1;
    end
    case({dst_valid,write_valid&&write_ready})
     2'b10:coord_reserved<=coord_reserved+1'b1;
     2'b01:coord_reserved<=coord_reserved-1'b1;
     default:begin end
    endcase
    if(coord_push)begin
     coord_addresses[coord_wptr]<={a11,a01,a10,a00};
     coord_tags[coord_wptr]<=req_tag;
     coord_fractions[coord_wptr]<={fy,fx};
     coord_inside[coord_wptr]<=req_inside;
     coord_wptr<=coord_wptr+1'b1;
    end
    if(coord_pop)coord_rptr<=coord_rptr+1'b1;
    case({coord_push,coord_pop})
     2'b10:coord_count<=coord_count+1'b1;
     2'b01:coord_count<=coord_count-1'b1;
     default:begin end
    endcase
   end
''')
s=s.replace('(mem_valid&&mem_ready)||mem_rsp_valid||req_valid||out_valid||',
    '(mem_valid&&mem_ready)||mem_rsp_valid||coord_pop||out_valid||')
s=s.replace('     mode<=nearest;cycles<=0;completed_pixels<=0;', '''     mode<=nearest;cycles<=0;completed_pixels<=0;
     coord_wptr<=0;coord_rptr<=0;coord_count<=0;coord_reserved<=0;
     coordinates_issued<=0;issue_x<=0;issue_y<=0;''')
before='''    WAIT_REQ: if(req_valid)begin
     a[0]<=a00;a[1]<=a10;a[2]<=a01;a[3]<=a11;sample<=0;
     inside_saved<=req_inside;tag_saved<=req_tag;fx_saved<=fx;fy_saved<=fy;
     for(i=0;i<4;i=i+1)p[i]<=0;
     if(req_inside)state<=READ_SEND;else state<=RESPOND;
    end'''
after='''    WAIT_REQ: if(coord_pop)begin
     a[0]<=coord_addresses[coord_rptr][23:0];
     a[1]<=coord_addresses[coord_rptr][47:24];
     a[2]<=coord_addresses[coord_rptr][71:48];
     a[3]<=coord_addresses[coord_rptr][95:72];sample<=0;
     inside_saved<=coord_inside[coord_rptr];tag_saved<=coord_tags[coord_rptr];
     fx_saved<=coord_fractions[coord_rptr][7:0];fy_saved<=coord_fractions[coord_rptr][15:8];
     for(i=0;i<4;i=i+1)p[i]<=0;
     if(coord_inside[coord_rptr])state<=READ_SEND;else state<=RESPOND;
    end'''
assert s.count(before)==1
s=s.replace(before,after)
s=s.replace('if(busy&&(reject_marker||reject_solver||watchdog==TIMEOUT_CYCLES-1))begin',
    'if(busy&&(reject_marker||reject_solver||coord_overflow||watchdog==TIMEOUT_CYCLES-1))begin')
s=s.replace('    if(watchdog==TIMEOUT_CYCLES-1)fault<=1;', '''    coord_count<=0;coord_reserved<=0;coord_wptr<=0;coord_rptr<=0;
    if(coord_overflow||watchdog==TIMEOUT_CYCLES-1)fault<=1;''')
(O/'frame_processor.v').write_text(s,encoding='utf-8')
flow=(base/'results/build.tcl').read_text(encoding='utf-8-sig')
before='add_design {'+original.as_posix()+'}'
assert flow.count(before)==1
flow=flow.replace(before,'add_design {'+(O/'frame_processor.v').as_posix()+'}')
(O/'build.tcl').write_text(flow,encoding='utf-8')
paths=[Path(m[1]) for line in flow.splitlines() if (m:=re.fullmatch(r'add_design \{(.+)\}',line))]
paths+=[R/'constr/board_ddr.fdc']
(O/'source_hashes.json').write_text(json.dumps({str(p):sha(p) for p in paths},indent=2)+'\n',encoding='utf-8')
config=json.loads((base/'results/configuration.json').read_text(encoding='utf-8-sig'))
config.update(base_release='release/ddr_camera_hires_rowtrain_20261013',coordinate_lookahead_credits=16,
    public_source_reads_outstanding=1,processed_pixel_samples_outstanding=1,
    note='Only frame processor scheduling changed; immutable source and single source request interface preserved. Source/result dimensions and all thresholds unchanged. Physical speed acceptance pending.')
(O/'configuration.json').write_text(json.dumps(config,indent=2)+'\n',encoding='utf-8')
for p in list((base/'results').glob('*.hex'))+[base/'results/fixture.json']:
    shutil.copyfile(p,O/p.name)
for p in base.glob('*.sv'):shutil.copyfile(p,D/p.name)
for p in list((base/'results').glob('tb*.sv'))+list((base/'results').glob('tb*.do')):
    content=p.read_text(encoding='utf-8-sig').replace(base.as_posix(),D.as_posix()).replace(original.as_posix(),(O/'frame_processor.v').as_posix())
    for path in manifest:
        old=Path(path)
        if old.parent==base/'results' and old.suffix=='.v':
            content=content.replace((O/old.name).as_posix(),old.as_posix())
    (O/p.name).write_text(content,encoding='utf-8')
shutil.copyfile(base/'results/simulation_cases.json',O/'simulation_cases.json')
print('Coordinate lookahead clone prepared: only frame_processor RTL changed, stable image untouched.')
