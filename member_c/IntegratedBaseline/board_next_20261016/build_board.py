"""Prepare an isolated board candidate. Never replace or program frozen V4S."""
from pathlib import Path
import re,json,hashlib
from PIL import Image,ImageDraw,ImageFont
H=Path(__file__).resolve().parent
F=Path('D:/FPGA/output/c_stream_board_v4s_20261016')
O=H/'board';O.mkdir(exist_ok=True)
def rep(s,a,b):
 assert s.count(a)==1,(a[:100],s.count(a));return s.replace(a,b)
s=(F/'diagnostics/ddr_camera_hires_prefetch_20261012/results/video_correct_ddr_top.v').read_text()
s=rep(s,'module video_correct_ddr_top(','''module video_correct_ddr_top #(
 parameter SOURCE_W=1920,SOURCE_H=1080,RESULT_W=768,RESULT_H=1080,
 parameter HS=44,HB=148,HF=88,VS=5,VB=36,VF=4,BIST_BEATS=256,
 parameter HDMI_HOLD=10000,RECOVERY_HOLD=100000,RECOVERY_TIMEOUT=5000000,RECOVERY_SETTLE=1000000
)(''')
s=rep(s,'board_recovery_reset recovery(', 'board_recovery_reset #(.HOLD_CYCLES(RECOVERY_HOLD),.LOCK_TIMEOUT(RECOVERY_TIMEOUT),.SETTLE_CYCLES(RECOVERY_SETTLE)) recovery(') if False else s
s=s.replace('hd_count<10000','hd_count<HDMI_HOLD').replace('hd_count==10000','hd_count==HDMI_HOLD')
s=rep(s,'.SRC_W(1920),.SRC_H(1080),', '.IN_W(SOURCE_W),.IN_H(SOURCE_H),.SRC_W(SOURCE_W),.SRC_H(SOURCE_H),.BIST_BEATS(BIST_BEATS),.H_SYNC(HS),.H_BACK(HB),.H_ACTIVE(SOURCE_W),.H_FRONT(HF),.V_SYNC(VS),.V_BACK(VB),.V_ACTIVE(SOURCE_H),.V_FRONT(VF),')
s=rep(s,'.OUT_W(768),.OUT_H(1080),', '.OUT_W(RESULT_W),.OUT_H(RESULT_H),')
s=s.replace('.SOURCE_WORDS(1920*1080)', '.SOURCE_WORDS(SOURCE_W*SOURCE_H)').replace('.RESULT_WORDS(768*1080)', '.RESULT_WORDS(RESULT_W*RESULT_H)')

s=rep(s,'reset_sync ddr_reset(.clk(ref_clk),.arst_n(clocks_ready),','reset_sync ddr_reset(.clk(ref_clk),.arst_n(clocks_ready&&memory_release_n),')
s=rep(s,'wire cfg_rst,mem_reset,proc_rst,rx_rst,pix_rst,ui_rst;', '''wire cfg_rst,mem_reset,proc_rst,rx_rst,pix_rst,ui_rst;
 wire memory_release_n,recovering,retry_exhausted;wire[7:0]recovery_count;wire[2:0]recovery_state;
 reg epoch_fault;
 board_recovery_reset #(.HOLD_CYCLES(RECOVERY_HOLD),.LOCK_TIMEOUT(RECOVERY_TIMEOUT),.SETTLE_CYCLES(RECOVERY_SETTLE)) recovery(.cfg_clk(cfg_clk),.external_rst_n(clocks_ready),.fault_request_async(epoch_fault),.ddr_ready_async(ddr_ready),
 .memory_release_n(memory_release_n),.recovering(recovering),.exhausted(retry_exhausted),.recovery_count(recovery_count),.state(recovery_state));''')
