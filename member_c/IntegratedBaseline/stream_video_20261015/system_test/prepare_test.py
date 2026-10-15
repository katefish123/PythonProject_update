from pathlib import Path
import re,argparse
HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('--baseline',type=Path,default=Path('D:/FPGA/output/c_stream_board_v1_20261015'));args=parser.parse_args()
BASE=args.baseline.resolve()
s=(BASE/'fullhd_tests/tb_fullhd_pipeline.sv').read_text()
s=s.replace('module tb_fullhd_pipeline #(parameter OVERLAP=1,FRAMES=3,PREFETCH=0,LATE_CAPTURE=0,INLINE=0);','module tb_stream_system #(parameter FULLHD=0,STRESS=0,OVERLAP=1,FRAMES=3,PREFETCH=0,LATE_CAPTURE=95,INLINE=1);')
s=s.replace('localparam SW=1920,SH=1080,OW=640,OH=904,SRC_PIXELS=SW*SH,PIXELS=OW*OH;', '''localparam SW=FULLHD?1920:128,SH=FULLHD?1080:48,OW=FULLHD?768:32,OH=FULLHD?1080:48,SRC_PIXELS=SW*SH,PIXELS=OW*OH;
 localparam HS=FULLHD?44:4,HB=FULLHD?148:8,HF=FULLHD?88:256,VS=FULLHD?5:2,VB=FULLHD?36:4,VF=FULLHD?4:4;
 localparam HX0=HS+HB,VY0=VS+VB,HT=HS+HB+SW+HF,VT=VS+VB+SH+VF;
 localparam CAM_HT=(!FULLHD&&STRESS)?HS+HB+SW+8:HT;
 localparam DX0=HX0+(SW-OW)/2,DY0=VY0+(SH-OH)/2;
 localparam string FIXTURES=FULLHD?"'''+str(HERE/'fixtures/fullhd').replace('\\','/')+'''":"'''+str(HERE/'fixtures/reduced').replace('\\','/')+'''";''')
s=s.replace('always #18.5185185 proc_clk','always #9.259259259 proc_clk')
s=s.replace('video_correct_ddr_core #','video_correct_ddr_stream_core #')
s=s.replace('.CAPTURE_BURST_BEATS(8),.IN_W(SW)', '.H_SYNC(HS),.H_BACK(HB),.H_ACTIVE(SW),.H_FRONT(HF),.V_SYNC(VS),.V_BACK(VB),.V_ACTIVE(SH),.V_FRONT(VF),.CAPTURE_BURST_BEATS(8),.IN_W(SW)')
roi={'P0_XMIN':(580,27),'P0_XMAX':(681,42),'P0_YMIN':(86,0),'P0_YMAX':(187,11),'P1_XMIN':(1410,85),'P1_XMAX':(1511,101),'P1_YMIN':(174,0),'P1_YMAX':(275,14),'P2_XMIN':(1480,95),'P2_XMAX':(1581,111),'P2_YMIN':(920,34),'P2_YMAX':(1021,47),'P3_XMIN':(226,17),'P3_XMAX':(327,33),'P3_YMIN':(886,31),'P3_YMAX':(987,47)}
for key,(old,new) in roi.items():s=s.replace(f'.{key}({old})',f'.{key}(FULLHD?{old}:{new})')
s=s.replace('.MARKER_MIN_PIXELS(64)','.MARKER_MIN_PIXELS(FULLHD?64:16)').replace('.MARKER_MAX_SPAN(256)','.MARKER_MAX_SPAN(FULLHD?256:16)')
s=s.replace('wire[2047:0]burst_payload;wire[3:0]engine_reason;','wire[2047:0]burst_payload,source_block_payload;wire source_block_cmd;wire[3:0]engine_reason;')
s=s.replace('.cmd_burst_data(burst_payload),.cmd_valid(cmd_v)', '.cmd_source_block(source_block_cmd),.rsp_source_block(source_block_payload),.cmd_burst_data(burst_payload),.cmd_valid(cmd_v)')
s=s.replace('.cmd_source_block(1\'b0),.rsp_source_block()', '.cmd_source_block(source_block_cmd),.rsp_source_block(source_block_payload)')
s=s.replace('rx_vs=(camera_y<5);','rx_vs=(camera_y<VS);')
s=s.replace('camera_x>=192&&camera_x<2112&&camera_y>=41&&camera_y<1121','camera_x>=HX0&&camera_x<HX0+SW&&camera_y>=VY0&&camera_y<VY0+SH')
s=s.replace('(camera_y-41)*SW+camera_x-192','(camera_y-VY0)*SW+camera_x-HX0')
s=s.replace('camera_x==2199','camera_x==CAM_HT-1').replace('camera_y==1124','camera_y==VT-1')
s=s.replace('read_delay<=28+((physical_reads%128==127)?100:0);','read_delay<=((!FULLHD&&STRESS&&(araddr<SRC_PIXELS||(araddr>=SRC1&&araddr<SRC1+SRC_PIXELS)))?96:28)+((physical_reads%128==127)?100:0);')
s=s.replace('dut.processor.input_geometry_valid','dut.stream_path.processor.input_geometry_valid').replace('dut.processor.input_corners','dut.stream_path.processor.input_corners')
s=re.sub(r'  if\(INLINE && \(dut.processor.state==1\|\|dut.processor.state==2\)\)\$fatal[^\n]*\n','',s)
s=re.sub(r'  if\(dut.p_busy\)begin\n   case\(dut.processor.state\).*?\n  end\n', '''  if(dut.p_busy)begin
   case(dut.stream_path.processor.state)
    1,2,3:solve_cycles=solve_cycles+1;
    4:read_cycles=read_cycles+1;
    default:other_cycles=other_cycles+1;
   endcase
  end
''',s,flags=re.S)
for name,replace in [('wr_v','write_valid'),('wr_ready','write_ready'),('wr_a','write_addr'),('wr_rgb','write_rgb')]:s=s.replace('dut.'+name,'dut.stream_path.'+replace)
s=s.replace('FULLHD_PHASE_PROFILE mode=%0d frame=%0d scan=%0d solve=%0d read=%0d interp=%0d write=%0d other=%0d processing_ns=%0d",OVERLAP,processing_frame,scan_cycles,solve_cycles,read_cycles,interp_cycles,write_cycles,other_cycles', 'STREAM_PHASE_PROFILE mode=%0d frame=%0d solver_commit=%0d streaming_run=%0d writer_drain=%0d processing_ns=%0d",OVERLAP,processing_frame,solve_cycles,read_cycles,other_cycles')
s=s.replace('hd2>=832&&hd2<1472&&vd2>=129&&vd2<1033','hd2>=DX0&&hd2<DX0+OW&&vd2>=DY0&&vd2<DY0+OH')
s=s.replace('(vd2-129)*OW+hd2-832','(vd2-DY0)*OW+hd2-DX0').replace('hd2-832,vd2-129','hd2-DX0,vd2-DY0').replace('hd2==1471&&vd2==1032','hd2==DX0+OW-1&&vd2==DY0+OH-1')
s=re.sub(r'  \$readmemh\("[^\n]+source_1920x1080.hex",source0\);','  $readmemh({FIXTURES,"/source0.hex"},source0);',s)
s=re.sub(r'  \$readmemh\("[^\n]+source_variant_1920x1080.hex",source1\);','  $readmemh({FIXTURES,"/source1.hex"},source1);',s)
s=re.sub(r'  \$readmemh\("[^\n]+source_variant2_1920x1080.hex",source2\);','  $readmemh({FIXTURES,"/source2.hex"},source2);',s)
for i,suffix in enumerate(['','variant_','variant2_']):
 s=re.sub(r'  \$readmemh\("[^\n]+expected_'+suffix+r'640x904.hex",expected'+str(i)+r'\);',f'  $readmemh({{FIXTURES,"/expected{i}.hex"}},expected{i});',s)
