"""Merge board-proven capture/preview into C's independent black candidate.

This generator never programs hardware and never grants acceptance.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from prepare_engine import transform

HERE=Path(__file__).resolve().parent
BOARD=HERE/'board_snapshot'
CAND=Path('diagnostics/ddr_camera_hires_prefetch_20261012/results')
FP=Path('diagnostics/ddr_camera_hires_20261011/results/frame_processor.v')


def add_ports(code,module,ports):
    pattern=r'('+module+r'\s*#\s*\((?:[^()]|\([^()]*\))*\)\s+\w+\s*\()'
    return re.sub(pattern,lambda m:m[1]+ports,code)


def merge(out):
    for name,digest in json.loads((BOARD/'manifest.json').read_text())['files'].items():
        assert hashlib.sha256((BOARD/name).read_bytes()).hexdigest()==digest,name
    # Byte-preserved underlying writer, separately versioned bank wrapper.
    assert (HERE/'writer/ddr_capture_writer.v').read_bytes()==(BOARD/'rtl/memory/ddr_capture_writer.v').read_bytes()
    writer=(HERE/'writer/ddr_capture_writer.v').read_text()+'\n'+(HERE/'writer/ddr_capture_writer_banked.v').read_text()
    (out/'rtl/memory/ddr_capture_writer.v').write_text(writer)
    engine=out/CAND/'ddr_word_engine.v'
    engine.write_text(transform(engine.read_text()))
    capture=out/'rtl/video/ddr_snapshot_capture.v';s=capture.read_text()
    s=s.replace('output reg rx_complete_toggle,output reg capture_ok,','output reg rx_complete_toggle,output reg capture_ok,output reg[3:0]failure_reason,')
    s=s.replace('request_sync<=0;rx_complete_toggle<=0;', 'failure_reason<=0;request_sync<=0;rx_complete_toggle<=0;')
    s=s.replace('active<=1;active_token<=request_sync[2];', 'failure_reason<=0;active<=1;active_token<=request_sync[2];')
    s=s.replace('capture_ok<=finish_candidate&&!frame_bad&&!fifo_overflow;', '''capture_ok<=finish_candidate&&!frame_bad&&!fifo_overflow;
    failure_reason<=fifo_overflow?4'd13:frame_bad||y_line_count!=IN_H||x_count!=0?4'd12:!finish_candidate?4'd15:4'd0;''')
    capture.write_text(s)
    fp=out/FP;s=fp.read_text().replace('output wire geometry_valid','output reg[3:0]failure_reason,output wire geometry_valid')
    s=s.replace('state<=IDLE;done<=0;error<=0;', 'failure_reason<=0;state<=IDLE;done<=0;error<=0;')
    s=s.replace('IDLE: if(start&&!fault)begin','IDLE: if(start&&!fault)begin\n     failure_reason<=0;')
    s=s.replace('else begin state<=IDLE;error<=1;fault<=1;end','else begin failure_reason<=3;state<=IDLE;error<=1;fault<=1;end')
    s=s.replace('if(out_tag!={dy,dx})begin error<=1;', 'if(out_tag!={dy,dx})begin failure_reason<=11;error<=1;')
    s=s.replace('if(busy&&(reject_marker||reject_solver||watchdog==TIMEOUT_CYCLES-1))begin',
                'if(busy&&(reject_marker||reject_solver||watchdog==TIMEOUT_CYCLES-1))begin\n    failure_reason<=reject_marker?4\'d3:reject_solver?4\'d4:4\'d5;')
    fp.write_text(s)
    join=out/'rtl/algo/geometry_frame_join.v';s=join.read_text()
    s=s.replace('input wire writer_complete,writer_ok,','input wire [3:0]writer_reason,output reg[3:0]failure_reason,\n input wire writer_complete,writer_ok,')
    s=s.replace('reg [1:0] writer_settle;', 'reg [1:0] writer_settle;\n reg[3:0]reason0,reason1,reason2,writer_reason_held;')
    s=s.replace('writer_sync<=0;ok_sync<=0;', 'failure_reason<=0;reason0<=0;reason1<=0;reason2<=0;writer_reason_held<=0;writer_sync<=0;ok_sync<=0;')
    s=s.replace('writer_sync<={writer_sync[1:0],writer_complete};', 'reason0<=writer_reason;reason1<=reason0;reason2<=reason1;\n   writer_sync<={writer_sync[1:0],writer_complete};')
    s=s.replace('request_seen<=request_toggle;metadata_ready<=0;', 'failure_reason<=0;request_seen<=request_toggle;metadata_ready<=0;')
    s=s.replace('writer_good<=ok_sync[2];writer_ready<=1;', 'writer_good<=ok_sync[2];writer_reason_held<=reason2;writer_ready<=1;')
    s=s.replace('complete_toggle<=request_toggle;capture_ok<=writer_good&&geometry_good;',
                "complete_toggle<=request_toggle;capture_ok<=writer_good&&geometry_good;\n     failure_reason<=!writer_good?(writer_reason_held!=0?writer_reason_held:4'd2):!geometry_good?4'd3:4'd0;")
    join.write_text(s)
    session=out/'rtl/top/frame_session.v';s=session.read_text();cut=s.index('module frame_session_overlap')
    serial=s[:cut];overlap=s[cut:]
    serial=serial.replace('output reg [31:0] good_frames,rejected_frames','output reg capture_rejected,output wire[3:0]phase,output reg [31:0] good_frames,rejected_frames')
    serial=serial.replace('reg [3:0] state;', 'reg [3:0] state;assign phase=state;')
    serial=serial.replace('state<=WAIT_ENABLE;timer<=0;capture_request<=0;', 'capture_rejected<=0;state<=WAIT_ENABLE;timer<=0;capture_request<=0;')
    serial=serial.replace('processor_start<=0;\n            case', 'processor_start<=0;capture_rejected<=0;\n            case')
    serial=serial.replace('rejected_frames<=rejected_frames+1;\n                            frame_error', 'capture_rejected<=1;rejected_frames<=rejected_frames+1;\n                            frame_error')
    overlap=overlap.replace('output reg [31:0] good_frames,', 'output reg capture_rejected,output wire[3:0]phase,\n output reg [31:0] good_frames,')
    overlap=overlap.replace('assign source_ready=ready_valid;', "assign source_ready=ready_valid;\n assign phase=working?4'd5:(state==CLEAR)?4'd9:(state==RETRY)?4'd8:(state==PUBLISH)?4'd6:(state==DISPLAY_WAIT)?4'd7:capture_inflight?4'd2:4'd0;")
    overlap=overlap.replace('state<=WAIT_FRAME;cap_state<=CAP_IDLE;', 'capture_rejected<=0;state<=WAIT_FRAME;cap_state<=CAP_IDLE;')
    overlap=overlap.replace('processor_start<=0;\n   case', 'processor_start<=0;capture_rejected<=0;\n   case')
    overlap=overlap.replace('else begin cap_rejected<=cap_rejected+1\'b1;', "else begin capture_rejected<=1;cap_rejected<=cap_rejected+1'b1;")
    session.write_text(serial+overlap)
    core=out/'rtl/top/video_correct_ddr_core.v';s=core.read_text()
    s=s.replace('parameter FIFO_ADDR_BITS=9,', 'parameter CAPTURE_BURST_BEATS=1,\n parameter FIFO_ADDR_BITS=9,')
    s=s.replace('output wire cmd_valid,cmd_write,', '''output reg[3:0]diagnostic_reason,output wire[3:0]diagnostic_phase,
 input wire preview_valid,overlay_on,input wire[23:0]preview_rgb,overlay_rgb,
 output wire[11:0]scan_x,scan_y,output wire scan_de,scan_start,scan_reset_n,
 output wire[2047:0]cmd_burst_data,output wire cmd_valid,cmd_write,''')
    s=s.replace('fault_sync[1:0],memory_fault}', 'fault_sync[1:0],memory_fault||selftest_failed}')
    s=s.replace('wire p_done,p_error,p_busy,writer_drained,writer_fault;', '''wire p_done,p_error,p_busy,writer_drained,writer_fault;
 wire capture_rejected;wire[3:0]rx_failure_reason,writer_reason,capture_reason,processor_reason;
 (* ASYNC_REG="TRUE" *) reg[3:0]capture_reason0,capture_reason1,capture_reason2;
 always @(posedge proc_clk or negedge proc_rst_n)begin
  if(!proc_rst_n)begin capture_reason0<=0;capture_reason1<=0;capture_reason2<=0;diagnostic_reason<=0;end
  else begin
   capture_reason0<=capture_reason;capture_reason1<=capture_reason0;capture_reason2<=capture_reason1;
   if(fault_sync[2])diagnostic_reason<=7;
   else if(writer_fault)diagnostic_reason<=6;
   else if(p_error)diagnostic_reason<=processor_reason;
   else if(capture_rejected)diagnostic_reason<=capture_reason2!=0?capture_reason2:4'd2;
   else if(complete_pulse)diagnostic_reason<=0;
   else if(input_wait)diagnostic_reason<=1;
  end
 end''')
    # Move procedural dependencies ahead of diagnostic always block.
    s=s.replace(' reg done_pending,complete_pulse;\n','').replace(' wire p_done,',' reg done_pending,complete_pulse;\n wire p_done,',1)
    s=s.replace('.rejected_frames(rejected_frames));', '.rejected_frames(rejected_frames),.phase(diagnostic_phase),.capture_rejected(capture_rejected));')
    s=s.replace('.capture_ok(rx_good),.fifo_wr_en', '.capture_ok(rx_good),.failure_reason(rx_failure_reason),.fifo_wr_en')
    s=s.replace('.writer_complete(writer_ack),.writer_ok(writer_good),', '.writer_complete(writer_ack),.writer_ok(writer_good),.writer_reason(writer_reason),.failure_reason(capture_reason),')
    s=s.replace("assign capture_ack=writer_ack;assign capture_good=writer_good;", "assign capture_ack=writer_ack;assign capture_good=writer_good;assign capture_reason=writer_reason;")
    s=s.replace('ddr_capture_writer_banked #(.SRC_W(SRC_W),.SRC_H(SRC_H))', 'ddr_capture_writer_banked #(.SRC_W(SRC_W),.SRC_H(SRC_H),.BURST_BEATS(CAPTURE_BURST_BEATS))')
    s=s.replace('.rx_capture_ok(rx_good),', '.rx_capture_ok(rx_good),.rx_failure_reason(rx_failure_reason),')
    s=s.replace('.cmd_valid(cap_v),', '.cmd_burst_data(cmd_burst_data),.cmd_valid(cap_v),',1)
    s=s.replace('.complete_toggle(writer_ack),.capture_ok(writer_good));', '.complete_toggle(writer_ack),.capture_ok(writer_good),.failure_reason(writer_reason));')
    s=s.replace('.completed_pixels(p_pixels),.geometry_valid());', '.completed_pixels(p_pixels),.geometry_valid(),.failure_reason(processor_reason));')
    s=s.replace('.force_pattern(force_pattern),.capture_guard', '.preview_valid(preview_valid),.preview_rgb(preview_rgb),.overlay_on(overlay_on),.overlay_rgb(overlay_rgb),\n  .scan_x(scan_x),.scan_y(scan_y),.scan_de(scan_de),.scan_start(scan_start),.scan_reset_n(scan_reset_n),\n  .force_pattern(force_pattern),.capture_guard')
    core.write_text(s)
    display=out/CAND/'ddr_result_display.v';s=display.read_text()
    s=s.replace('input  wire         force_pattern,', '''input wire preview_valid,overlay_on,input wire[23:0]preview_rgb,overlay_rgb,
    output wire[11:0]scan_x,scan_y,output wire scan_de,scan_start,scan_reset_n,
    input  wire         force_pattern,''')
    s=s.replace('wire [11:0] active_x=hc-(H_SYNC+H_BACK);', '''wire [11:0] active_x=hc-(H_SYNC+H_BACK);
    assign scan_x=active_x;assign scan_y=vc-(V_SYNC+V_BACK);
    assign scan_de=vtc_de;assign scan_start=frame_start;assign scan_reset_n=pix_local_rst_n;''')
    s=s.replace('else if(pixel_pattern) rgb<=pixel_pattern_rgb;', '''else if(pixel_pattern)begin
                if(!force_pattern&&preview_valid)rgb<=preview_rgb;else rgb<=pixel_pattern_rgb;
            end''')
    s=s.replace('            else rgb<=0;\n', '            else rgb<=0;\n            if(pixel_de&&overlay_on&&!force_pattern)rgb<=overlay_rgb;\n')
    display.write_text(s)
    for name in ['rx_preview.v','status_overlay.v']:
        shutil.copyfile(BOARD/'rtl/video'/name,out/'rtl/video'/name)
    top=out/CAND/'video_correct_ddr_top.v';s=top.read_text();board=(BOARD/CAND/'video_correct_ddr_top.v').read_text()
    start=board.index(' wire[23:0]rgb,preview_rgb,overlay_rgb;');end=board.index(' video_correct_ddr_core #',start)
    s=s.replace(' wire [23:0] rgb;\n',board[start:end])
    assert 'wire[3:0]diagnostic_reason' in s, 'top RGB declaration changed'
    s=s.replace(' wire [27:0] cmd_a;', ' wire[2047:0]capture_burst_data;wire [27:0] cmd_a;')
    s=s.replace('video_correct_ddr_core #(', 'video_correct_ddr_core #(.CAPTURE_BURST_BEATS(8),',1)
    begin=board.index('  .diagnostic_reason(diagnostic_reason)');end=board.index('  .cmd_burst_data',begin)
    s=s.replace('  .cmd_valid(cmd_v),', board[begin:end]+'  .cmd_burst_data(capture_burst_data),.cmd_valid(cmd_v),',1)
    s=s.replace('ddr_word_engine #(', 'ddr_word_engine #(.CAPTURE_BURST_BEATS(8),',1)
    s=s.replace('.fault(engine_fault),', '.fault(engine_fault),.capture_burst_data(capture_burst_data),.fault_reason(engine_reason),')
    top.write_text(s)
    for test in out.rglob('*.sv'):
        s=test.read_text()
        for module,ports in [('video_correct_ddr_core',".preview_valid(1'b0),.preview_rgb(24'd0),.overlay_on(1'b0),.overlay_rgb(24'd0),"),
                             ('ddr_result_display',".preview_valid(1'b0),.preview_rgb(24'd0),.overlay_on(1'b0),.overlay_rgb(24'd0),"),
                             ('ddr_word_engine',".capture_burst_data(2048'd0),"),
                             ('ddr_capture_writer',".rx_failure_reason(4'd0),"),
                             ('ddr_capture_writer_banked',".rx_failure_reason(4'd0),")]:
            s=add_ports(s,module,ports)
        s=s.replace('geometry_frame_join dut(',"geometry_frame_join dut(.writer_reason(4'd0),")
        test.write_text(s)
    extra=[out/'rtl/video/rx_preview.v',out/'rtl/video/status_overlay.v']
    for script in (out/CAND).glob('*.do'):
        s=script.read_text()
        s=re.sub(r'^(vlog .*?)$',lambda m:m[1]+''.join(' {'+p.as_posix()+'}' for p in extra),s,flags=re.M)
        script.write_text(s)
    build=out/CAND/'build.tcl';build.write_text(build.read_text().replace('compile -top_module',''.join('add_design {'+p.as_posix()+'}\n' for p in extra)+'compile -top_module'))
    patch_native_bench(out)
    add_extra_inputs(out)
    finalize_ports(out)
    mp=out/'reproduction_manifest.json';manifest=json.loads(mp.read_text())
    manifest['optimization']='filtered_black_geometry_with_banked_burst_preview_candidate'
    manifest['known_unmerged']=[]
    for path in list(manifest['files']):
        manifest['files'][path]['local_sha256']=hashlib.sha256((out/path).read_bytes()).hexdigest()
    for path in extra:
        manifest['files'][path.relative_to(out).as_posix()]={'local_sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    for path in [*(out/'fullhd_tests').rglob('*'),*(out/CAND).glob('tb_*.do'),out/CAND/'simulation_cases.json']:
        if path.is_file():manifest['files'][path.relative_to(out).as_posix()]={'local_sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    mp.write_text(json.dumps(manifest,indent=2)+'\n')


def add_extra_inputs(out):
    from run_extra import CASES,BOARD_TESTS,fixtures
    folder=out/'fullhd_tests'
    fixtures(out,folder)
    cases_file=out/CAND/'simulation_cases.json';cases=json.loads(cases_file.read_text())
    template=(out/CAND/'tb_scheduler.do').read_text()
    tests=dict(CASES,tb_banked_burst_writer='BANKED_BURST_WRITER_PASS',tb_burst_source_cache='BURST_SOURCE_CACHE_PASS')
    for name,marker in tests.items():
        if name=='tb_banked_burst_writer':src=HERE/'writer'/ (name+'.sv')
        elif name in ('tb_core_recovery','tb_geometry_reset','tb_burst_source_cache'):src=HERE/(name+'.sv')
        else:src=BOARD_TESTS/(name+'.sv')
        code=src.read_text().replace('@OUT@',folder.as_posix())
        if name in ('tb_reason','tb_tag_status'):code=add_ports(code,'frame_processor',".input_geometry_valid(1'b0),.input_corners(96'd0),")
        if name=='tb_reason':code=code.replace('.mem_rgb(24\'d0)',".mem_rgb(24'h808080)")
        if name=='tb_preview_display':code=add_ports(code,'ddr_result_display',".capture_guard(1'b0),.prefetch_busy(),")
        (folder/(name+'.sv')).write_text(code)
        script=template.replace((folder/'tb_scheduler.sv').as_posix(),(folder/(name+'.sv')).as_posix())
        script=script.replace('work_scheduler','work_'+name).replace('tb_scheduler',name)
        (out/CAND/(name+'.do')).write_text(script);cases[name]=marker
    cases_file.write_text(json.dumps(cases,indent=2)+'\n')


def finalize_ports(out):
    scan={name:'' for name in ['scan_x','scan_y','scan_de','scan_start','scan_reset_n']}
    ports={
      'video_correct_ddr_core':dict(scan,diagnostic_reason='',diagnostic_phase='',cmd_burst_data=''),
      'ddr_result_display':scan,
      'ddr_snapshot_capture':{'failure_reason':''},
      'ddr_capture_writer':{'failure_reason':'','cmd_burst_data':''},
      'ddr_capture_writer_banked':{'failure_reason':'','cmd_burst_data':''},
      'ddr_word_engine':{'fault_reason':''},
      'frame_processor':{'failure_reason':''},
      'frame_session':{'phase':'','capture_rejected':''},
      'frame_session_overlap':{'phase':'','capture_rejected':''},
      'geometry_frame_join':{'failure_reason':''},
    }
    for test in out.rglob('*.sv'):
        code=test.read_text()
        for module,defaults in ports.items():
            pattern=r'^\s*'+module+r'\s*(?:#\s*\((?:[^()]|\([^()]*\))*\)\s*)?\w+\s*\('
            for match in reversed(list(re.finditer(pattern,code,re.M))):
                start=match.end()
                # Legacy tests select two alternative instance prefixes with
                # `ifdef, sharing a single port body and terminator.
                terminal=re.search(r'\)\s*;',code[start:])
                if terminal is None:raise ValueError(f'Missing instance terminator: {test} {module}')
                end=start+terminal.start()+1
                body=code[start:end-1]
                missing=''.join(f'.{name}({value}),' for name,value in defaults.items()
                                if not re.search(r'\.'+name+r'\s*\(',body))
                code=code[:start]+missing+code[start:]
        test.write_text(code)


def patch_native_bench(out):
    bench=out/'fullhd_tests/tb_fullhd_pipeline.sv';s=bench.read_text()
    s=s.replace(' video_correct_ddr_core #(', ' wire[2047:0]burst_payload;wire[3:0]engine_reason;\n video_correct_ddr_core #(.CAPTURE_BURST_BEATS(8),',1)
    s=s.replace('.cmd_valid(cmd_v),.cmd_ready(cmd_r),.cmd_write(cmd_w),.cmd_addr(cmd_a),.cmd_wdata(cmd_data)', '.cmd_burst_data(burst_payload),.cmd_valid(cmd_v),.cmd_ready(cmd_r),.cmd_write(cmd_w),.cmd_addr(cmd_a),.cmd_wdata(cmd_data)',1)
    s=s.replace(' ddr_word_engine #(', ' ddr_word_engine #(.CAPTURE_BURST_BEATS(8),',1)
    s=s.replace('.capture_burst_data(2048\'d0),', '.capture_burst_data(burst_payload),.fault_reason(engine_reason),')
    s=s.replace(".axi_wready(awready),.axi_wusero_id(4'd0),.axi_wusero_last(1'b1)", ".axi_wready(wready),.axi_wusero_id(4'd0),.axi_wusero_last(wlast)")
    s=s.replace(' wire awready=rst_n', ''' reg write_pending=0;reg[27:0]write_base=0;integer write_index=0,write_total=0;
 wire wready=rst_n&&(ui_tick%11!=0);
 wire wlast=write_pending?(write_index==write_total-1):(awlen==0);
 wire[27:0]physical_addr=write_pending?write_base+write_index*8:awaddr;
 wire awready=rst_n''')
    s=s.replace('  if(awvalid&&awready)begin: physical_write', '''  if(awvalid&&awready)begin
   if(write_pending)$fatal(1,"overlapping physical AW");
   if(awlen!=0&&awlen!=7)$fatal(1,"invalid AWLEN");
   write_pending<=1;write_base<=awaddr;write_index<=0;write_total<=awlen+1;
  end
  if(wready&&(write_pending||(awvalid&&awready)))begin: physical_write''')
    a=s.index('begin: physical_write');b=s.index('\n  end\n end\n always @(negedge ui_clk)',a)
    section=s[a:b].replace('awaddr','physical_addr')
    section+='''
   if(wlast)begin write_pending<=0;write_index<=0;end
   else begin write_pending<=1;write_index<=write_pending?write_index+1:1;end'''
    s=s[:a]+section+s[b:]
    bench.write_text(s)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True)
    out=parser.parse_args().output.resolve()
    subprocess.run([sys.executable,str(HERE/'prepare.py'),'--output',str(out)],check=True)
    merge(out)
    print('MERGED_CANDIDATE_READY board_replacement_allowed=false')
