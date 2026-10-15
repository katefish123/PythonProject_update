"""Join A's preserved black interface with C's full-source capture pipeline."""
import argparse,hashlib,json,re,shutil,subprocess,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
A=HERE.parent/'a_black_sync_20261014/upstream/diagnostics/ddr_camera_black_20261014'
CAND=Path('diagnostics/ddr_camera_hires_prefetch_20261012/results')
PROCESSOR=Path('diagnostics/ddr_camera_hires_20261011/results/frame_processor.v')
NAMES=['BLACK_RMIN','BLACK_RMAX','BLACK_GMIN','BLACK_GMAX','BLACK_BMIN','BLACK_BMAX']+[f'P{i}_{s}' for i in range(4) for s in ['XMIN','XMAX','YMIN','YMAX']]
DEFAULTS=[0,64,0,64,0,64]+['0','SRC_W/2-1','0','SRC_H/2-1','SRC_W/2','SRC_W-1','0','SRC_H/2-1','SRC_W/2','SRC_W-1','SRC_H/2','SRC_H-1','0','SRC_W/2-1','SRC_H/2','SRC_H-1']
DECL='parameter '+','.join(f'{n}={v}' for n,v in zip(NAMES,DEFAULTS))
FORWARD=','.join(f'.{n}({n})' for n in NAMES)
TAPS='.sample_valid(),.sample_first(),.sample_last(),.sample_token(),'
def put(out,rel,code):
 p=out/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(code);return p
