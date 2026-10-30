from pathlib import Path
import argparse,json

CAND='diagnostics/ddr_camera_hires_prefetch_20261012/results'
def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True)
    out=p.parse_args().output.resolve(); cand=out/CAND; tests=out/'fullhd_tests';tests.mkdir(exist_ok=True)
    text=(cand/'tb_hires_read_ahead_display.sv').read_text()
    text=text.replace('module tb_hires_read_ahead_display #(parameter READ_AHEAD=1,EXPECT_UNDERRUN=0,LOAD_TRAFFIC=0);',
                      'module tb_fullhd_capture_display #(parameter READ_AHEAD=1,EXPECT_UNDERRUN=0,LOAD_TRAFFIC=1);')
    text=text.replace("28'h0200000","28'h0400000").replace("28'h0100000","28'h0200000")
    text=text.replace('.SCALE(1)) dut(', ".SCALE(1),.BASE0(28'h0200000),.BASE1(28'h0400000)) dut(")
    text=text.replace('.RESULT_WORDS(OW*OH)) engine(', ".RESULT_WORDS(OW*OH),.RESULT_BASE0(28'h0200000),.RESULT_BASE1(28'h0400000)) engine(")
    text=text.replace(".axi_awready(1'b1)",'.axi_awready(ui_cycle%17>=2)')
    text=text.replace(".axi_wready(1'b1)",'.axi_wready(ui_cycle%17>=2)')
    start=text.index(' reg load_proc_valid=')
    end=text.index(' wire app_valid,',start)
    text=text[:start]+'''
 wire load_proc_valid=1'b0;wire [27:0] load_proc_addr=0;
 wire load_cap_valid;wire [27:0] load_cap_addr;wire [255:0] capture_data;wire [31:0] capture_mask;
 wire load_proc_ready,load_cap_ready,load_proc_rsp,load_cap_rsp,load_proc_write,load_cap_write;
 wire [255:0] load_proc_data,load_cap_data;
 reg camera_vs=0,camera_de=0,capture_request=0;reg [23:0] camera_rgb=0;
 wire rx_done,rx_ok,full,empty,fwe,fre,frvalid,cap_done,cap_good,capture_write;
 wire [284:0] fwd,frd;
 integer capture_served=0,capture_max_backlog=0;
 ddr_snapshot_capture #(.IN_W(1920),.IN_H(1080),.SRC_W(1920),.SRC_H(1080)) capture(
  .rx_clk(pix_clk),.rx_rst_n(reset_n),.rx_vs(camera_vs),.rx_de(camera_de),.rx_rgb(camera_rgb),
  .request_toggle(capture_request),.rx_complete_toggle(rx_done),.capture_ok(rx_ok),
  .fifo_wr_en(fwe),.fifo_wr_data(fwd),.fifo_full(full));
 async_packet_fifo #(.DATA_WIDTH(285),.ADDR_BITS(10)) fifo(.wr_clk(pix_clk),.rd_clk(ui_clk),.rst_n(reset_n),
  .wr_en(fwe),.wr_data(fwd),.full(full),.rd_en(fre),.rd_data(frd),.rd_valid(frvalid),.empty(empty));
 ddr_capture_writer #(.SRC_W(1920),.SRC_H(1080)) writer(.ui_clk(ui_clk),.ui_rst_n(reset_n),
  .request_toggle(capture_request),.rx_complete_toggle(rx_done),.rx_capture_ok(rx_ok),
  .fifo_empty(empty),.fifo_rd_data(frd),.fifo_rd_valid(frvalid),.fifo_rd_en(fre),
  .cmd_valid(load_cap_valid),.cmd_ready(load_cap_ready),.cmd_write(capture_write),.cmd_addr(load_cap_addr),
  .cmd_wdata(capture_data),.cmd_wstrb(capture_mask),.rsp_valid(load_cap_rsp),.rsp_write(load_cap_write),
  .complete_toggle(cap_done),.capture_ok(cap_good));
 always @(posedge pix_clk)if(reset_n&&capture.active)begin
  if(full)$fatal(1,"FULLHD_FIFO_OVERFLOW full-resolution capture cannot sustain rate");
 end
 always @(posedge ui_clk)if(reset_n&&load_cap_valid&&load_cap_ready)begin
  if(!capture_write||load_cap_addr!==capture_served*8||capture_mask!==32'hffffffff||
     capture_data!==source_word(load_cap_addr))$fatal(1,"FULLHD_CAPTURE_PIXEL_OR_ADDRESS beat=%0d",capture_served);
  capture_served=capture_served+1;
 end
 initial begin
  wait(ack==1);repeat(30)@(negedge pix_clk);capture_request=1;
  repeat(30)@(negedge pix_clk);camera_vs=1;repeat(5)@(negedge pix_clk);camera_vs=0;
  for(integer y=0;y<1080;y=y+1)begin
   for(integer x=0;x<1920;x=x+1)begin
    camera_de=1;camera_rgb=24'h200000|(y*1920+x);@(negedge pix_clk);
   end
   camera_de=0;repeat(280)@(negedge pix_clk);
  end
  camera_vs=1;repeat(5)@(negedge pix_clk);camera_vs=0;
 end
''' +text[end:]
    text=text.replace('.c1_wdata(source_word(load_cap_addr)),.c1_wstrb(32\'hffffffff)', '.c1_wdata(capture_data),.c1_wstrb(capture_mask)')
    text=text.replace('if(LOAD_TRAFFIC&&(capture_served<10000||processor_served<100))$fatal(1,"other memory clients did not make progress");',
       'wait(cap_done==capture_request); if(!cap_good||!rx_ok||capture_served!=259200)$fatal(1,"FULLHD_CAPTURE_INCOMPLETE beats=%0d",capture_served);')
    text=text.replace('$display("SHARED_MEMORY_COUNTS capture=%0d source=%0d max_capture_backlog=%0d assumed_capture_period=24",capture_served,processor_served,capture_max_backlog);',
       '$display("FULLHD_CAPTURE_DISPLAY_PASS source_pixels=2073600 capture_beats=%0d display_frames=%0d model_latency_only=1",capture_served,completed_frames);')
    (tests/'tb_fullhd_capture_display.sv').write_text(text)
    sources=[f'{CAND}/ddr_word_engine.v',f'{CAND}/ddr_result_display.v','rtl/memory/ddr_arbiter3.v',
             'rtl/video/ddr_snapshot_capture.v','rtl/memory/async_packet_fifo.v','rtl/memory/ddr_capture_writer.v',
             'vendor/c_current/01_design_code/video_timing_vtc.v','fullhd_tests/tb_fullhd_capture_display.sv']
    script='onerror {quit -f -code 1}\nvlib work_fullhd\nvmap work_fullhd work_fullhd\n'
    script+='vlog -sv -work work_fullhd '+' '.join('{'+(out/s).as_posix()+'}' for s in sources)+'\n'
    script+='vsim -c -voptargs=+acc work_fullhd.tb_fullhd_capture_display\nonfinish stop\nrun -all\n'
    script+='if {[examine -value -radix binary sim:/tb_fullhd_capture_display/test_passed] ne "1"} {quit -f -code 1}\nputs "VERIFIED_PASS_BIT=1"\nquit -f -code 0\n'
    (tests/'capture_display.do').write_text(script)
    frame=(cand/'tb_ddr_full_frame.sv').read_text().replace('SRC_W=960,SRC_H=540','SRC_W=1920,SRC_H=1080')
    frame=frame.replace("28'h0100000","28'h0200000")
    frame=frame.replace((cand/'source_960x540.hex').as_posix(),(tests/'source_1920x1080.hex').as_posix())
    frame=frame.replace((cand/'expected_640x904.hex').as_posix(),(tests/'expected_640x904.hex').as_posix())
    frame=frame.replace('.MAX_PIXELS(4096),.MAX_SPAN(128)', '.MAX_PIXELS(16384),.MAX_SPAN(256)')
    frame=frame.replace('.MIN_PIXELS(16)', '.MIN_PIXELS(64)')
    frame=frame.replace("OUT_BASE+28'h100000", "28'h0400000")
    frame=frame.replace('  for(integer i=0;i<SRC_W*SRC_H;i=i+1) ram[i]={8\'d0,source[i]};', '  run_capture();')
    capture_stage=(Path(__file__).resolve().parent/'capture_to_frame.sv.inc').read_text()
    frame=frame.replace(' initial begin\n  $readmemh',capture_stage+'\n initial begin\n  $readmemh',1)
    (tests/'tb_ddr_full_frame.sv').write_text(frame)
    frame_do=(cand/'tb_ddr_full_frame.do').read_text().replace((cand/'tb_ddr_full_frame.sv').as_posix(),(tests/'tb_ddr_full_frame.sv').as_posix())
    frame_do=frame_do.replace('work_tb_ddr_full_frame','work_fullhd_frame')
    (tests/'full_frame.do').write_text(frame_do)
    relocated=(cand/'tb_video_correct_ddr_core.sv').read_text()
    relocated=relocated.replace("28'h0200000","28'h0400000").replace("28'h0100000","28'h0200000")
    relocated=relocated.replace("28'h03f0000","28'h0600000").replace("28'h03f0040","28'h0600040")
    relocated=relocated.replace('.BIST_BEATS(8)) dut(', ".BIST_BEATS(8),.RESULT_BASE0(28'h0200000),.RESULT_BASE1(28'h0400000),.BIST_BASE(28'h0600000)) dut(")
    (tests/'tb_relocated_core.sv').write_text(relocated)
    relocate_do=(cand/'tb_video_correct_ddr_core.do').read_text().replace((cand/'tb_video_correct_ddr_core.sv').as_posix(),(tests/'tb_relocated_core.sv').as_posix())
    relocate_do=relocate_do.replace('work_tb_video_correct_ddr_core','work_relocated_core')
    exceptions=Path(__file__).resolve().parent.parent/'a_sync_20261013/accepted/sim/tb_ddr_capture.sv'
    (tests/'tb_ddr_capture.sv').write_bytes(exceptions.read_bytes())
    exception_do=(cand/'tb_video_correct_ddr_core.do').read_text().replace((cand/'tb_video_correct_ddr_core.sv').as_posix(),(tests/'tb_ddr_capture.sv').as_posix())
    exception_do=exception_do.replace('tb_video_correct_ddr_core','tb_ddr_capture')
    for name,code in [('tb_fullhd_capture_display',script),('tb_fullhd_frame',frame_do),('tb_relocated_core',relocate_do),('tb_capture_errors',exception_do)]:
        # Each test owns its transcript and waveform files even when it reuses a module name.
        import re
        code=re.sub(r'transcript file \{[^}]+\}',f'transcript file {{{(cand/(name+".transcript.log")).as_posix()}}}',code)
        code=re.sub(r'-wlf \{[^}]+\}',f'-wlf {{{(cand/(name+".wlf")).as_posix()}}}',code)
        (cand/(name+'.do')).write_text(code)
    cases=json.loads((cand/'simulation_cases.json').read_text())
    cases.update(tb_fullhd_capture_display='FULLHD_CAPTURE_DISPLAY_PASS',tb_fullhd_frame='DDR_FULL_FRAME_PASS',
                 tb_relocated_core='DDR_CORE_PASS',tb_capture_errors='DDR_CAPTURE_PASS')
    (cand/'simulation_cases.json').write_text(json.dumps(cases,indent=2)+'\n')
if __name__=='__main__':main()
