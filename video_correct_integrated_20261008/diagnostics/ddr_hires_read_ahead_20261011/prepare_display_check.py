"""Check the real display/arbiter/engine chain with slower AXI and refresh delays."""
from pathlib import Path
import json

D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/"results"
source=R/"diagnostics/ddr_camera_hires_status_20261011/results/tb_native_display.sv"
text=source.read_text(encoding="utf-8-sig")
text=text.replace('module tb_native_display #(parameter CONTENTIOUS=0);','module tb_hires_read_ahead_display #(parameter READ_AHEAD=1,EXPECT_UNDERRUN=0);')
text=text.replace('reg rsp_valid=0;reg [255:0] rsp_data=0;','wire rsp_valid;wire [255:0] rsp_data;')
text=text.replace('integer ui_cycle=0,delay_count=0,requests=0,mem_y,mem_x,mem_bank;',
    'integer ui_cycle=0,delay_count=0,requests=0,physical_reads=0,mem_y,mem_x,mem_bank;\n integer correct_pixels=0,black_pixels=0;')
start=text.index(' assign cmd_ready=')
end=text.index(' always @(posedge pix_clk)',start)
model=r'''
 wire app_valid,app_ready,app_write,app_response,app_response_write;
 wire [27:0] app_addr;wire [255:0] app_wdata,app_rdata;wire [31:0] app_mask;
 ddr_arbiter3 owner(.clk(ui_clk),.rst_n(reset_n),.enabled(1'b1),
  .c0_valid(1'b0),.c0_ready(),.c0_write(1'b0),.c0_addr(28'd0),.c0_wdata(256'd0),.c0_wstrb(32'd0),.c0_rsp_valid(),.c0_rsp_write(),.c0_rdata(),
  .c1_valid(1'b0),.c1_ready(),.c1_write(1'b0),.c1_addr(28'd0),.c1_wdata(256'd0),.c1_wstrb(32'd0),.c1_rsp_valid(),.c1_rsp_write(),.c1_rdata(),
  .c2_valid(cmd_valid),.c2_ready(cmd_ready),.c2_write(1'b0),.c2_addr(cmd_addr),.c2_wdata(256'd0),.c2_wstrb(32'd0),.c2_rsp_valid(rsp_valid),.c2_rsp_write(),.c2_rdata(rsp_data),
  .cmd_valid(app_valid),.cmd_ready(app_ready),.cmd_write(app_write),.cmd_addr(app_addr),.cmd_wdata(app_wdata),.cmd_wstrb(app_mask),
  .rsp_valid(app_response),.rsp_write(app_response_write),.rsp_rdata(app_rdata));
 wire [27:0] axi_awaddr,axi_araddr;wire [3:0] axi_awid,axi_arid,axi_awlen,axi_arlen;
 wire axi_awap,axi_arap,axi_awvalid,axi_arvalid,engine_fault;
 wire [255:0] axi_wdata;wire [31:0] axi_mask;
 reg arready=0,rvalid=0,rlast=0;reg [255:0] rdata=0;
 reg memory_pending=0;reg [27:0] memory_base;integer beat=0,total=0;
 ddr_word_engine #(.READ_AHEAD_ENABLE(READ_AHEAD),.RESULT_WORDS(OW*OH)) engine(
  .clk(ui_clk),.rst_n(reset_n),.init_done(reset_n),.cmd_valid(app_valid),.cmd_ready(app_ready),.cmd_write(app_write),.cmd_addr(app_addr),.cmd_wdata(app_wdata),.cmd_wstrb(app_mask),
  .rsp_valid(app_response),.rsp_write(app_response_write),.rsp_rdata(app_rdata),.fault(engine_fault),
  .axi_awaddr(axi_awaddr),.axi_awuser_ap(axi_awap),.axi_awuser_id(axi_awid),.axi_awlen(axi_awlen),.axi_awvalid(axi_awvalid),.axi_awready(1'b1),
  .axi_wdata(axi_wdata),.axi_wstrb(axi_mask),.axi_wready(1'b1),.axi_wusero_id(4'd0),.axi_wusero_last(1'b1),
  .axi_araddr(axi_araddr),.axi_aruser_ap(axi_arap),.axi_aruser_id(axi_arid),.axi_arlen(axi_arlen),.axi_arvalid(axi_arvalid),.axi_arready(arready),
  .axi_rdata(rdata),.axi_rid(4'd0),.axi_rlast(rlast),.axi_rvalid(rvalid));
 always @(posedge ui_clk)if(reset_n)begin
  if(cmd_valid&&cmd_ready)requests=requests+1;
  if(axi_arvalid&&arready)physical_reads=physical_reads+1;
  if(engine_fault||axi_awvalid)$fatal(1,"display protocol/ownership fault");
 end
 // Hypothetical physical memory: 28-cycle first-beat response; occasionally
 // another 100 clocks model a refresh wait. Stream all burst beats without RREADY.
 always @(negedge ui_clk)begin
  ui_cycle=ui_cycle+1;arready=reset_n&&!memory_pending&&(ui_cycle%7!=0);rvalid=0;rlast=0;
  if(!reset_n)begin memory_pending=0;beat=0;end
  else if(!memory_pending&&axi_arvalid&&arready)begin
   memory_base=axi_araddr;total=axi_arlen+1;beat=0;
   delay_count=28+((physical_reads%128==127)?100:0);memory_pending=1;
  end else if(memory_pending)begin
   if(delay_count>0)delay_count=delay_count-1;
   else begin
    mem_bank=(memory_base>=28'h0200000);
    mem_y=(memory_base+beat*8-(mem_bank?28'h0200000:28'h0100000))/OW;
    mem_x=(memory_base+beat*8-(mem_bank?28'h0200000:28'h0100000))%OW;
    if(mem_y>=OH||mem_x>=OW)$fatal(1,"read-ahead exceeded result bounds");
    for(integer lane=0;lane<8;lane=lane+1)rdata[lane*32+:32]={8'd0,encode_pixel(mem_bank,mem_y,mem_x+lane)};
    rvalid=1;rlast=(beat==total-1);beat=beat+1;
    if(beat==total)memory_pending=0;
   end
  end
 end
'''
text=text[:start]+model+text[end:]
before='''   if(rgb!==encode_pixel(frame_bank,vd2-Y0,hd2-X0))$fatal(1,"native row/word/lane mismatch bank=%0d x=%0d y=%0d got=%h expected=%h",frame_bank,hd2-X0,vd2-Y0,rgb,encode_pixel(frame_bank,vd2-Y0,hd2-X0));'''
after='''   if(rgb===encode_pixel(frame_bank,vd2-Y0,hd2-X0))correct_pixels=correct_pixels+1;
   else if(EXPECT_UNDERRUN&&rgb===24'd0)black_pixels=black_pixels+1;
   else $fatal(1,"display/arbiter/engine lost or mixed a row bank=%0d x=%0d y=%0d",frame_bank,hd2-X0,vd2-Y0);'''