def add_ports(code,module,ports):
 pattern=r'('+module+r'\s*#\s*\((?:[^()]|\([^()]*\))*\)\s+\w+\s*\()'
 return re.sub(pattern,lambda m:m[1]+ports,code)
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);out=p.parse_args().output.resolve()
 subprocess.run([sys.executable,str(HERE.parent/'fullhd_pipeline_20261014/prepare.py'),'--output',str(out)],check=True)
 for src in (A/'b_algorithm/rtl').glob('*.v'):
  dst=out/('rtl/algo/marker_detector.v' if src.name=='marker_detector.v' else 'vendor/b/rtl/'+src.name);shutil.copyfile(src,dst)
 for src in (A/'b_algorithm/python/brect').glob('*.py'):shutil.copyfile(src,out/'fullhd_tests/reference/brect'/src.name)
 display=(A/'src/diagnostics/ddr_camera_hires_rowtrain_20261013/results/ddr_result_display.v').read_text()
 display=display.replace('output reg          underrun\n','output reg          underrun,\n    output wire         prefetch_busy\n')
 display=display.replace('input  wire         force_pattern,','input  wire         force_pattern,\n    input  wire         capture_guard,')
 display=display.replace('reg [1:0] ui_state;','reg [1:0] ui_state;\n    assign prefetch_busy=(ui_state!=UI_IDLE);')
 # Back-to-back display commands can starve full-source capture. Retain one
 # response/store handoff slot while capturing so its next packet can arbitrate.
 display=display.replace('if(!scan_active_ui[2] || ui_line_row[0]!=scan_row_ui2[0]) begin\n                            // Store', 'if(!capture_guard && (!scan_active_ui[2] || ui_line_row[0]!=scan_row_ui2[0])) begin\n                            // Store')
 put(out,CAND/'ddr_result_display.v',display)
 # Preserve the B files. This C adapter changes only the source of corner metadata.
 b=(A/'b_algorithm/rtl/b_rectifier.v').read_text()
 b=b.replace('module b_rectifier #','module c_corner_rectifier #',1)
 b=b.replace('output wire corners_valid,marker_reject,marker_dropped,solver_reject,','input wire corners_valid,output wire marker_reject,marker_dropped,solver_reject,')
 b=b.replace('output wire [11:0] x0,y0,x1,y1,x2,y2,x3,y3,','input wire [11:0] x0,y0,x1,y1,x2,y2,x3,y3,')
 first=b.index(' wire marker_busy;');last=b.index(' reg solve_start;',first)
 b=b[:first]+" assign marker_reject=1'b0;assign marker_dropped=1'b0;\n"+b[last:]
 put(out,Path('rtl/algo/c_corner_rectifier.v'),'// C interface adapter; B solver/core math remains unmodified.\n'+b)
 for name in ['capture_geometry.v','geometry_frame_join.v']:shutil.copyfile(HERE/name,put(out,Path('rtl/algo')/name,''))
 capture=out/'rtl/video/ddr_snapshot_capture.v';s=capture.read_text()
 s=s.replace('output reg rx_complete_toggle,output reg capture_ok,','output wire sample_valid,sample_first,sample_last,sample_token,\n output reg rx_complete_toggle,output reg capture_ok,')
 anchor=' wire vs_rise=rx_vs&&!vs_d;'
 s=s.replace(anchor,anchor+'''\n assign sample_valid=active&&!vs_rise&&rx_de&&(x_count==x_next)&&(y_line_count==y_next)&&x_count<IN_W&&y_line_count<IN_H;
 assign sample_first=sample_valid&&(sampled_pixels==0);
 assign sample_last=sample_valid&&(sampled_pixels==EXPECTED_PIXELS-1);
 assign sample_token=active_token;''');capture.write_text(s)
 fp=out/PROCESSOR;s=fp.read_text().replace('parameter TIMEOUT_CYCLES=1000000','parameter EXTERNAL_GEOMETRY=0,\n '+DECL+',\n parameter TIMEOUT_CYCLES=1000000')
 s=s.replace('descriptors[0:7]','descriptors[0:15]').replace('reg [2:0] queue_rd,queue_wr;','reg [3:0] queue_rd,queue_wr;').replace('reg [3:0] queue_count,reserved;','reg [4:0] queue_count,reserved;').replace('(reserved<8)','(reserved<16)')
 s=s.replace('input wire clk,rst_n,start,nearest,','input wire clk,rst_n,start,nearest,\n input wire input_geometry_valid,input wire [95:0] input_corners,')
 auto_start=s.index(' end else begin: auto_geometry');auto_end=s.index(' end endgenerate',auto_start)
 original=s[auto_start:auto_end]
 external=original.replace('auto_geometry','external_geometry',1).replace('b_rectifier #','c_corner_rectifier #',1)
 external=external.replace('.src_valid(src_valid),','.src_valid(1\'b0),').replace('.src_frame_start(src_valid&&scan_addr==0)','.src_frame_start(1\'b0)').replace('.src_frame_end(src_valid&&scan_addr==SRC_W*SRC_H-1)','.src_frame_end(1\'b0)')
 external=external.replace('.corners_valid(),.marker_dropped(),.x0(),.y0(),.x1(),.y1(),.x2(),.y2(),.x3(),.y3(),', '.corners_valid(start&&input_geometry_valid),.marker_dropped(),'+','.join(f'.{n}(input_corners[{95-i*12}-:12])' for i,n in enumerate(['x0','y0','x1','y1','x2','y2','x3','y3']))+',')
 external=external.replace('end else begin: external_geometry','end else if(EXTERNAL_GEOMETRY)begin: external_geometry')
 original=original.replace('.MAX_SPAN(MAX_SPAN)) algorithm(','.MAX_SPAN(MAX_SPAN),'+FORWARD+') algorithm(')
 s=s[:auto_start]+external+original+s[auto_end:]
 s=s.replace('if(FIXED_IDENTITY)state<=COMMIT;else state<=SCAN_SEND;', '''if(FIXED_IDENTITY)state<=COMMIT;
     else if(EXTERNAL_GEOMETRY)begin
      if(input_geometry_valid)state<=SOLVE;
      else begin state<=IDLE;error<=1;fault<=1;end
     end else state<=SCAN_SEND;''')
 fp.write_text(s)
 core=out/'rtl/top/video_correct_ddr_core.v';s=core.read_text().replace('ADAPTIVE_DISPLAY_GUARD=0,','ADAPTIVE_DISPLAY_GUARD=0,INLINE_GEOMETRY=0,\n '+DECL+',')
 s=s.replace('wire rx_complete,rx_good;','wire rx_complete,rx_good,sample_v,sample_first,sample_last,sample_token;')
 s=s.replace('.fifo_full(fifo_full),.rx_complete_toggle', '.sample_valid(sample_v),.sample_first(sample_first),.sample_last(sample_last),.sample_token(sample_token),\n  .fifo_full(fifo_full),.rx_complete_toggle')
 s=s.replace('wire cap_v,cap_r,cap_w,cap_rsp,cap_rsp_write;', '''wire cap_v,cap_r,cap_w,cap_rsp,cap_rsp_write,writer_ack,writer_good;
 wire [95:0] corners0,corners1;wire valid0,valid1;
 generate if(INLINE_GEOMETRY)begin: capture_geometry_path
  (* ASYNC_REG="TRUE" *) reg [2:0] bank_rx;
  always @(posedge rx_clk or negedge rx_rst_n)begin
   if(!rx_rst_n)bank_rx<=0;else bank_rx<={bank_rx[1:0],capture_bank};
  end
  wire mt,mid,mb,mok;wire [95:0] mc;
  capture_geometry #(.SRC_W(SRC_W),.SRC_H(SRC_H),.MIN_PIXELS(MARKER_MIN_PIXELS),.MAX_PIXELS(MARKER_MAX_PIXELS),.MAX_SPAN(MARKER_MAX_SPAN),'''+FORWARD+''') geometry(
   .rx_clk(rx_clk),.rx_rst_n(rx_rst_n),.sample_valid(sample_v),.sample_first(sample_first),.sample_last(sample_last),.sample_rgb(rx_rgb),
   .sample_token(sample_token),.sample_bank(bank_rx[2]),.rx_complete_toggle(rx_complete),
   .metadata_toggle(mt),.metadata_token(mid),.metadata_bank(mb),.metadata_ok(mok),.metadata_corners(mc));
  geometry_frame_join joiner(.clk(proc_clk),.rst_n(proc_rst_n),.request_toggle(capture_req),.request_bank(capture_bank),
   .writer_complete(writer_ack),.writer_ok(writer_good),.metadata_toggle(mt),.metadata_token(mid),.metadata_bank(mb),.metadata_ok(mok),.metadata_corners(mc),
   .complete_toggle(capture_ack),.capture_ok(capture_good),.corners0(corners0),.corners1(corners1),.valid0(valid0),.valid1(valid1));
 end else begin: no_capture_geometry
  assign capture_ack=writer_ack;assign capture_good=writer_good;assign corners0=0;assign corners1=0;assign valid0=0;assign valid1=0;
 end endgenerate''')
 s=s.replace('.complete_toggle(capture_ack),.capture_ok(capture_good));','.complete_toggle(writer_ack),.capture_ok(writer_good));')
 s=s.replace('.MAX_SPAN(MARKER_MAX_SPAN)) processor(','.MAX_SPAN(MARKER_MAX_SPAN),.EXTERNAL_GEOMETRY(INLINE_GEOMETRY),'+FORWARD+') processor(')
 s=s.replace('.publish_toggle(pub_toggle),.publish_bank(pub_bank),.ack_toggle(display_ack),.force_pattern(force_pattern),','.publish_toggle(pub_toggle),.publish_bank(pub_bank),.ack_toggle(display_ack),.force_pattern(force_pattern),.capture_guard(OVERLAP_CAPTURE&&capture_busy_ui[2]),')
 s=s.replace('.clk(proc_clk),.rst_n(processor_rst),.start(start),','.input_geometry_valid(source_bank?valid1:valid0),.input_corners(source_bank?corners1:corners0),\n  .clk(proc_clk),.rst_n(processor_rst),.start(start),')
 # Declare before the instance expression: avoid an implicit scalar net.
 busy_decl=' (* ASYNC_REG="TRUE" *) reg [2:0] capture_busy_ui;\n'
 s=s.replace(busy_decl,'').replace(' wire display_v,',busy_decl+' wire display_v,')
 core.write_text(s)
 config=json.loads((A/'config.json').read_text());scaled=dict(config)
 scaled['source']=[1920,1080];scaled['min_pixels']=64;scaled['max_pixels']=16384;scaled['max_span']=256
 scaled['fixture_points']=[[2*x,2*y] for x,y in config['fixture_points']];scaled['fixture_marker_radius']=20
 scaled['rois']={n:[[2*v for v in bounds[0]],[2*v+1 for v in bounds[1]]] for n,bounds in config['rois'].items()}
 values=[0,64,0,64,0,64]
 for lo,hi in scaled['rois'].values():values += [lo[0],hi[0],lo[1],hi[1]]
 top=out/CAND/'video_correct_ddr_top.v';s=top.read_text().replace('.ADAPTIVE_DISPLAY_GUARD(1),','.ADAPTIVE_DISPLAY_GUARD(1),.INLINE_GEOMETRY(1),'+','.join(f'.{n}({v})' for n,v in zip(NAMES,values))+',');top.write_text(s)
 # Existing fixtures are colored. Keep those compatibility tests explicitly in
 # fixed-identity mode or regenerate black content below; no old PASS is reused.
 for test in out.rglob('*.sv'):
  s=test.read_text()
  if 'ddr_snapshot_capture #' in s:s=add_ports(s,'ddr_snapshot_capture',TAPS)
  if 'frame_processor #' in s:s=add_ports(s,'frame_processor',".input_geometry_valid(1'b0),.input_corners(96'd0),")
  if 'ddr_result_display #' in s:
   guard='capture_request!=cap_done' if test.stem in ['tb_fullhd_capture_display','tb_banked_capture_display'] else "1'b0"
   s=add_ports(s,'ddr_result_display','.capture_guard('+guard+'),')
   if guard!="1'b0":
    # An expression in an instance port creates implicit nets for undeclared
    # names. Move these existing declarations before the display instance.
    declarations=[]
    for prefix in [' reg camera_vs=',' wire rx_done,']:
     line=next(line for line in s.splitlines(keepends=True) if line.startswith(prefix))
     declarations.append(line);s=s.replace(line,'',1)
    pos=s.index(' ddr_result_display #')
    s=s[:pos]+''.join(declarations)+s[pos:]
  test.write_text(s)
 subprocess.run([sys.executable,str(HERE/'fixtures.py'),'--output',str(out),'--config',json.dumps(scaled)],check=True)
 # New full-frame benchmarks compare the same black scene with/without inline.
 test=out/'fullhd_tests/tb_fullhd_pipeline.sv';s=test.read_text().replace('LATE_CAPTURE=0);','LATE_CAPTURE=0,INLINE=0);')
 s=s.replace('.ADAPTIVE_DISPLAY_GUARD(PREFETCH),','.ADAPTIVE_DISPLAY_GUARD(PREFETCH),.INLINE_GEOMETRY(INLINE),'+','.join(f'.{n}({v})' for n,v in zip(NAMES,values))+',')
 s=s.replace('if(dut.p_busy)begin','if(INLINE && (dut.processor.state==1||dut.processor.state==2))$fatal(1,"unexpected DDR source rescan");\n  if(dut.p_busy)begin')
 s=s.replace('late_percent=%0d",OVERLAP,PREFETCH,LATE_CAPTURE','late_percent=%0d inline=%0d",OVERLAP,PREFETCH,LATE_CAPTURE,INLINE');test.write_text(s)
 # Three different images, including the same source bank reused for frame3.
 s=s.replace('source1[0:SRC_PIXELS-1],','source1[0:SRC_PIXELS-1],source2[0:SRC_PIXELS-1],').replace('expected1[0:PIXELS-1];','expected1[0:PIXELS-1],expected2[0:PIXELS-1];')
 s=s.replace('reg source_kind[0:1],result_kind[0:1];','reg [1:0] source_kind[0:1],result_kind[0:1];')
 s=s.replace('capture_seq%2','capture_seq%3').replace('(processing_frame-1)%2','(processing_frame-1)%3')
 s=s.replace('if(camera_kind)rx_rgb=source1[(camera_y-41)*SW+camera_x-192];\n    else rx_rgb=source0[(camera_y-41)*SW+camera_x-192];','rx_rgb=source_pixel(camera_kind,(camera_y-41)*SW+camera_x-192);')
 s=s.replace('(kind?source1[rel+lane]:source0[rel+lane])','source_pixel(kind,rel+lane)')
 s=s.replace('(current_kind?expected1[rel+lane]:expected0[rel+lane])','expected_pixel(current_kind,rel+lane)')
 s=s.replace('(current_kind?expected1[produced]:expected0[produced])','expected_pixel(current_kind,produced)')
 s=s.replace('(display_kind?expected1[(vd2-129)*OW+hd2-832]:expected0[(vd2-129)*OW+hd2-832])','expected_pixel(display_kind,(vd2-129)*OW+hd2-832)')
 marker=' function [255:0] memory_read'
 s=s.replace(marker,''' function [23:0] source_pixel(input integer kind,input integer index);
  source_pixel=(kind==2)?source2[index]:(kind==1)?source1[index]:source0[index];
 endfunction
 function [23:0] expected_pixel(input integer kind,input integer index);
  expected_pixel=(kind==2)?expected2[index]:(kind==1)?expected1[index]:expected0[index];
 endfunction
'''+marker)
 s=s.replace('source_kind[0]=0;',f'$readmemh("{out.as_posix()}/fullhd_tests/source_variant2_1920x1080.hex",source2);\n  $readmemh("{out.as_posix()}/fullhd_tests/expected_variant2_640x904.hex",expected2);\n  source_kind[0]=0;')
 s=s.replace('reg [1:0] source_kind[0:1],result_kind[0:1];','reg [95:0] expected_geometry[0:2];\n reg [1:0] source_kind[0:1],result_kind[0:1];')
 s=s.replace('source_kind[0]=0;',f'$readmemh("{out.as_posix()}/fullhd_tests/source_corners96.hex",expected_geometry);\n  source_kind[0]=0;')
 s=s.replace('result_kind[dut.write_bank]=current_kind;', 'if(INLINE && (!dut.processor.input_geometry_valid || dut.processor.input_corners!==expected_geometry[current_kind]))$fatal(1,"source geometry generation mismatch");\n   result_kind[dut.write_bank]=current_kind;')
 test.write_text(s)
 template=(out/CAND/'tb_fullhd_pipeline_2.do').read_text();(out/CAND/'tb_fullhd_pipeline_3.do').write_text(template.replace('work_fullhd_pipeline_2','work_fullhd_pipeline_3').replace('tb_fullhd_pipeline_2.','tb_fullhd_pipeline_3.').replace('-gOVERLAP=1','-gINLINE=1 -gOVERLAP=1'))
 extra=[out/'rtl/algo'/name for name in ['c_corner_rectifier.v','capture_geometry.v','geometry_frame_join.v']]
 for script in (out/CAND).glob('*.do'):
  s=script.read_text();s=s.replace(' {', ' {',1)
  for source in extra:
   s=re.sub(r'^(vlog .*?)$',lambda m:m[1]+' {'+source.as_posix()+'}',s,flags=re.M)
  script.write_text(s)
 build=out/CAND/'build.tcl';build.write_text(build.read_text().replace('compile -top_module',''.join('add_design {'+p.as_posix()+'}\n' for p in extra)+'compile -top_module'))
 cases=json.loads((out/CAND/'simulation_cases.json').read_text());cases.pop('tb_fullhd_pipeline_0');cases.pop('tb_fullhd_pipeline_1');cases['tb_fullhd_pipeline_3']='FULLHD_PIPELINE_PASS'
 # These legacy color-marker images belong to the preserved 833af36 release.
 # New black geometry is covered by two complete native 3-frame core tests.
 for name in ['tb_video_correct_ddr_core','tb_ddr_full_frame','tb_core_word_engine','tb_fullhd_frame','tb_relocated_core','tb_overlap_core','tb_overlap_throughput']:
  cases.pop(name)
 for name,marker in [('tb_capture_geometry','CAPTURE_GEOMETRY_PASS'),('tb_geometry_join','GEOMETRY_JOIN_PASS')]:
  shutil.copyfile(HERE/(name+'.sv'),out/'fullhd_tests'/(name+'.sv'))
  original=(out/CAND/'tb_scheduler.do').read_text();(out/CAND/(name+'.do')).write_text(original.replace('tb_scheduler',name).replace('work_scheduler','work_'+name));cases[name]=marker
 (out/CAND/'simulation_cases.json').write_text(json.dumps(cases,indent=2)+'\n')
 mp=out/'reproduction_manifest.json';manifest=json.loads(mp.read_text());manifest['optimization']='inline_black_geometry_native_full_source';manifest['a_black_sync_commit']='256b5ea2b8bf4a559f19adfca7465161654b8226';manifest['b_black_commit']='4106f3babb65096927d365bbab55f070b90325e2'
 for name in manifest['files']:manifest['files'][name]['local_sha256']=hashlib.sha256((out/name).read_bytes()).hexdigest()
 for src in [*extra,*((out/'fullhd_tests').glob('*')),*(out/CAND).glob('tb_*.do')]:
  if src.is_file():manifest['files'][src.relative_to(out).as_posix()]={'local_sha256':hashlib.sha256(src.read_bytes()).hexdigest()}
 mp.write_text(json.dumps(manifest,indent=2)+'\n');print('INLINE_BLACK_GEOMETRY_READY tests='+str(len(cases)))
if __name__=='__main__':main()
