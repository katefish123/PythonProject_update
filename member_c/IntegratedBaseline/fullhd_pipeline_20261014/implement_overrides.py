"""Materialize application-only native scan cache and late-capture overlays."""
from pathlib import Path
HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'capture_overlap_20261014/overrides'
CAND=Path('diagnostics/ddr_camera_hires_prefetch_20261012/results')
def save(rel,s):
 p=HERE/'overrides'/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
engine=(HERE.parent/'a_sync_20261013/hires_candidate'/CAND/'ddr_word_engine.v').read_text()
engine=engine.replace('parameter integer RESULT_WORDS', '''parameter integer SOURCE_PREFETCH_ENABLE = 0,
    parameter integer SOURCE_WORDS = 1920*1080,
    parameter [27:0] SOURCE_BASE0 = 28'd0,
    parameter [27:0] SOURCE_BASE1 = 28'h0800000,
    parameter integer RESULT_WORDS''')
engine=engine.replace('wire cache_hit=result_read && cache_valid && cache_tag==cmd_addr[27:6];', '''reg source_cache_valid,read_source,source_next_valid;
    reg [21:0] source_cache_tag;
    reg [27:0] source_next_addr;
    reg [255:0] source_cache[0:7];
    wire source_read=SOURCE_PREFETCH_ENABLE && !cmd_write &&
        ((cmd_addr>=SOURCE_BASE0 && cmd_addr<SOURCE_BASE0+SOURCE_WORDS) ||
         (cmd_addr>=SOURCE_BASE1 && cmd_addr<SOURCE_BASE1+SOURCE_WORDS));
    wire source_block_safe=
        ((request_block>=SOURCE_BASE0 && request_block+28'd63<SOURCE_BASE0+SOURCE_WORDS) ||
         (request_block>=SOURCE_BASE1 && request_block+28'd63<SOURCE_BASE1+SOURCE_WORDS));
    wire source_prefetch=source_read && source_block_safe &&
        (cmd_addr==SOURCE_BASE0 || cmd_addr==SOURCE_BASE1 ||
         (source_next_valid && cmd_addr==source_next_addr));
    wire source_hit=source_read && source_cache_valid && source_cache_tag==cmd_addr[27:6];
    wire result_hit=result_read && cache_valid && cache_tag==cmd_addr[27:6];
    wire cache_hit=result_hit || source_hit;''')
engine=engine.replace('result_cache[read_index]<=axi_rdata;', 'if(read_source)source_cache[read_index]<=axi_rdata;\n                    else result_cache[read_index]<=axi_rdata;')
engine=engine.replace('cache_tag<=addr_hold[27:6];cache_valid<=1;\n                        rsp_rdata<=(addr_hold[5:3]==3\'d7) ? axi_rdata : result_cache[addr_hold[5:3]];', '''if(read_source)begin source_cache_tag<=addr_hold[27:6];source_cache_valid<=1;end
                        else begin cache_tag<=addr_hold[27:6];cache_valid<=1;end
                        rsp_rdata<=(addr_hold[5:3]==3'd7) ? axi_rdata :
                            (read_source ? source_cache[addr_hold[5:3]] : result_cache[addr_hold[5:3]]);''')
engine=engine.replace('fault<=1;cache_valid<=0;', 'fault<=1;cache_valid<=0;source_cache_valid<=0;')
engine=engine.replace('fault <= 1\'b0;cache_valid<=0;', "source_cache_valid<=0;source_cache_tag<=0;source_next_valid<=0;source_next_addr<=0;read_source<=0;\n            fault <= 1'b0;cache_valid<=0;")
engine=engine.replace('read_burst<=0;read_index<=0;\n                        if(cmd_write', '''read_burst<=0;read_index<=0;read_source<=0;
                        if(source_read)begin source_next_valid<=1;source_next_addr<=cmd_addr+28'd8;end
                        if(cmd_write && source_cache_valid && source_cache_tag==cmd_addr[27:6])source_cache_valid<=0;
                        if(cmd_write''')
