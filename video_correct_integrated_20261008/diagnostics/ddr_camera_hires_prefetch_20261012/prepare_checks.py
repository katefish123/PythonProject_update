"""Add real engine/core ownership and simultaneous-memory-load regressions."""
from pathlib import Path
import json

D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/"results"
high=R/"diagnostics/ddr_camera_hires_20261011"
proto=R/"diagnostics/ddr_hires_read_ahead_20261011/results"
script=(high/"prepare_checks.py").read_text(encoding="utf-8-sig")
exec(compile(script,str(D/"prepare_checks.py"),"exec"),{"__file__":str(D/"prepare_checks.py"),"__name__":"__main__"})
cases=json.loads((O/"simulation_cases.json").read_text(encoding="utf-8-sig"))
manifest=json.loads((O/"source_hashes.json").read_text(encoding="utf-8-sig"))
rtl=[Path(p) for p in manifest if p.endswith(".v") and "/ddr3_ip/" not in p.replace("\\","/") and "/ip/" not in p.replace("\\","/")]
for name in ["tb_ddr_word_engine","tb_ddr_read_ahead"]:
    (O/(name+".sv")).write_bytes((proto/(name+".sv")).read_bytes())

display=(proto/"tb_hires_read_ahead_display.sv").read_text(encoding="utf-8-sig")
display=display.replace("parameter READ_AHEAD=1,EXPECT_UNDERRUN=0","parameter READ_AHEAD=1,EXPECT_UNDERRUN=0,LOAD_TRAFFIC=0")
display=display.replace(" wire [63:0] diagnostics;\n","")
display=display.replace(",.diagnostic_snapshot(diagnostics)","")
display=display.replace('  if(diagnostics[31:22]==0 || diagnostics[63:48]==0 || diagnostics[47:32]<diagnostics[63:48])$fatal(1,"invalid actual row timing snapshot");\n',"")
display=display.replace("diagnostics[47:32]","row_max_ui_cycles")
monitor=r'''
 integer row_ui_cycles=0,row_max_ui_cycles=0;
 always @(posedge ui_clk)begin
  if(!reset_n)begin row_ui_cycles=0;row_max_ui_cycles=0;end
  else if(dut.ui_state==dut.UI_IDLE)row_ui_cycles=0;
  else begin
   row_ui_cycles=row_ui_cycles+1;
   if(dut.ui_state==dut.UI_WRITE && dut.burst_index==OW/8-1 &&
      (!dut.scan_active_ui[2] || dut.ui_line_row[0]!=dut.scan_row_ui2[0]) &&
      row_ui_cycles>row_max_ui_cycles)row_max_ui_cycles=row_ui_cycles;
  end
 end
 function [255:0] source_word(input [27:0] address);
  for(integer q=0;q<8;q=q+1)source_word[q*32+:32]={8'd0,24'h200000|(address+q)};
 endfunction
 reg load_proc_valid=0,load_cap_valid=0,load_proc_pending=0,load_cap_pending=0;
 reg [27:0] load_proc_addr=0,load_cap_addr=0;
 wire load_proc_ready,load_cap_ready,load_proc_rsp,load_cap_rsp,load_proc_write,load_cap_write;
 wire [255:0] load_proc_data,load_cap_data;
 integer capture_backlog=0,capture_max_backlog=0,capture_produced=0,capture_served=0,processor_served=0;
 wire capture_produce=LOAD_TRAFFIC&&reset_n&&(ui_cycle%24==0);
 always @(posedge ui_clk)begin
  if(!reset_n || !LOAD_TRAFFIC)begin
   load_proc_valid<=0;load_cap_valid<=0;load_proc_pending<=0;load_cap_pending<=0;
   load_proc_addr<=0;load_cap_addr<=0;capture_backlog=0;capture_max_backlog=0;
   capture_produced=0;capture_served=0;processor_served=0;
  end else begin
   if(capture_produce)begin capture_backlog=capture_backlog+1;capture_produced=capture_produced+1;end
   if(load_cap_rsp)begin
    if(!load_cap_pending||!load_cap_write)$fatal(1,"capture response ownership/write type");
    load_cap_pending<=0;capture_backlog=capture_backlog-1;capture_served=capture_served+1;
    load_cap_addr<=load_cap_addr>=518392?28'd0:load_cap_addr+8;
   end
   if(capture_backlog>capture_max_backlog)capture_max_backlog=capture_backlog;
   if(capture_backlog<0||capture_backlog>=1024)$fatal(1,"capture backlog exceeded production FIFO");
   if(!load_cap_valid&&!load_cap_pending&&capture_backlog>0)load_cap_valid<=1;
   if(load_cap_valid&&load_cap_ready)begin load_cap_valid<=0;load_cap_pending<=1;end
   if(!load_proc_valid&&!load_proc_pending&&ui_cycle%97==0)load_proc_valid<=1;
   if(load_proc_valid&&load_proc_ready)begin load_proc_valid<=0;load_proc_pending<=1;end
   if(load_proc_rsp)begin
    if(!load_proc_pending||load_proc_write||load_proc_data!==source_word(load_proc_addr))$fatal(1,"source processor response mixed with display/capture");
    load_proc_pending<=0;processor_served=processor_served+1;
    load_proc_addr<=load_proc_addr>=518392?28'd0:load_proc_addr+8;
   end
  end
 end
'''
anchor=" wire app_valid,app_ready,app_write,app_response,app_response_write;"
assert display.count(anchor)==1
display=display.replace(anchor,monitor+anchor)
before=".c0_valid(1'b0),.c0_ready(),.c0_write(1'b0),.c0_addr(28'd0),.c0_wdata(256'd0),.c0_wstrb(32'd0),.c0_rsp_valid(),.c0_rsp_write(),.c0_rdata(),"
after=".c0_valid(load_proc_valid),.c0_ready(load_proc_ready),.c0_write(1'b0),.c0_addr(load_proc_addr),.c0_wdata(256'd0),.c0_wstrb(32'd0),.c0_rsp_valid(load_proc_rsp),.c0_rsp_write(load_proc_write),.c0_rdata(load_proc_data),"
assert display.count(before)==1
display=display.replace(before,after)
before=".c1_valid(1'b0),.c1_ready(),.c1_write(1'b0),.c1_addr(28'd0),.c1_wdata(256'd0),.c1_wstrb(32'd0),.c1_rsp_valid(),.c1_rsp_write(),.c1_rdata(),"
after=".c1_valid(load_cap_valid),.c1_ready(load_cap_ready),.c1_write(1'b1),.c1_addr(load_cap_addr),.c1_wdata(source_word(load_cap_addr)),.c1_wstrb(32'hffffffff),.c1_rsp_valid(load_cap_rsp),.c1_rsp_write(load_cap_write),.c1_rdata(load_cap_data),"
assert display.count(before)==1
display=display.replace(before,after)
display=display.replace('if(engine_fault||axi_awvalid)$fatal(1,"display protocol/ownership fault");',
    'if(engine_fault)$fatal(1,"display protocol/ownership fault");')