s=rep(s,'reg [2:0] ready_sync,nearest_sync,pattern_sync;', 'reg [2:0] ready_sync,nearest_sync,raw_sync,recovery_sync;')
s=rep(s,'ready_sync<=0;nearest_sync<=0;', 'ready_sync<=0;nearest_sync<=0;raw_sync<=7;recovery_sync<=7;')
s=rep(s,'nearest_sync<={nearest_sync[1:0],!key2_nearest_n};', 'nearest_sync<={nearest_sync[1:0],!key2_nearest_n};raw_sync<={raw_sync[1:0],key1_pattern_n};recovery_sync<={recovery_sync[1:0],recovering};')
a=s.index(' always @(posedge pix_clk or negedge pix_rst)begin\n  if(!pix_rst)pattern_sync')
b=s.index(' reg rx_vs_q',a);s=s[:a]+s[b:]
a=s.index(' reg[4:0]memory_detail;');b=s.index(' video_correct_ddr_continuous_core #(',a)
diag=''' wire display_raw,debug_display_bank;wire[31:0]raw_count,corr_count,dropped_count,debug_frame_id,debug_display_id;
 wire[359:0]debug_h;wire[95:0]debug_corners;wire[27:0]debug_source_base,debug_result_base;wire[10:0]fifo_peak;
 wire[3:0]source_faults,service_stage;
 wire[31:0]max_aw,max_first_w,max_w_gap,max_first_r,max_r_gap,max_cmd_wait;
 wire current_fault;wire[4:0]current_mask,first_mask;wire[2:0]current_kind,first_kind;
 wire[3:0]current_raw,current_source,first_raw,first_source,first_stage,first_engine_raw;wire first_valid;wire[47:0]first_tick;
 wire source_first_valid;wire[3:0]source_first_fault;wire[47:0]source_first_proc_tick,source_first_received_ui_tick;
 (* ASYNC_REG="TRUE" *)reg[2:0]source_protection_sync;
 always @(posedge ui_clk or negedge ui_rst)begin
 if(!ui_rst)source_protection_sync<=0;else source_protection_sync<={source_protection_sync[1:0],|source_faults};end
 // Reset diagnostic history only with manual reset/PLL loss. Application and
 // native engine reset together on recovery; a one-cycle ALIGN is latched.
 always @(posedge ui_clk or negedge ui_rst)begin
 if(!ui_rst)epoch_fault<=0;
 else if(ddr_ready&&(engine_fault||phy_fail||align_error||self_fail||source_protection_sync[2]))epoch_fault<=1;
 end
 native_service_monitor service(.clk(ui_clk),.rst_n(ui_rst),.cmd_valid(cmd_v),.cmd_ready(cmd_r),
 .awvalid(awvalid),.awready(awready),.wready(wready),.wlast(wlast),.arvalid(arvalid),.arready(arready),.rvalid(rvalid),.rlast(rlast),
 .max_aw(max_aw),.max_first_w(max_first_w),.max_w_gap(max_w_gap),.max_first_r(max_first_r),.max_r_gap(max_r_gap),.max_cmd_wait(max_cmd_wait),.stage(service_stage));
 @DIAGNOSTICS@
 wire[399:0]ui_diagnostics;wire[399:0]proc_diagnostics;
 assign ui_diagnostics[0+:80]={34'd0,first_engine_raw,current_source,current_raw,current_kind,current_mask,first_source,first_raw,first_kind,first_mask,engine_reason,service_stage,first_valid,epoch_fault};
 assign ui_diagnostics[80+:80]={16'd0,max_aw,max_first_w};
 assign ui_diagnostics[160+:80]={16'd0,max_w_gap,max_first_r};
 assign ui_diagnostics[240+:80]={16'd0,max_r_gap,max_cmd_wait};
 assign ui_diagnostics[320+:80]={23'd0,first_tick,first_stage,first_mask};
 snapshot_cdc #(.WIDTH(400)) diagnostics_crossing(.s_clk(ui_clk),.d_clk(proc_clk57),.rst_n(clocks_ready),.s_data(ui_diagnostics),.d_data(proc_diagnostics),.d_valid());
 reg first_service_valid;reg[191:0]first_service;
 always @(posedge ui_clk or negedge clocks_ready)begin
 if(!clocks_ready)begin first_service_valid<=0;first_service<=0;end
 else if(!first_service_valid&&(engine_fault||phy_fail||align_error||self_fail||(|current_source)))begin
 first_service_valid<=1;first_service<={max_aw,max_first_w,max_w_gap,max_first_r,max_r_gap,max_cmd_wait};end end
 wire[191:0]proc_first_service;
 snapshot_cdc #(.WIDTH(192)) first_service_crossing(.s_clk(ui_clk),.d_clk(proc_clk57),.rst_n(clocks_ready),.s_data(first_service),.d_data(proc_first_service),.d_valid());
 // Physical input count is independent of admission and survives DDR retry.
 wire physical_vs;hdmi_vs_recover physical_vsync(.clk(hd_rx_pclk),.reset_n(clocks_ready),.de(hd_rx_de),.hs(hd_rx_hs),.vs_in(hd_rx_vs),.vs_out(physical_vs));
 reg input_vs_d;reg[31:0]physical_input,physical_gray;
 always @(posedge hd_rx_pclk or negedge clocks_ready)begin
 if(!clocks_ready)begin input_vs_d<=0;physical_input<=0;physical_gray<=0;end
 else begin input_vs_d<=physical_vs;if(physical_vs&&!input_vs_d)physical_input<=physical_input+1'b1;physical_gray<=(physical_input>>1)^physical_input;end end
 (* ASYNC_REG="TRUE" *)reg[31:0]input_q0,input_q1,input_q2;
 always @(posedge proc_clk57 or negedge clocks_ready)begin
 if(!clocks_ready)begin input_q0<=0;input_q1<=0;input_q2<=0;end
 else begin input_q0<=physical_gray;input_q1<=input_q0;input_q2<=input_q1;end end
 wire[31:0]input_count;
 genvar n;generate for(n=0;n<32;n=n+1)begin: input_decode assign input_count[n]=^(input_q2>>n);end endgenerate
 wire[10:0]recovery_record;wire[10:0]proc_recovery;
 assign recovery_record={recovery_count,recovery_state};
 snapshot_cdc #(.WIDTH(11)) recovery_crossing(.s_clk(cfg_clk),.d_clk(proc_clk57),.rst_n(clocks_ready),.s_data(recovery_record),.d_data(proc_recovery),.d_valid());
 reg first_fifo_valid;reg[10:0]first_fifo_peak;
 always @(posedge proc_clk57 or negedge clocks_ready)begin
 if(!clocks_ready)begin first_fifo_valid<=0;first_fifo_peak<=0;end
 else if(!first_fifo_valid&&diagnostic_reason==7)begin first_fifo_valid<=1;first_fifo_peak<=fifo_peak;end end
 wire[1919:0]trace_data;wire[79:0]actual_pix_metadata;
 assign trace_data[0+:80]=0;
 assign trace_data[80+:80]={16'd0,input_count,admitted_count};
 assign trace_data[160+:80]={16'd0,dropped_count,rejected_count};
 assign trace_data[240+:80]={16'd0,raw_count,corr_count};
 assign trace_data[320+:80]={16'd0,displayed_id,display_age};
 assign trace_data[400+:80]={26'd0,fifo_peak,debug_frame_id,proc_recovery};
 assign trace_data[480+:80]={32'd0,debug_corners[95:48]};
 assign trace_data[560+:80]={32'd0,debug_corners[47:0]};
 assign trace_data[640+:80]={debug_h[0+:40],debug_h[40+:40]};
 assign trace_data[720+:80]={debug_h[80+:40],debug_h[120+:40]};
 assign trace_data[800+:80]={debug_h[160+:40],debug_h[200+:40]};
 assign trace_data[880+:80]={debug_h[240+:40],debug_h[280+:40]};
 assign trace_data[960+:80]={12'd0,debug_result_base,debug_h[320+:40]};
 assign trace_data[1040+:400]=proc_diagnostics;
 assign trace_data[1440+:80]={52'd0,debug_source_base};
 assign trace_data[1520+:80]={16'd0,proc_first_service[191:128]};
 assign trace_data[1600+:80]={16'd0,proc_first_service[127:64]};
 assign trace_data[1680+:80]={16'd0,proc_first_service[63:0]};
 wire[100:0]source_history={source_first_valid,source_first_fault,source_first_proc_tick,source_first_received_ui_tick};
 wire[100:0]proc_source_history;
 snapshot_cdc #(.WIDTH(101)) source_history_crossing(.s_clk(ui_clk),.d_clk(proc_clk57),.rst_n(clocks_ready),.s_data(source_history),.d_data(proc_source_history),.d_valid());
 assign trace_data[1760+:80]={15'd0,first_fifo_valid,first_fifo_peak,proc_source_history[100],proc_source_history[96+:4],proc_source_history[48+:48]};
 assign trace_data[1840+:80]={32'd0,proc_source_history[0+:48]};
 wire[27:0]actual_display_base=display_raw?(debug_display_bank?28'h0800000:28'd0):(debug_display_bank?28'h0400000:28'h0200000);
 assign actual_pix_metadata={17'd0,debug_display_id,actual_display_base,display_raw,debug_display_bank,image_valid};
 debug_hex_overlay trace_view(.proc_clk(proc_clk57),.pix_clk(pix_clk),.rst_n(clocks_ready),.scan_de(scan_de),.x(scan_x),.y(scan_y),
 .data(trace_data),.pix_metadata(actual_pix_metadata),.on(telemetry_on),.rgb(telemetry_rgb));
 wire[4:0]pix_status,pix_status_code;
 wire[2:0]proc_current_kind=proc_diagnostics[31+:3];wire[3:0]proc_current_raw=proc_diagnostics[34+:4];
 wire[4:0]proc_status=proc_recovery[2:0]==4?5'd29:proc_recovery[2:0]!=1?5'd15:
 (|proc_diagnostics[26+:5])?(proc_current_kind==1?5'd28:proc_current_kind==2?5'd16+{1'b0,proc_current_raw}:proc_current_kind==3?5'd25:proc_current_kind==4?5'd26:5'd27):
 input_wait?5'd1:displayed_id!=0?(display_age>100?5'd13:5'd9):5'd0;
 snapshot_cdc #(.WIDTH(5)) status_crossing(.s_clk(proc_clk57),.d_clk(pix_clk),.rst_n(clocks_ready),.s_data(proc_status),.d_data(pix_status_code),.d_valid());
 assign pix_status=(pix_status_code==9&&display_raw)?5'd12:pix_status_code;
 status_overlay status_view(.clk(pix_clk),.rst_n(scan_reset_n),.scan_de(scan_de),.scan_start(scan_start),.x(scan_x),.y(scan_y),.status(pix_status),.on(status_on),.rgb(status_rgb));
 assign overlay_on=status_on||telemetry_on;
 assign overlay_rgb=status_on?status_rgb:telemetry_rgb;
 assign preview_valid=1'b0;assign preview_rgb=24'd0;
'''
outputs='current_fault_any current_mask current_kind current_raw_reason current_engine_reason current_source_fault current_ui_tick current_source_proc_tick current_source_received_ui_tick current_ui_stage current_dqs_valid source_snapshot_valid first_valid first_mask first_kind first_raw_reason first_engine_reason first_source_fault first_ui_tick first_source_proc_tick first_ui_stage first_dqs_valid source_first_valid source_first_fault source_first_proc_tick source_first_received_ui_tick'.split()
mapping=dict(proc_clk='proc_clk57',ui_clk='ui_clk',rst_n='clocks_ready',ui_engine_fault='engine_fault',ui_engine_reason='engine_reason',ui_phy_fail='phy_fail',ui_align_error='align_error',ui_self_fail='self_fail',ui_stage='service_stage',ui_dqs_valid="4'd0",proc_source_fault='source_faults')
mapping.update({k:'' for k in outputs})
mapping.update(current_fault_any='current_fault',current_mask='current_mask',current_kind='current_kind',current_raw_reason='current_raw',current_source_fault='current_source',first_valid='first_valid',first_mask='first_mask',first_kind='first_kind',first_raw_reason='first_raw',first_engine_reason='first_engine_raw',first_source_fault='first_source',first_ui_tick='first_tick',first_ui_stage='first_stage',source_first_valid='source_first_valid',source_first_fault='source_first_fault',source_first_proc_tick='source_first_proc_tick',source_first_received_ui_tick='source_first_received_ui_tick')
instance='fault_diagnostics_stream diagnostics('+','.join(f'.{k}({v})' for k,v in mapping.items())+');'
diag=diag.replace('@DIAGNOSTICS@',instance)
s=s[:a]+diag+s[b:]
s=rep(s,'.hdmi_ready(ready_sync[2]),', '.hdmi_ready(ready_sync[2]&&!recovery_sync[2]),')
s=rep(s,'.memory_fault(engine_fault||phy_fail||align_error)', '.memory_fault(engine_fault||phy_fail||align_error||epoch_fault)')
s=rep(s,'.force_pattern(pattern_sync[2]),', '''.force_pattern(1'b0),.raw_requested(raw_sync[2]),.display_raw(display_raw),.raw_publications(raw_count),.corrected_publications(corr_count),
 .source_fault_components(source_faults),.data_fifo_peak(fifo_peak),.debug_h(debug_h),.debug_corners(debug_corners),.debug_frame_id(debug_frame_id),
 .debug_source_base(debug_source_base),.debug_result_base(debug_result_base),.debug_display_bank(debug_display_bank),.debug_display_id(debug_display_id),''')
