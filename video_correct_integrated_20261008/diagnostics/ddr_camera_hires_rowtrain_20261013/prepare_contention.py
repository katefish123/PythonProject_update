"""Same bounded AXI write stalls for old and repaired high-detail readers."""
from pathlib import Path
import json
D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/'results'
old=R/'diagnostics/ddr_camera_hires_prefetch_20261012/results'
test=(old/'tb_hires_read_ahead_display.sv').read_text(encoding='utf-8-sig')
test=test.replace('LOAD_TRAFFIC=0);','LOAD_TRAFFIC=0,WRITE_WAIT=0,CAPTURE_PERIOD=24,PROCESSOR_PERIOD=97,PHASED_TRAFFIC=0,READ_WAIT=28,SOURCE_READ_WAIT=28);')
test=test.replace('ui_cycle%24==0','ui_cycle%CAPTURE_PERIOD==0').replace('ui_cycle%97==0','ui_cycle%PROCESSOR_PERIOD==0')
test=test.replace(' wire capture_produce=LOAD_TRAFFIC', ''' // FrameSession freezes the source before enabling the processor. Model
 // one complete capture phase and a separate processor phase, while both
 // remain concurrent with the display. Legacy simultaneous traffic remains
 // as its own unchanged regression at zero added write stalls.
 wire capture_phase=!PHASED_TRAFFIC || ui_cycle%4166680>=2083340;
 wire processor_phase=!PHASED_TRAFFIC || (!capture_phase && capture_backlog==0 && !load_cap_pending && !load_cap_valid);
 wire capture_produce=capture_phase&&LOAD_TRAFFIC''')
test=test.replace('if(!load_proc_valid&&!load_proc_pending&&', 'if(processor_phase&&!load_proc_valid&&!load_proc_pending&&')
test=test.replace('delay_count=28+', "delay_count=(memory_base<28'h0100000 ? SOURCE_READ_WAIT : READ_WAIT)+")
test=test.replace('if(EXPECT_UNDERRUN&&(!underrun||black_pixels==0))',
    'if(EXPECT_UNDERRUN&&(!PHASED_TRAFFIC||completed_frames>=1)&&(!underrun||black_pixels==0))')
test=test.replace('if(EXPECT_UNDERRUN)wait(completed_frames>=1);',
    'if(EXPECT_UNDERRUN&&!PHASED_TRAFFIC)wait(completed_frames>=1);')
test=test.replace('"capture backlog exceeded production FIFO"','"capture backlog exceeded production FIFO produced=%0d served=%0d source=%0d rowmax=%0d state=%0d row=%0d",capture_produced,capture_served,processor_served,row_max_ui_cycles,dut.ui_state,dut.ui_line_row')
test=test.replace('dut.ui_state==dut.UI_WRITE && dut.burst_index==OW/8-1',
    '(dut.ui_state==dut.UI_WRITE || (dut.ui_state==dut.UI_RSP && rsp_valid)) && dut.burst_index==OW/8-1')
test=test.replace('.axi_awready(1\'b1)', '.axi_awready(awready)').replace('.axi_wready(1\'b1)', '.axi_wready(wready)')
anchor=' reg arready=0,rvalid=0,rlast=0;reg [255:0] rdata=0;'
assert test.count(anchor)==1
test=test.replace(anchor,anchor+'''
 reg awready=0,wready=0,write_pending=0;
 reg [27:0] held_awaddr=0;reg [255:0] held_wdata=0;reg [31:0] held_mask=0;
 integer write_countdown=0,physical_writes=0;
 // Model a bounded physical write drain after AW acceptance, separately from
 // the 28-clock read response/100-clock periodic refresh model. These are
 // adversarial simulation assumptions, not board measurements.
 always @(negedge ui_clk)begin
  awready=reset_n&&!write_pending;wready=0;
  if(!reset_n)begin write_pending=0;write_countdown=0;physical_writes=0;end
  else if(axi_awvalid&&awready)begin
   if(axi_awlen!=0 || axi_mask!==32'hffffffff)$fatal(1,"capture physical write contract");
   held_awaddr=axi_awaddr;held_wdata=axi_wdata;held_mask=axi_mask;
   if(WRITE_WAIT==0)begin wready=1;physical_writes=physical_writes+1;end
   else begin write_pending=1;write_countdown=WRITE_WAIT;end
  end else if(write_pending)begin
   if(axi_awaddr!==held_awaddr || axi_wdata!==held_wdata || axi_mask!==held_mask)$fatal(1,"write beat changed under physical backpressure");
   if(write_countdown>0)write_countdown=write_countdown-1;
   else begin wready=1;write_pending=0;physical_writes=physical_writes+1;end
  end
 end
''')
test=test.replace('assumed_capture_period=24",capture_served,processor_served,capture_max_backlog',
    'assumed_capture_period=%0d assumed_write_wait=%0d physical_writes=%0d",capture_served,processor_served,capture_max_backlog,CAPTURE_PERIOD,WRITE_WAIT,physical_writes')
(O/'tb_hires_read_ahead_display.sv').write_text(test,encoding='utf-8')
cases=json.loads((O/'simulation_cases.json').read_text(encoding='utf-8-sig'))
# Update the existing twelve tests to the optimized reader. Native address,
# whole frame RGB and real core ownership still use their unchanged goldens.
for name,display_source,generic in [
    ('tb_rowtrain_contention',O/'ddr_result_display.v','-gLOAD_TRAFFIC=1 -gWRITE_WAIT=12 -gREAD_WAIT=40 -gSOURCE_READ_WAIT=80 -gCAPTURE_PERIOD=32 -gPROCESSOR_PERIOD=97 -gPHASED_TRAFFIC=1 '),
    ('tb_old_contention_control',old/'ddr_result_display.v','-gLOAD_TRAFFIC=1 -gWRITE_WAIT=12 -gREAD_WAIT=40 -gSOURCE_READ_WAIT=80 -gCAPTURE_PERIOD=32 -gPROCESSOR_PERIOD=97 -gPHASED_TRAFFIC=1 -gEXPECT_UNDERRUN=1 '),
]:
    paths=[O/'ddr_word_engine.v',display_source,R/'rtl/memory/ddr_arbiter3.v',R/'vendor/c_current/01_design_code/video_timing_vtc.v',O/'tb_hires_read_ahead_display.sv']
    top='tb_hires_read_ahead_display'
    lines=['onerror {quit -f -code 1}',f'transcript file {{{(O/(name+".transcript.log")).as_posix()}}}',
        f'if {{![file isdirectory work_{name}]}} {{vlib work_{name}}}',f'vmap work_{name} work_{name}',
        f'vlog -sv -work work_{name} '+ ' '.join('{'+p.as_posix()+'}' for p in paths),
        f'vsim -c -voptargs=+acc -wlf {{{(O/(name+".wlf")).as_posix()}}} {generic}work_{name}.{top}',
        'onfinish stop','run -all',f'set pass_bit [examine -value -radix binary -noshowbase sim:/{top}/test_passed]',
        'if {[llength $pass_bit]!=1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}',
        'puts "VERIFIED_PASS_BIT=1"','quit -f -code 0']
    (O/(name+'.do')).write_text('\n'.join(lines)+'\n',encoding='utf-8')
    cases[name]='HIRES_ENGINE_DISPLAY_PASS'
assert len(cases)==14
(O/'simulation_cases.json').write_text(json.dumps(cases,indent=2)+'\n',encoding='utf-8')
print('Prepared identical old/new delayed-write contention models and twelve retained regression cases.')