s=re.sub(r'  \$readmemh\("[^\n]+source_corners96.hex",expected_geometry\);','  $readmemh({FIXTURES,"/corners96.hex"},expected_geometry);',s)
s=s.replace('$display("FULLHD_PIPELINE_CONFIG overlap=', '$display("STREAM_SYSTEM_CONFIG native=%0d proc54MHz source%0dx%0d output%0dx%0d overlap=').replace('OVERLAP,PREFETCH,LATE_CAPTURE,INLINE);','FULLHD,SW,SH,OW,OH,OVERLAP,PREFETCH,LATE_CAPTURE,INLINE);')
s=s.replace('FULLHD_PIPELINE_PASS','STREAM_SYSTEM_PASS')
s=s.replace('if(underrun&&image_valid)$fatal(1,"full-HD display underrun");','if(underrun&&image_valid)$fatal(1,"display underrun native=%0d hc=%0d vc=%0d frame=%0d generation=%0d",FULLHD,dut.display_reader.hc,dut.display_reader.vc,published,dut.display_reader.display_gen);')
s=s.replace('if(OVERLAP&&overlap_beats==0)', 'if(OVERLAP&&LATE_CAPTURE==0&&overlap_beats==0)')
s=s.replace('initial begin #(64\'d10000000000)', 'initial begin #(FULLHD?64\'d10000000000:64\'d100000000)')
s=s.replace('integer proc_tick=0,last_start=0,interval_sum=0,interval_count=0,avg_interval=0;', 'integer proc_tick=0,last_start=0,interval_sum=0,interval_count=0,avg_interval=0;time previous_publish=0;')
s=s.replace('seen_pub=dut.pub_toggle;published=published+1;', 'seen_pub=dut.pub_toggle;published=published+1;'+'''\n   if(previous_publish!=0)$display("STREAM_PUBLISH_INTERVAL frame=%0d ns=%0d",published,$time-previous_publish);previous_publish=$time;''')
s=s.replace('if(wdata[lane*32+:24]!==source_pixel', "if(wdata[lane*32+24+:8]!==0)$fatal(1,\"capture word padding byte nonzero\");\n    for(integer lane=0;lane<8;lane=lane+1)\n     if(wdata[lane*32+:24]!==source_pixel")
s=s.replace('if(wdata[lane*32+:24]!==expected_pixel', "if(wdata[lane*32+24+:8]!==0)$fatal(1,\"result word padding byte nonzero\");\n    for(integer lane=0;lane<8;lane=lane+1)\n     if(wdata[lane*32+:24]!==expected_pixel")
(HERE/'tb_stream_system.sv').write_text(s)
# Keep baseline source-list order, replace only the top-level fixture under test.
template=(BASE/'diagnostics/ddr_camera_hires_prefetch_20261012/results/tb_fullhd_pipeline_3.do').read_text()
line=next(x for x in template.splitlines() if x.startswith('vlog '))
sources=re.findall(r'\{([^}]+)\}',line)
sources=[x for x in sources if not x.endswith('/tb_fullhd_pipeline.sv')]
sources += [str(x).replace('\\','/') for x in (BASE/'rtl/stream').glob('*.v')]
sources += [str(BASE/'rtl/top/frame_session_overlap_stream.v'),str(BASE/'rtl/top/video_correct_ddr_stream_core.v'),str(HERE/'tb_stream_system.sv')]
(HERE/'sources.json').write_text(__import__('json').dumps(sources,indent=2))
print('SYSTEM_BENCH_READY sources='+str(len(sources)))