assert text.count(before)==1
text=text.replace(before,after)
text=text.replace('if(underrun)$fatal(1,"native display underflow");',
    'if(!EXPECT_UNDERRUN&&underrun)$fatal(1,"cached full display underflow");\n    if(EXPECT_UNDERRUN&&(!underrun||black_pixels==0))$fatal(1,"control case failed to reproduce late rows");')
before='''  // Change the pending frame during active scan. Current pixels must retain bank0.
  wait(dut.vc==Y0+300&&dut.hc==X0+300);@(negedge pix_clk);pub_bank=1;pub_toggle=0;
  wait(completed_frames>=2);
  if(frame_bank!=1)$fatal(1,"second completed frame did not atomically swap to bank1");'''
after='''  if(EXPECT_UNDERRUN)wait(completed_frames>=1);
  else begin
   // Pending publication during active scan cannot mix physical memory banks.
   wait(dut.vc==Y0+300&&dut.hc==X0+300);@(negedge pix_clk);pub_bank=1;pub_toggle=0;
   wait(completed_frames>=2);
   if(frame_bank!=1)$fatal(1,"cached scanout did not swap atomically");
  end'''
assert text.count(before)==1
text=text.replace(before,after)
start=text.index('  test_passed=1;')
end=text.index('\n end',start)
text=text[:start]+'''  if(!EXPECT_UNDERRUN&&physical_reads!=2*OW*OH/64)$fatal(1,"unexpected prefetch transaction count %0d",physical_reads);
  test_passed=1;$display("HIRES_ENGINE_DISPLAY_PASS read_ahead=%0d expected_underflow=%0d frames=%0d correct_pixels=%0d black_pixels=%0d physical_reads=%0d logical_reads=%0d max_row_cycles=%0d model_latency_only=1",READ_AHEAD,EXPECT_UNDERRUN,completed_frames,correct_pixels,black_pixels,physical_reads,requests,diagnostics[47:32]);$finish;'''+text[end:]
(O/"tb_hires_read_ahead_display.sv").write_text(text,encoding="utf-8")
display=R/"diagnostics/ddr_camera_hires_status_20261011/results/ddr_result_display.v"
paths=[O/"ddr_word_engine.v",display,R/"rtl/memory/ddr_arbiter3.v",R/"vendor/c_current/01_design_code/video_timing_vtc.v",O/"tb_hires_read_ahead_display.sv"]
for name,generic in [("tb_hires_read_ahead_display",""),("tb_hires_read_ahead_control","-gREAD_AHEAD=0 -gEXPECT_UNDERRUN=1 ")]:
    top="tb_hires_read_ahead_display"
    lines=["onerror {quit -f -code 1}",f"transcript file {{{(O/(name+'.transcript.log')).as_posix()}}}",
        f"if {{![file isdirectory work_{name}]}} {{vlib work_{name}}}",f"vmap work_{name} work_{name}",
        f"vlog -sv -work work_{name} "+" ".join("{"+p.as_posix()+"}" for p in paths),
        f"vsim -c -voptargs=+acc {generic}work_{name}.{top}","onfinish stop","run -all",
        f"set pass_bit [examine -value -radix binary -noshowbase sim:/{top}/test_passed]",
        'if {[llength $pass_bit]!=1 || [lindex $pass_bit 0] ne "1"} {quit -f -code 1}',
        'puts "VERIFIED_PASS_BIT=1"',"quit -f -code 0"]
    (O/(name+".do")).write_text("\n".join(lines)+"\n",encoding="utf-8")
cases=json.loads((O/"simulation_cases.json").read_text(encoding="utf-8-sig"))
cases.update(tb_hires_read_ahead_display="HIRES_ENGINE_DISPLAY_PASS",tb_hires_read_ahead_control="HIRES_ENGINE_DISPLAY_PASS")
(O/"simulation_cases.json").write_text(json.dumps(cases,indent=2)+"\n",encoding="utf-8")
print("Prepared full 640x904 display/arbiter/AXI-engine bank swap and delayed-memory control comparison; no physical latency claim.")
