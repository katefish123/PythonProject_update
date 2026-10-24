"""Build a reduced-width, production-depth shared-service failure regression."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parent
PACKAGE=Path('D:/FPGA/deliveries/FullHD_Lens_IntegratedRepair_20261023')
source=PACKAGE/'validation/baseline_test/source_snapshot/tb_lens_board.sv'
text=source.read_text()
def replace(old,new):
    global text
    if text.count(old)!=1:raise RuntimeError('Unexpected anchor '+old[:100])
    text=text.replace(old,new)
replace('module tb_raw_pipeline #(parameter NATIVE=1,FRAMES=2,CORRECTED=1,REQUIRE_RAW30=0,BAD_FRAME=0,CAMERA_START_LINE=0,RGB_PATTERN=0);',
'''module tb_service_starvation #(parameter ADVERSE=1);
 localparam NATIVE=0,FRAMES=3,CORRECTED=0,REQUIRE_RAW30=0,BAD_FRAME=0,CAMERA_START_LINE=0,RGB_PATTERN=1;
 integer pixel_errors=0,fifo_full_cycles=0,close12=0,close13=0,first_pub_frame=0;''')
replace('localparam SW=NATIVE?1920:128,SH=NATIVE?1080:(CORRECTED?48:16),OW=NATIVE?1920:64;',
        'localparam SW=128,SH=1080,OW=128;')
replace('localparam HS=NATIVE?44:4,HB=NATIVE?148:8,HF=NATIVE?88:512;',
        'localparam HS=4,HB=8,HF=16;')
replace('localparam VS=NATIVE?5:2,VB=NATIVE?36:4,VF=4;', 'localparam VS=2,VB=4,VF=4;')
replace('video_correct_ddr_continuous_core #(', 'video_correct_ddr_continuous_core #(.BIST_ONLY_NATIVE_WDATA(1),')
replace('integer ui_tick=0,read_beat=0,read_total=0,read_delay=0,write_index=0,write_total=0,reads=0,writes=0;',
'''integer ui_tick=0,read_beat=0,read_total=0,read_delay=0,write_index=0,write_total=0,reads=0,writes=0,write_delay=0;
 wire slow_window;
 integer slow_read_commands=0,slow_write_commands=0;''')
replace('integer camera_x=0,camera_y=CAMERA_START_LINE,physical_frames=0;integer bank_id[0:1];reg[31:0]seen_generation=0;',
'''integer camera_x=0,camera_y=CAMERA_START_LINE,physical_frames=0;integer bank_id[0:1];reg[31:0]seen_generation=0;
 assign slow_window=ADVERSE&&good>=1&&camera_y>=VS+VB&&camera_y<VS+VB+SH/2;''')
replace('wire wready=rst_n&&(ui_tick%11!=0),awready=rst_n&&(ui_tick%17>=2),arready=rst_n&&!read_pending&&(ui_tick%7!=0);',
        'wire wready=rst_n&&write_pending&&write_delay==0&&(ui_tick%11!=0),awready=rst_n&&(ui_tick%17>=2),arready=rst_n&&!read_pending&&(ui_tick%7!=0);')
replace('ui_tick++;', 'ui_tick++;\n if(write_pending&&write_delay>0)write_delay<=write_delay-1;')
replace('if(engine_fault||bist_fail||source_fault)$fatal(1,"pipeline fault engine=%0d source=%b",engine_reason,source_fault);',
        'if(engine_fault||bist_fail)$fatal(1,"pipeline fault engine=%0d source=%b",engine_reason,source_fault);')
replace('read_delay<=28+((reads%128==127)?100:0);reads++;',
        'read_delay<=slow_window?320:4;if(slow_window)slow_read_commands++;reads++;')
replace('write_pending<=1;write_base<=awaddr;write_index<=0;write_total<=awlen+1;',
        'write_pending<=1;write_base<=awaddr;write_index<=0;write_total<=awlen+1;write_delay<=slow_window?320:0;if(slow_window)slow_write_commands++;')
replace('end else if(rgb!==pattern(scan_id,px,py))$fatal(1,"RAW pixel mismatch id=%0d x=%0d y=%0d actual=%h",scan_id,px,py,rgb);',
'''end else if(rgb!==pattern(scan_id,px,py))begin
 pixel_errors++;if(pixel_errors==1)$display("DISPLAY_FAILURE id=%0d x=%0d y=%0d actual=%h expected=%h time=%0t",scan_id,px,py,rgb,pattern(scan_id,px,py),$time);
 end''')
replace('end else if(rejected!=0)$fatal(1,"unexpected rejected frame");',
        'end else if(!ADVERSE&&rejected!=0)$fatal(1,"control unexpectedly rejected frame");')
for name in ('source.hex','source_alt.hex','expected.hex','expected_alt.hex','H40.hex'):
    # No fixture is used in this RAW patterned-camera test; do not fabricate
    # truncated native fixtures for the reduced-resolution memory arrays.
    text='\n'.join(line for line in text.split('\n') if not ('$readmemh(' in line and '/'+name+'"' in line))
old=''' wait(unique_scans>=FRAMES);@(posedge dut.scan_start);#100;
 if(checked<FRAMES*WORDS||writes<FRAMES*WORDS/8||good<FRAMES)$fatal(1,"insufficient coverage");
 if(CORRECTED&&BAD_FRAME>0&&rejected!=1)$fatal(1,"bad-marker rejection not exercised");
 if(REQUIRE_RAW30&&!CORRECTED&&maximum_steady_interval>2*HT*VT*6.734008+1000)$fatal(1,"RAW30_DEADLINE_MISSED interval_ns=%0d",maximum_steady_interval);
 $display("PASS RAW_PIPELINE corrected=%0d native=%0d pixels=%0d unique_scans=%0d published=%0d reads=%0d writes=%0d physical_frames=%0d admitted=%0d dropped=%0d",CORRECTED,NATIVE,checked,unique_scans,good,reads,writes,physical_frames,admitted,dropped);$finish;'''
replace(old,''' if(!ADVERSE)begin
  wait(unique_scans>=3);@(posedge dut.scan_start);#100;
  if(good<3||pixel_errors!=0||rejected!=0||engine_fault||bist_fail)$fatal(1,"control failed");
  $display("PASS SERVICE_CONTROL physical=%0d good=%0d pix_id=%0d pixels=%0d peak=%0d",physical_frames,good,dut.debug_display_id,checked,dut.data_fifo_peak);$finish;
 end else begin
  wait(good>=1);first_pub_frame=physical_frames;
  wait(physical_frames>=first_pub_frame+6);repeat(10000)@(negedge ui_clk);
  summary();
  if(good==1&&dut.data_fifo_peak==1024&&fifo_full_cycles>0&&(rejected_reason_counts[13*32+:32]>0||close13>0))
   $fatal(1,"SERVICE_STARVATION_REPRO first publication followed by overflow and no new RAW image");
  $fatal(1,"SERVICE_DIAGNOSTIC_NO_TARGET inspect recorded distribution and counters");
 end''')
replace('initial begin #(NATIVE?FRAMES*100000000+100000000:10000000);$fatal(1,"pipeline timeout");end',
        'initial begin #50000000;summary();$fatal(1,"service experiment timeout");end')
replace('endmodule', '''
 integer cap_accepts=0,display_accepts=0,cap_wait=0,max_cap_wait=0,last_rejected=0,last_frame=0;
 always @(posedge rx_clk)if(rst_n)begin
  if(good>=1&&!dut.continuous_sources.queue_ready)fifo_full_cycles++;
  if(dut.continuous_sources.close_valid)begin
   if(dut.continuous_sources.close_reason==12)close12++;
   if(dut.continuous_sources.close_reason==13)close13++;
   $display("CAPTURE_CLOSE gen=%0d ok=%b reason=%0d peak=%0d full_cycles=%0d time=%0t",dut.continuous_sources.close_generation,dut.continuous_sources.close_ok,dut.continuous_sources.close_reason,dut.data_fifo_peak,fifo_full_cycles,$time);
  end
 end
 always @(posedge ui_clk)if(rst_n&&bist_pass)begin
  if(dut.cap_v&&!dut.cap_r)begin cap_wait++;if(cap_wait>max_cap_wait)max_cap_wait=cap_wait;end else cap_wait=0;
  if(cmd_v&&cmd_r)begin if(dut.ui_mux.grant==1)cap_accepts++;if(dut.ui_mux.grant==2)display_accepts++;end
 end
 always @(posedge proc_clk)if(rst_n&&rejected!=last_rejected)begin
  last_rejected=rejected;$display("REJECT total=%0d r12=%0d r13=%0d r14=%0d r15=%0d source_fault=%b time=%0t",rejected,rejected_reason_counts[12*32+:32],rejected_reason_counts[13*32+:32],rejected_reason_counts[14*32+:32],rejected_reason_counts[15*32+:32],source_fault,$time);
 end
 task summary;
 begin
  $display("SERVICE_SUMMARY adverse=%0d physical=%0d admitted=%0d dropped=%0d rejected=%0d good=%0d raw=%0d pix_id=%0d actual_raw=%b",ADVERSE,physical_frames,admitted,dropped,rejected,good,raw_pubs,dut.debug_display_id,display_raw);
  $display("SERVICE_CAUSES r12=%0d r13=%0d r14=%0d r15=%0d rx_close12=%0d rx_close13=%0d fifo_peak=%0d fifo_full_cycles=%0d pixel_errors=%0d underrun=%b engine_fault=%b source_fault=%b",rejected_reason_counts[12*32+:32],rejected_reason_counts[13*32+:32],rejected_reason_counts[14*32+:32],rejected_reason_counts[15*32+:32],close12,close13,dut.data_fifo_peak,fifo_full_cycles,pixel_errors,underrun,engine_fault,source_fault);
  $display("SERVICE_TIMING slow_reads=%0d slow_writes=%0d read_cmds=%0d write_beats=%0d cap_accepts=%0d display_accepts=%0d max_cap_wait_ui=%0d",slow_read_commands,slow_write_commands,reads,writes,cap_accepts,display_accepts,max_cap_wait);
 end endtask
endmodule''')
(ROOT/'tb_service_starvation.sv').write_text(text)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
(ROOT/'bench_binding.json').write_text(json.dumps({'parent_bench':str(source),'parent_bench_sha256':sha(source),
 'generated_bench_sha256':sha(ROOT/'tb_service_starvation.sv'),'generator_sha256':sha(Path(__file__)),
 'scope':'Reduced 128x1080 RAW, real 1024 FIFO/8beat writer/display priority, clustered max320 UI-cycle first-beat service; not measured board latency or production fullHD throughput'},indent=2)+'\n')
print(ROOT/'tb_service_starvation.sv')
