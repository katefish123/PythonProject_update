from pathlib import Path
import argparse

def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);out=p.parse_args().output.resolve()
 cand=out/'diagnostics/ddr_camera_hires_prefetch_20261012/results'
 s=(cand/'tb_video_correct_ddr_core.sv').read_text().replace('module tb_video_correct_ddr_core;','module tb_overlap_core;')
 s=s.replace('.BIST_BEATS(8)) dut(', ".BIST_BEATS(8),.OVERLAP_CAPTURE(1),.SOURCE_BASE1(28'h0800000)) dut(")
 s=s.replace('src_mem[0:WORDS*4-1],','src_mem[0:WORDS*4-1],src_mem1[0:WORDS*4-1],')
 s=s.replace('rx_de<=0;rx_vs<=1;repeat(2) @(negedge rx_clk);rx_vs<=0;', 'rx_de<=0;repeat(4) @(negedge rx_clk);')
 s=s.replace('else if(a<SRC_PIXELS) memory_read=src_mem[a>>3];',"else if(a<SRC_PIXELS) memory_read=src_mem[a>>3];\n   else if(a>=28'h0800000&&a<28'h0800000+SRC_PIXELS)memory_read=src_mem1[(a-28'h0800000)>>3];")
 s=s.replace('else if(cmd_addr>=28\'h0100000 && cmd_addr<28\'h0100000+WORDS*8) begin if', "else if(cmd_addr>=28'h0800000&&cmd_addr<28'h0800000+SRC_PIXELS)begin src_mem1[(cmd_addr-28'h0800000)>>3]<=cmd_wdata;cap_writes<=cap_writes+1;end\n   else if(cmd_addr>=28'h0100000 && cmd_addr<28'h0100000+WORDS*8) begin if",1)
 s=s.replace('   if(cmd_addr<SRC_PIXELS && cap_writes<(good_frames+1)*(SRC_PIXELS/8)) $fatal(1,"read source before capture writes drained: %0d",cap_writes);','')
 a=s.index(' always @(posedge proc_clk) if(proc_rst_n&&dut.start) begin')
 b=s.index(' always @(posedge proc_clk) if(proc_rst_n&&dut.pub_toggle',a)
 s=s[:a]+r'''
 integer expected_kind=0,starts0=0,starts1=0,overlap_writes=0,checked_results=0;
 reg result_kind[0:1];
 always @(negedge proc_clk)nearest=dut.source_bank;
 always @(posedge proc_clk)if(proc_rst_n&&dut.start)begin
  expected_kind=dut.source_bank;
  if(expected_kind)starts1=starts1+1;else starts0=starts0+1;
  for(integer z=0;z<SRC_PIXELS;z=z+1)begin
   if(expected_kind)begin
    if(src_mem1[z/8][(z%8)*32+:24]!==src1[z])$fatal(1,"source1 incomplete or mixed frame at start");
   end else if(src_mem[z/8][(z%8)*32+:24]!==src0[z])$fatal(1,"source0 incomplete or mixed frame at start");
  end
 end
 always @(posedge proc_clk)if(proc_rst_n&&dut.wr_v&&dut.wr_ready)begin
  if(dut.wr_rgb!==(expected_kind?exp1[dut.wr_a]:exp0[dut.wr_a]))$fatal(1,"parallel result pixel mismatch addr=%0d source=%0d",dut.wr_a,expected_kind);
  checked_results=checked_results+1;
 end
 always @(posedge ui_clk)if(ui_rst_n&&cmd_valid&&cmd_ready&&cmd_write&&
  (cmd_addr<SRC_PIXELS||(cmd_addr>=28'h0800000&&cmd_addr<28'h0800000+SRC_PIXELS)))begin
  if(working)begin
   if((cmd_addr>=28'h0800000)==dut.source_bank)$fatal(1,"background capture overwrote processing source");
   overlap_writes=overlap_writes+1;
  end
 end
''' +s[b:]
 s=s.replace('  pub_count=pub_count+1;', '  result_kind[dut.pub_bank]=expected_kind;compare_frame(dut.pub_bank,expected_kind);\n  pub_count=pub_count+1;')
 s=s.replace('task display_check(input integer which); integer x,y;', 'task display_check; integer which,x,y;')
 s=s.replace('@(posedge vsync);wait(de===1\'b0);','@(posedge vsync);wait(de===1\'b0);which=result_kind[dut.display_reader.display_bank];')
 a=s.index('  repeat(6)@(negedge ui_clk);proc_rst_n=1;')
 b=s.index(' initial begin #30000000;',a)
 s=s[:a]+r'''
  repeat(6)@(negedge ui_clk);proc_rst_n=1;rx_rst_n=1;ui_rst_n=1;pix_rst_n=1;
  fork
   begin forever send_frame(dut.capture_bank?1:0,0);end
   begin
    wait(good_frames>=4);wait(image_valid);display_check();
    if(display_underrun||selftest_failed)$fatal(1,"parallel core display or DDR failure");
    if(starts0<2||starts1<2||overlap_writes==0)$fatal(1,"source banks did not overlap and alternate");
    hdmi_ready=0;wait(!working);repeat(100)@(negedge proc_clk);hdmi_ready=1;
    wait(good_frames>=6);
    proc_rst_n=0;rx_rst_n=0;ui_rst_n=0;pix_rst_n=0;
    repeat(6)@(negedge proc_clk);pub_seen=0;pub_count=0;dest_responses=0;
    proc_rst_n=1;rx_rst_n=1;ui_rst_n=1;pix_rst_n=1;
    wait(good_frames>=3);wait(image_valid);display_check();
    if(display_underrun)$fatal(1,"parallel display failed after common reset");
    test_passed=1;$display("OVERLAP_CORE_PASS starts0=%0d starts1=%0d overlap_writes=%0d checked_results=%0d",starts0,starts1,overlap_writes,checked_results);$finish;
   end
  join
 end
''' +s[b:]
 s=s.replace('dut.serial_session.session.state','dut.parallel_session.session.state')
 (out/'fullhd_tests/tb_overlap_core.sv').write_text(s)
 template=(cand/'tb_scheduler.do').read_text()
 (cand/'tb_overlap_core.do').write_text(template.replace('tb_scheduler','tb_overlap_core').replace('work_scheduler','work_overlap_core'))

 # Match input pixels, bilinear mode, clocks and memory delay for serial/parallel comparison.
 perf=s.replace('module tb_overlap_core;','module tb_overlap_throughput #(parameter OVERLAP=1);')
 perf=perf.replace('.OVERLAP_CAPTURE(1)','.OVERLAP_CAPTURE(OVERLAP)')
 perf=perf.replace('always #5 proc_clk','always #18.5185185 proc_clk').replace('always #3.5 rx_clk','always #3.3670035 rx_clk')
 perf=perf.replace('nearest=dut.source_bank','nearest=0')
 perf=perf.replace('source1.hex','source0.hex').replace('expected1.hex','expected0.hex')
 perf=perf.replace('forever send_frame(dut.capture_bank?1:0,0)','forever send_frame(0,0)')
 perf=perf.replace('initial begin #30000000;', 'initial begin #30000000;').replace('dut.parallel_session.session.state','0')
 pa=perf.index('    wait(good_frames>=4);')
 pb=perf.index('   end\n  join',pa)
 perf=perf[:pa]+r"""
    wait(good_frames>=6);hdmi_ready=0;wait(!working);wait(image_valid);display_check();
    avg_interval=interval_sum/interval_count;
    if(display_underrun||interval_count<4)$fatal(1,"throughput comparison incomplete");
    $display("OVERLAP_THROUGHPUT_PASS mode=%0d average_start_interval_cycles=%0d intervals=%0d",OVERLAP,avg_interval,interval_count);
    test_passed=1;$finish;
"""+perf[pb:]
 perf=perf.replace(' integer expected_kind=0,', r"""
 integer proc_tick=0,last_start=0,interval_sum=0,interval_count=0,avg_interval=0;
 reg started_once=0;
 always @(posedge proc_clk)if(proc_rst_n)begin
  proc_tick=proc_tick+1;
  if(dut.start)begin
   if(started_once)begin interval_sum=interval_sum+proc_tick-last_start;interval_count=interval_count+1;end
   last_start=proc_tick;started_once=1;
  end
 end
 integer expected_kind=0,""")
 (out/'fullhd_tests/tb_overlap_throughput.sv').write_text(perf)
 code=template.replace('tb_scheduler','tb_overlap_throughput').replace('work_scheduler','work_overlap_throughput')
 head=code[:code.index('vsim -c')]
 tail=''
 for mode in [0,1]:
  tail+=f'vsim -c -voptargs=+acc -gOVERLAP={mode} work_overlap_throughput.tb_overlap_throughput\nonfinish stop\nrun -all\n'
  tail+='if {[examine -value -radix binary sim:/tb_overlap_throughput/test_passed] ne "1"} {quit -f -code 1}\n'
  variable='baseline' if mode==0 else 'parallel'
  tail+=f'set {variable} [examine -value -radix decimal -noshowbase sim:/tb_overlap_throughput/avg_interval]\n'
  tail+='quit -sim\n'
 tail+='if {$parallel >= $baseline} {puts "FAIL_OVERLAP_THROUGHPUT no interval reduction";quit -f -code 1}\nputs "VERIFIED_PASS_BIT=1"\nquit -f -code 0\n'
 (cand/'tb_overlap_throughput.do').write_text(head+tail)
 s=(out/'fullhd_tests/tb_fullhd_capture_display.sv').read_text().replace('module tb_fullhd_capture_display','module tb_banked_capture_display')
 s=s.replace("wire load_proc_valid=1'b0;wire [27:0] load_proc_addr=0;", "integer processor_served=0,processor_wait=0,max_processor_wait=0;wire load_proc_valid=reset_n;wire [27:0] load_proc_addr=28'h0100000;")
 s=s.replace(' ddr_capture_writer #', ' ddr_capture_writer_banked #')
 s=s.replace('.c0_valid(load_proc_valid),','.c0_valid(load_proc_valid&&empty&&!prefetch_busy),')
 s=s.replace('wire ack,cmd_valid;', 'wire ack,cmd_valid,prefetch_busy;')
 s=s.replace('.prefetch_busy()', '.prefetch_busy(prefetch_busy)')
 s=s.replace('.request_toggle(capture_request),.rx_complete_toggle(rx_done),.rx_capture_ok(rx_ok),',".base_word_addr(28'h0800000),.request_toggle(capture_request),.rx_complete_toggle(rx_done),.rx_capture_ok(rx_ok),")
 s=s.replace('load_cap_addr!==capture_served*8',"load_cap_addr!==28'h0800000+capture_served*8")
 s=s.replace('capture_data!==source_word(load_cap_addr)',"capture_data!==source_word(load_cap_addr-28'h0800000)")
 s=s.replace('FULLHD_CAPTURE_DISPLAY_PASS source_pixels=', 'BANKED_FULLHD_CAPTURE_DISPLAY_PASS source_pixels=')
 s=s.replace('  $display("BANKED_FULLHD_CAPTURE_DISPLAY_PASS', '  if(processor_served<100)$fatal(1,"processor reads did not progress during banked full-HD capture");\n  $display("PROCESSOR_MAX_UI_WAIT=%0d UI_PERIOD_NS=8",max_processor_wait);\n  if(max_processor_wait>=4629000)$fatal(1,"parallel memory wait exceeds processor watchdog");\n  $display("BANKED_FULLHD_CAPTURE_DISPLAY_PASS')
 s=s.replace('  if(cmd_valid&&cmd_ready)requests=requests+1;', '  if(cmd_valid&&cmd_ready)requests=requests+1;\n  if(load_proc_valid&&load_proc_ready)begin processor_served=processor_served+1;processor_wait=0;end\n  else if(load_proc_valid)begin processor_wait=processor_wait+1;if(processor_wait>max_processor_wait)max_processor_wait=processor_wait;end')
 (out/'fullhd_tests/tb_banked_capture_display.sv').write_text(s)
 template=(cand/'tb_fullhd_capture_display.do').read_text()
 (cand/'tb_banked_capture_display.do').write_text(template.replace('tb_fullhd_capture_display','tb_banked_capture_display').replace('work_fullhd','work_banked_fullhd').replace('vlib work_banked_fullhd','if {![file isdirectory work_banked_fullhd]} {vlib work_banked_fullhd}'))
if __name__=='__main__':main()