s=rep(s,'.dropped_frames(),', '.dropped_frames(dropped_count),')
# Early wire declarations avoid tool-specific forward procedural references.
a=s.index(' wire [27:0] awaddr,araddr;');b=s.index(' ddr_word_engine_result_burst #',a)
native_declarations=s[a:b];s=s[:a]+s[b:]
s=rep(s,' wire cmd_v,cmd_r,cmd_w,',native_declarations+' wire cmd_v,cmd_r,cmd_w,')
s=rep(s,'wire current_fault;','wire current_fault;')
s=rep(s,' wire ddr_lock,ddr_ready,phy_fail,align_error;','')
s=rep(s,' wire memory_release_n,', ' wire ddr_lock,ddr_ready,phy_fail,align_error;\n wire memory_release_n,')
(O/'video_correct_ddr_top.v').write_text(s)

# Add truthful RAW/HELD/recovery/source labels to the existing ROM; old error
# codes remain distinct. FIRST history is rendered in hex rows, never selected
# as the current fault label.
s=(F/'rtl/video/status_overlay.v').read_text()
font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',12)
rows=[]
status_labels={12:'RAW 1920X1080',13:'HELD LAST FRAME',15:'RECOVERING DDR',28:'SOURCE FAULT',29:'RETRY LIMIT'}
# Verilog case selects the first matching item. Remove replaced addresses
# before installing labels; appending duplicate items retains the old glyphs.
s=re.sub(r"^9'h([0-9a-f]+): bits=160'h[0-9a-f]+;\s*$",
         lambda m:'' if int(m[1],16)//16 in status_labels else m[0],s,flags=re.M)
for code,label in status_labels.items():
 im=Image.new('1',(160,16));ImageDraw.Draw(im).text((0,0),label,font=font,fill=1)
 for y in range(16):
  bits=0
  for x in range(160):bits=(bits<<1)|int(im.getpixel((x,y))!=0)
  rows.append(f"9'h{code*16+y:03x}: bits=160'h{bits:040x};")
s=rep(s,' default:bits=0;', '\n'.join(rows)+'\n default:bits=0;')
rom_addresses=re.findall(r"9'h([0-9a-f]+): bits=",s)
assert len(rom_addresses)==len(set(rom_addresses)),'Duplicate status ROM addresses'
(O/'status_overlay.v').write_text(s)

sources=json.loads((H/'integration/sources.json').read_text())
sub={Path(p).name:p for p in sources}
sub['continuous_capture_manager.v']=(H/'control/manager_raw.v').as_posix()
sub.update({'video_correct_ddr_top.v':(O/'video_correct_ddr_top.v').as_posix(),'status_overlay.v':(O/'status_overlay.v').as_posix()})
tcl=(F/'diagnostics/ddr_camera_hires_prefetch_20261012/results/build.tcl').read_text()
designs=[]
for name in re.findall(r'add_design\s+\{([^}]+)\}',tcl):
 p=Path(name)
 if p.name in ['ddr_result_display.v','ddr_result_display_block64.v']:continue
 designs.append(sub.get(p.name,p.as_posix()))
for p in sources+[str(H/'diagnostics'/n).replace('\\','/') for n in ['fault_diagnostics_stream.v','snapshot_cdc.v','native_service_monitor.v','debug_hex_overlay.v']]+[(H/'control/board_recovery_reset.v').as_posix()]:
 if p not in designs:designs.append(p)
modules={}
for p in designs:
 if Path(p).suffix!='.v':continue
 for name in re.findall(r'^\s*module\s+(\w+)',Path(p).read_text(encoding='utf-8',errors='replace'),re.M):
  assert name not in modules,('duplicate module',name,p,modules.get(name))
  modules[name]=p
constraints=re.findall(r'add_constraint[^\n{]*\{([^}]+)\}',tcl)
assert constraints
script='set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676\n'
script+=''.join('add_design {'+p+'}\n' for p in designs)
script+=''.join('add_constraint {'+p+'}\n' for p in constraints)
script+='compile -top_module video_correct_ddr_top\nsynthesize -ads\ndev_map\npnr -gplace_seed 17 -groute_seed 17 -optimize_multi_corner_timing -slack_prior_in_global_router TRUE\nreport_timing\ngen_bit_stream\n'
(O/'build.tcl').write_text(script)
manifest={'hardware_accepted':False,'timing_qualified':False,'designs':{p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in designs},'constraints':{p:hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in constraints}}
(O/'source_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('Prepared isolated board sources:',len(designs),'files; qualification pending')