display=display.replace('''    if(mem_y>=OH||mem_x>=OW)$fatal(1,"read-ahead exceeded result bounds");
    for(integer lane=0;lane<8;lane=lane+1)rdata[lane*32+:32]={8'd0,encode_pixel(mem_bank,mem_y,mem_x+lane)};''',
'''    if(memory_base<28'h0100000)rdata=source_word(memory_base+beat*8);
    else begin
     if(mem_y>=OH||mem_x>=OW)$fatal(1,"read-ahead exceeded result bounds");
     for(integer lane=0;lane<8;lane=lane+1)rdata[lane*32+:32]={8'd0,encode_pixel(mem_bank,mem_y,mem_x+lane)};
    end''')
display=display.replace("if(!EXPECT_UNDERRUN&&physical_reads!=","if(!EXPECT_UNDERRUN&&!LOAD_TRAFFIC&&physical_reads!=")
display=display.replace('  test_passed=1;$display("HIRES_ENGINE_DISPLAY_PASS',
'''  if(LOAD_TRAFFIC&&(capture_served<10000||processor_served<100))$fatal(1,"other memory clients did not make progress");
  $display("SHARED_MEMORY_COUNTS capture=%0d source=%0d max_capture_backlog=%0d assumed_capture_period=24",capture_served,processor_served,capture_max_backlog);
  test_passed=1;$display("HIRES_ENGINE_DISPLAY_PASS''')
(O/"tb_hires_read_ahead_display.sv").write_text(display,encoding="utf-8")