engine=engine.replace('rsp_rdata<=result_cache[cmd_addr[5:3]];', 'rsp_rdata<=source_hit ? source_cache[cmd_addr[5:3]] : result_cache[cmd_addr[5:3]];')
engine=engine.replace('read_burst<=result_read;', 'read_burst<=result_read || source_prefetch;read_source<=source_prefetch;\n                            if(source_prefetch)source_cache_valid<=0;')
save(CAND/'ddr_word_engine.v',engine)
session=(OLD/'rtl/top/frame_session.v').read_text()
pos=session.index('module frame_session_overlap')
session=session[:pos]+session[pos:].replace('input wire clk,rst_n,enabled,','input wire clk,rst_n,enabled,capture_permitted,',1).replace('CAP_IDLE:if(enabled&&!ready_valid)', 'CAP_IDLE:if(enabled&&!ready_valid&&(!source_locked||capture_permitted))')
save(Path('rtl/top/frame_session.v'),session)
core=(OLD/'rtl/top/video_correct_ddr_core.v').read_text()
core=core.replace('OVERLAP_CAPTURE=0,','OVERLAP_CAPTURE=0,LATE_CAPTURE_PERCENT=0,ADAPTIVE_DISPLAY_GUARD=0,')
core=core.replace('wire p_done,p_error,p_busy,writer_drained,writer_fault;', '''wire p_done,p_error,p_busy,writer_drained,writer_fault;
 wire [31:0] p_pixels;
 localparam LATE_CAPTURE_PIXELS=OUT_W*OUT_H*LATE_CAPTURE_PERCENT/100;
 wire capture_permitted=(LATE_CAPTURE_PERCENT==0)||(p_busy&&p_pixels>=LATE_CAPTURE_PIXELS);''')
core=core.replace('.capture_bank(capture_bank),','.capture_permitted(capture_permitted),.capture_bank(capture_bank),')
core=core.replace('.completed_pixels(),','.completed_pixels(p_pixels),')
core=core.replace('wire capture_bank,source_bank;', 'wire capture_bank,source_bank,capture_inflight;')
core=core.replace('.capture_inflight(),','.capture_inflight(capture_inflight),')
core=core.replace("assign capture_bank=1'b0;", "assign capture_inflight=1'b0;assign capture_bank=1'b0;")
core=core.replace('wire processor_ui_allowed=!OVERLAP_CAPTURE||(fifo_empty&&!display_prefetch_busy);', '''// Three-stream protection is needed while capture is outstanding. Outside
 // that window, normal display-priority arbitration permits processor progress.
 (* ASYNC_REG="TRUE" *) reg [2:0] capture_busy_ui;
 always @(posedge ui_clk or negedge ui_rst_n)begin
  if(!ui_rst_n)capture_busy_ui<=0;
  else capture_busy_ui<={capture_busy_ui[1:0],capture_inflight};
 end
 wire strict_display_guard=!ADAPTIVE_DISPLAY_GUARD||capture_busy_ui[2];
 wire processor_ui_allowed=!OVERLAP_CAPTURE||(fifo_empty&&(!strict_display_guard||!display_prefetch_busy));''')
save(Path('rtl/top/video_correct_ddr_core.v'),core)
top=(OLD/CAND/'video_correct_ddr_top.v').read_text().replace('.OVERLAP_CAPTURE(1),','.OVERLAP_CAPTURE(1),.LATE_CAPTURE_PERCENT(95),.ADAPTIVE_DISPLAY_GUARD(1),')
top=top.replace('.READ_AHEAD_ENABLE(1),','.READ_AHEAD_ENABLE(1),.SOURCE_PREFETCH_ENABLE(1),.SOURCE_WORDS(1920*1080),.SOURCE_BASE1(28\'h0800000),')
save(CAND/'video_correct_ddr_top.v',top)
