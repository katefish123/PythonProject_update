"""Generate a separate streaming board candidate. Never programs a board."""
from pathlib import Path
import argparse, hashlib, json, re, shutil, subprocess, sys
HERE=Path(__file__).resolve().parent
CAND=Path('diagnostics/ddr_camera_hires_prefetch_20261012/results')

def replace_once(text, old, new):
    assert text.count(old)==1, (old[:100],text.count(old))
    return text.replace(old,new,1)

def prepare(out, prepared=False):
    if prepared:
        assert (out/'rtl/top/video_correct_ddr_core.v').exists() and not (out/'rtl/stream').exists()
    else:
        assert not out.exists(), 'Use a fresh output directory for immutable validation'
        subprocess.run([sys.executable,str(HERE.parent/'black_board_20261015/merge_board.py'),'--output',str(out)],check=True)
    # Keep old core/session intact for compatibility tests. Board top explicitly
    # selects separate new modules, so legacy tests cannot qualify the new path.
    core=(out/'rtl/top/video_correct_ddr_core.v').read_text()
    core=replace_once(core,'module video_correct_ddr_core #(','module video_correct_ddr_stream_core #(')
    core=replace_once(core,'output wire[2047:0]cmd_burst_data,','output wire cmd_source_block,input wire[2047:0]rsp_source_block,\n output wire[2047:0]cmd_burst_data,')
    core=core.replace('frame_session_overlap #(','frame_session_overlap_stream #(')
    core=replace_once(core,'.capture_permitted(capture_permitted),','.start_permitted(path_start_ready),.capture_permitted(capture_permitted),')
    # Declare before use for Verilog default_nettype none.
    core=replace_once(core,'wire p_done,p_error,p_busy,writer_drained,writer_fault;','wire p_done,p_error,p_busy,writer_drained,writer_fault,path_start_ready;')
    a=core.index(' wire mem_v,mem_ready,mem_rsp,wr_v,wr_ready;')
    b=core.index(' (* ASYNC_REG="TRUE" *) reg [2:0] capture_busy_ui;',a)
    core=core[:a]+''' wire br_v,br_r,br_w,br_rsp,br_rsp_write,br_block;
 wire [27:0]br_a;wire[255:0]br_data,br_rdata;wire[31:0]br_mask;
 assign writer_drained=1'b1;assign writer_fault=1'b0;
 c_stream_correction_path #(.SRC_W(SRC_W),.SRC_H(SRC_H),.OUT_W(OUT_W),.OUT_H(OUT_H),.ACTIVE_W(OUT_W-3),.ACTIVE_X(1),.RESULT_BASE0(RESULT_BASE0),.RESULT_BASE1(RESULT_BASE1)) stream_path(
 .proc_clk(proc_clk),.ui_clk(ui_clk),.rst_n(proc_rst_n&&ui_rst_n),.start(start),.abort(!processor_rst),.nearest(nearest),
 .input_geometry_valid(source_bank?valid1:valid0),.input_corners(source_bank?corners1:corners0),.source_base(source_bank?SOURCE_BASE1:28'd0),.frame_bank(write_bank),
 .start_ready(path_start_ready),.busy(p_busy),.done(p_done),.error(p_error),.failure_reason(processor_reason),.completed_pixels(p_pixels),.processor_cycles(),
 .cmd_valid(br_v),.cmd_ready(br_r),.cmd_write(br_w),.cmd_source_block(br_block),.cmd_addr(br_a),.cmd_wdata(br_data),.cmd_wstrb(br_mask),
 .rsp_valid(br_rsp),.rsp_write(br_rsp_write),.rsp_rdata(br_rdata),.rsp_source_block(rsp_source_block),.engine_fault(memory_fault));
''' + core[b:]
    core=replace_once(core,'assign cmd_valid=ddr_ready', 'assign cmd_source_block=selftest_passed&&app_v&&!display_v&&!cap_v&&br_block;\n assign cmd_valid=ddr_ready')
    (out/'rtl/top/video_correct_ddr_stream_core.v').write_text(core)
    session=(out/'rtl/top/frame_session.v').read_text()
    session=session[session.index('module frame_session_overlap'):]
    session=replace_once(session,'module frame_session_overlap #(','module frame_session_overlap_stream #(')
    session=replace_once(session,'input wire clk,rst_n,enabled,capture_permitted,','input wire clk,rst_n,enabled,capture_permitted,start_permitted,')
    # Do not consume a queued source frame until aborted result writes drain.
    session=replace_once(session,'if(enabled&&ready_valid)begin','if(enabled&&ready_valid&&start_permitted)begin')
    (out/'rtl/top/frame_session_overlap_stream.v').write_text('`timescale 1ns/1ps\n`default_nettype none\n'+session)
    sources=[]
    for folder in ('processor','bridge','cache','writer','integration','preview'):
        for src in (HERE/folder).glob('*.v'):
            dst=out/'rtl/stream'/src.name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst);sources.append(dst)
    shutil.copyfile(HERE/'engine/ddr_word_engine.v',out/CAND/'ddr_word_engine.v')
    sources += [out/'rtl/top/video_correct_ddr_stream_core.v',out/'rtl/top/frame_session_overlap_stream.v']
    top=out/CAND/'video_correct_ddr_top.v';s=top.read_text()
    s=replace_once(s,'video_pll_27m_148m5 vp(', 'wire proc_clk54;\n video_pll_27m_148m5 vp(.clkout54(proc_clk54),')
    s=replace_once(s,'reset_sync process_reset(.clk(sys_clk_27m)', 'reset_sync process_reset(.clk(proc_clk54)')
    s=replace_once(s,'always @(posedge sys_clk_27m or negedge proc_rst)begin\n  if(!proc_rst)begin ready_sync','always @(posedge proc_clk54 or negedge proc_rst)begin\n  if(!proc_rst)begin ready_sync')
    s=replace_once(s,'video_correct_ddr_core #(','video_correct_ddr_stream_core #(')
    s=replace_once(s,'.LATE_CAPTURE_PERCENT(95)', '.LATE_CAPTURE_PERCENT(0)')
    s=replace_once(s,'rx_preview preview(', 'rx_preview_stream preview(')
    s=replace_once(s,'.OUT_W(640),.OUT_H(904)','.OUT_W(768),.OUT_H(1080)')
    s=replace_once(s,'core(.proc_clk(sys_clk_27m)','core(.proc_clk(proc_clk54)')
    s=replace_once(s,'wire cmd_v,cmd_r,cmd_w,rsp_v,rsp_w,engine_fault;','wire cmd_v,cmd_r,cmd_w,rsp_v,rsp_w,engine_fault,source_block;wire[2047:0]full_source_block;')
    s=replace_once(s,'.cmd_burst_data(capture_burst_data),','.cmd_source_block(source_block),.rsp_source_block(full_source_block),.cmd_burst_data(capture_burst_data),')
    s=replace_once(s,'.RESULT_WORDS(640*904)','.RESULT_WORDS(768*1080)')
    s=replace_once(s,'engine(.clk(ui_clk)','engine(.cmd_source_block(source_block),.rsp_source_block(full_source_block),.clk(ui_clk)')
    # Preserve timeout wall time after doubling only the processing clock.
    s=replace_once(s,'video_correct_ddr_stream_core #(', 'video_correct_ddr_stream_core #(.CAPTURE_TIMEOUT(108000000),.RETRY_CYCLES(540000),')
    top.write_text(s)
    pll=out/'vendor/c_current/01_design_code/ip/video_pll_27m_148m5/video_pll_27m_148m5.v'
    s=replace_once(pll.read_text(),'output wire clkout0,','output wire clkout0,output wire clkout54,')
    s=replace_once(s,'.CLKOUTF        (               )','.CLKOUTF        (clkout54       )');pll.write_text(s)
    fdc=out/'constr/board_ddr.fdc';s=fdc.read_text()
    s=replace_once(s,'create_clock -name pixel_clock','create_clock -name processing_clock -period 18.518519 [get_pins {vp/u_gpll:CLKOUTF}]\ncreate_clock -name pixel_clock')
    s=replace_once(s,'-group [get_clocks {sys_clk_27m}]','-group [get_clocks {processing_clock}] -group [get_clocks {sys_clk_27m}]');fdc.write_text(s)
    build=out/CAND/'build.tcl';s=build.read_text();s=replace_once(s,'compile -top_module', ''.join('add_design {'+x.as_posix()+'}\n' for x in sources)+'compile -top_module');build.write_text(s)
    # Explicitly terminate new engine ports in all old compatibility fixtures.
    for test in out.rglob('*.sv'):
        s=test.read_text()
        s=re.sub(r'(ddr_word_engine\s*#\s*\((?:[^()]|\([^()]*\))*\)\s+\w+\s*\()',r"\1.cmd_source_block(1'b0),.rsp_source_block(),",s)
        test.write_text(s)
    manifest={p.relative_to(out).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sources,top,pll,fdc,out/CAND/'ddr_word_engine.v',build]}
    (out/'stream_sources.json').write_text(json.dumps({'hardware_accepted':False,'board_replacement_allowed':False,'files':manifest},indent=2)+'\n')
    print('STREAM_BOARD_CANDIDATE_GENERATED; NOT hardware qualified')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--prepared',action='store_true');a=p.parse_args();prepare(a.output.resolve(),a.prepared)