core=(O/"tb_video_correct_ddr_core.sv").read_text(encoding="utf-8-sig")
core=core.replace("module tb_video_correct_ddr_core;","module tb_core_word_engine;")
core=core.replace("reg cmd_ready=0,rsp_valid=0,rsp_write=0; reg [255:0] rsp_rdata=0;",
    "wire cmd_ready,rsp_valid,rsp_write,engine_fault;wire [255:0] rsp_rdata;reg [27:0] last_cmd_addr;")
core=core.replace(".memory_fault(memory_fault)",".memory_fault(memory_fault|engine_fault)")
start=core.index(" always @(negedge ui_clk) begin")
end=core.index(" always @(posedge ui_clk) if(ui_rst_n&&cmd_valid&&cmd_ready)",start)
model=r'''
 wire [27:0] axi_awaddr,axi_araddr;wire [3:0] axi_awid,axi_arid,axi_awlen,axi_arlen;
 wire axi_awap,axi_arap,axi_awvalid,axi_arvalid;wire [255:0] axi_wdata;wire [31:0] axi_mask;
 reg arready=0,rvalid=0,rlast=0;reg [255:0] rdata=0;
 reg memory_pending=0;reg [27:0] read_base;integer read_beat=0,read_total=0,ui_tick=0;
 ddr_word_engine #(.READ_AHEAD_ENABLE(1),.RESULT_WORDS(PIXELS)) engine(
  .clk(ui_clk),.rst_n(ui_rst_n),.init_done(ddr_ready),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_write(cmd_write),.cmd_addr(cmd_addr),.cmd_wdata(cmd_wdata),.cmd_wstrb(cmd_wstrb),
  .rsp_valid(rsp_valid),.rsp_write(rsp_write),.rsp_rdata(rsp_rdata),.fault(engine_fault),
  .axi_awaddr(axi_awaddr),.axi_awuser_ap(axi_awap),.axi_awuser_id(axi_awid),.axi_awlen(axi_awlen),.axi_awvalid(axi_awvalid),.axi_awready(1'b1),
  .axi_wdata(axi_wdata),.axi_wstrb(axi_mask),.axi_wready(1'b1),.axi_wusero_id(4'd0),.axi_wusero_last(1'b1),
  .axi_araddr(axi_araddr),.axi_aruser_ap(axi_arap),.axi_aruser_id(axi_arid),.axi_arlen(axi_arlen),.axi_arvalid(axi_arvalid),.axi_arready(arready),
  .axi_rdata(rdata),.axi_rid(4'd0),.axi_rlast(rlast),.axi_rvalid(rvalid));
 always @(negedge ui_clk)begin
  ui_tick=ui_tick+1;arready=ui_rst_n&&!memory_pending&&(ui_tick%5!=0);rvalid=0;rlast=0;
  if(!ui_rst_n)begin memory_pending=0;read_beat=0;end
  else if(!memory_pending&&axi_arvalid&&arready)begin
   read_base=axi_araddr;read_total=axi_arlen+1;read_beat=0;delay_count=4+(ui_tick%3);memory_pending=1;
  end else if(memory_pending)begin
   if(delay_count>0)delay_count=delay_count-1;
   else begin
    rdata=memory_read(read_base+read_beat*8);rvalid=1;rlast=(read_beat==read_total-1);read_beat=read_beat+1;
    if(read_beat==read_total)memory_pending=0;
   end
  end
 end
 always @(posedge ui_clk)if(ui_rst_n)begin
  if(engine_fault)$fatal(1,"core physical DDR engine fault");
  if(axi_awvalid)begin
   if(axi_awlen!=0||axi_mask!==32'hffffffff)$fatal(1,"core write protocol changed");
   if(axi_awaddr>=28'h03f0000&&axi_awaddr<28'h03f0040)bist_mem[(axi_awaddr-28'h03f0000)>>3]<=axi_wdata;
   else if(axi_awaddr<SRC_PIXELS)src_mem[axi_awaddr>>3]<=axi_wdata;
   else if(axi_awaddr>=28'h0100000&&axi_awaddr<28'h0100000+PIXELS)bank0[(axi_awaddr-28'h0100000)>>3]<=axi_wdata;
   else if(axi_awaddr>=28'h0200000&&axi_awaddr<28'h0200000+PIXELS)bank1[(axi_awaddr-28'h0200000)>>3]<=axi_wdata;
   else $fatal(1,"unexpected core physical write address");
  end
  if(rsp_valid&&rsp_write&&((last_cmd_addr>=28'h0100000&&last_cmd_addr<28'h0100000+PIXELS)||(last_cmd_addr>=28'h0200000&&last_cmd_addr<28'h0200000+PIXELS)))dest_responses<=dest_responses+1;
 end
'''
core=core[:start]+model+core[end:]
core=core.replace('  if(pending) $fatal(1,"overlapping UI memory commands");',"")
core=core.replace("  pending<=1;pending_write<=cmd_write;pending_addr<=cmd_addr;pending_data<=cmd_wdata;delay_count<=(cmd_count%4);","  last_cmd_addr<=cmd_addr;")
core=core.replace("bist_mem[(cmd_addr-28'h03f0000)>>3]<=cmd_wdata;","")
core=core.replace("src_mem[cmd_addr>>3]<=cmd_wdata;","")
core=core.replace("bank0[(cmd_addr-28'h0100000)>>3]<=cmd_wdata;","")
core=core.replace("bank1[(cmd_addr-28'h0200000)>>3]<=cmd_wdata;","")
core=core.replace('DDR_CORE_PASS','CORE_WORD_ENGINE_PASS')
(O/"tb_core_word_engine.sv").write_text(core,encoding="utf-8")
extra={
 "tb_ddr_word_engine":("DDR_WORD_ENGINE_PASS",[O/"ddr_word_engine.v",O/"tb_ddr_word_engine.sv"],"tb_ddr_word_engine",""),
 "tb_ddr_read_ahead":("DDR_READ_AHEAD_PASS",[O/"ddr_word_engine.v",O/"tb_ddr_read_ahead.sv"],"tb_ddr_read_ahead",""),
 "tb_hires_read_ahead_display":("HIRES_ENGINE_DISPLAY_PASS",[O/"ddr_word_engine.v",O/"ddr_result_display.v",R/"rtl/memory/ddr_arbiter3.v",R/"vendor/c_current/01_design_code/video_timing_vtc.v",O/"tb_hires_read_ahead_display.sv"],"tb_hires_read_ahead_display",""),
 "tb_hires_read_ahead_control":("HIRES_ENGINE_DISPLAY_PASS",[O/"ddr_word_engine.v",O/"ddr_result_display.v",R/"rtl/memory/ddr_arbiter3.v",R/"vendor/c_current/01_design_code/video_timing_vtc.v",O/"tb_hires_read_ahead_display.sv"],"tb_hires_read_ahead_display","-gREAD_AHEAD=0 -gEXPECT_UNDERRUN=1 "),
 "tb_hires_read_ahead_shared":("HIRES_ENGINE_DISPLAY_PASS",[O/"ddr_word_engine.v",O/"ddr_result_display.v",R/"rtl/memory/ddr_arbiter3.v",R/"vendor/c_current/01_design_code/video_timing_vtc.v",O/"tb_hires_read_ahead_display.sv"],"tb_hires_read_ahead_display","-gLOAD_TRAFFIC=1 "),
 "tb_core_word_engine":("CORE_WORD_ENGINE_PASS",rtl+[O/"tb_core_word_engine.sv"],"tb_core_word_engine",""),
}
for name,(marker,paths,top,generic) in extra.items():
    lines=["onerror {quit -f -code 1}",f"transcript file {{{(O/(name+'.transcript.log')).as_posix()}}}",
      f"if {{![file isdirectory work_{name}]}} {{vlib work_{name}}}",f"vmap work_{name} work_{name}",
      f"vlog -sv -work work_{name} "+" ".join("{"+p.as_posix()+"}" for p in paths),
      f"vsim -c -voptargs=+acc -wlf {{{(O/(name+'.wlf')).as_posix()}}} {generic}work_{name}.{top}","onfinish stop","run -all",
      f"set pass_bit [examine -value -radix binary -noshowbase sim:/{top}/test_passed]",
      'if {[llength $pass_bit]!=1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}',
      'puts "VERIFIED_PASS_BIT=1"',"quit -f -code 0"]
    (O/(name+".do")).write_text("\n".join(lines)+"\n",encoding="utf-8")
    cases[name]=marker
assert len(cases)==12
(O/"simulation_cases.json").write_text(json.dumps(cases,indent=2)+"\n",encoding="utf-8")
print("Prepared twelve checks: high pixels/capture, protocol/coherency, delayed scanout, shared traffic and real core/engine data ownership.")
