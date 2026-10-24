`timescale 1ns/1ps
`default_nettype none
// C: full 1920x1080 source; portrait result retains 640:904 aspect.
// PG2L100H / MES2L676-100HP board integration with external x32 DDR3.
module video_correct_ddr_top #(
 parameter SOURCE_W=1920,SOURCE_H=1080,RESULT_W=1920,RESULT_H=1080,
 parameter HS=44,HB=148,HF=88,VS=5,VB=36,VF=4,BIST_BEATS=256,
 parameter HDMI_HOLD=10000,RECOVERY_HOLD=100000,RECOVERY_TIMEOUT=5000000,RECOVERY_SETTLE=1000000,
 parameter DIAGNOSTIC_HOLD_CYCLES=500000,PRESENTATION_STALE_FRAMES=30
)(
 input wire sys_clk_27m,rst_n,key1_pattern_n,key2_nearest_n,
 input wire ddr_ref_clk_p,ddr_ref_clk_n,
 input wire hd_rx_pclk,hd_rx_vs,hd_rx_hs,hd_rx_de,
 input wire [23:0] hd_rx_data,
 output wire hd_tx_pclk,output reg hd_tx_vs,hd_tx_hs,hd_tx_de,
 output reg [23:0] hd_tx_data,
 output wire hd_reset_n,hd_scl,inout wire hd_sda,
 output wire [7:0] led,
 output wire mem_cs_n,mem_rst_n,mem_ck,mem_ck_n,mem_cke,mem_ras_n,mem_cas_n,mem_we_n,mem_odt,
 output wire [14:0] mem_a,output wire [2:0] mem_ba,
 inout wire [3:0] mem_dqs,mem_dqs_n,inout wire [31:0] mem_dq,output wire [3:0] mem_dm
);
 wire pix_clk,cfg_clk,pix_lock,cfg_lock,ref_clk,ui_clk;
 wire proc_clk57;
 video_pll_27m_148m5 vp(.clkout57(proc_clk57),.clkin1(sys_clk_27m),.clkout0(pix_clk),.lock(pix_lock));
 config_pll_27m_10m cp(.clkin1(sys_clk_27m),.clkout0(cfg_clk),.lock(cfg_lock));
 GTP_INBUFDS ref_input(.I(ddr_ref_clk_p),.IB(ddr_ref_clk_n),.O(ref_clk));
 wire clocks_ready=rst_n&&pix_lock&&cfg_lock;
 wire cfg_rst,mem_reset,proc_rst,rx_rst,pix_rst,ui_rst;
 wire ddr_lock,ddr_ready,phy_fail,align_error;
 wire memory_release_n,recovering,retry_exhausted;wire[7:0]recovery_count;wire[2:0]recovery_state;
 reg epoch_fault;
 board_recovery_reset #(.HOLD_CYCLES(RECOVERY_HOLD),.LOCK_TIMEOUT(RECOVERY_TIMEOUT),.SETTLE_CYCLES(RECOVERY_SETTLE)) recovery(.cfg_clk(cfg_clk),.external_rst_n(clocks_ready),.fault_request_async(epoch_fault),.ddr_ready_async(ddr_ready),
 .memory_release_n(memory_release_n),.recovering(recovering),.exhausted(retry_exhausted),.recovery_count(recovery_count),.state(recovery_state));
 reset_sync cfg_reset(.clk(cfg_clk),.arst_n(clocks_ready),.rst_n(cfg_rst));
 reset_sync ddr_reset(.clk(ref_clk),.arst_n(clocks_ready&&memory_release_n),.rst_n(mem_reset));
 reg [15:0] hd_count;
 always @(posedge cfg_clk or negedge cfg_rst)begin
  if(!cfg_rst)hd_count<=0;else if(hd_count<HDMI_HOLD)hd_count<=hd_count+1'b1;
 end
 assign hd_reset_n=cfg_rst&&hd_count==HDMI_HOLD;

 wire app_reset_async=hd_reset_n&&mem_reset&&ddr_lock;
 reset_sync process_reset(.clk(proc_clk57),.arst_n(app_reset_async),.rst_n(proc_rst));
 reset_sync receive_reset(.clk(hd_rx_pclk),.arst_n(app_reset_async),.rst_n(rx_rst));
 reset_sync display_reset(.clk(pix_clk),.arst_n(app_reset_async),.rst_n(pix_rst));
 reset_sync ui_reset(.clk(ui_clk),.arst_n(app_reset_async),.rst_n(ui_rst));
 wire rx_done,tx_done,ack_error,config_error,startup_retry_seen;
 hdmi_config #(.TX_FIRST(1'b1)) config_bus(.cfg_clk(cfg_clk),.reset_n(hd_reset_n),.rx_done(rx_done),.tx_done(tx_done),
  .scl(hd_scl),.sda(hd_sda),.ack_error(ack_error),.config_error(config_error),
  .startup_retry_seen(startup_retry_seen));
 (* ASYNC_REG="TRUE" *) reg [2:0] ready_sync,nearest_sync,raw_sync,recovery_sync;
 always @(posedge proc_clk57 or negedge proc_rst)begin
  if(!proc_rst)begin ready_sync<=0;nearest_sync<=0;raw_sync<=0;recovery_sync<=7;end
  else begin ready_sync<={ready_sync[1:0],rx_done&&tx_done&&!config_error};nearest_sync<={nearest_sync[1:0],!key2_nearest_n};raw_sync<={raw_sync[1:0],!key1_pattern_n};recovery_sync<={recovery_sync[1:0],recovering};end
 end
 // External data is captured on the stable falling edge. Retiming all four
 // signals together on the next rising edge preserves a full internal cycle.
 reg rx_vs_f,rx_hs_f,rx_de_f;reg [23:0] rx_rgb_f;
 always @(negedge hd_rx_pclk or negedge rx_rst)begin
  if(!rx_rst)begin rx_vs_f<=0;rx_hs_f<=0;rx_de_f<=0;rx_rgb_f<=0;end
  else begin rx_vs_f<=hd_rx_vs;rx_hs_f<=hd_rx_hs;rx_de_f<=hd_rx_de;rx_rgb_f<=hd_rx_data;end
 end
 reg rx_vs_q,rx_hs_q,rx_de_q;reg [23:0] rx_rgb_q;
 always @(posedge hd_rx_pclk or negedge rx_rst)begin
  if(!rx_rst)begin rx_vs_q<=0;rx_hs_q<=0;rx_de_q<=0;rx_rgb_q<=0;end
  else begin rx_vs_q<=rx_vs_f;rx_hs_q<=rx_hs_f;rx_de_q<=rx_de_f;rx_rgb_q<=rx_rgb_f;end
 end
 wire recovered_vs;
 hdmi_vs_recover vs_recover(.clk(hd_rx_pclk),.reset_n(rx_rst),.de(rx_de_q),.hs(rx_hs_q),.vs_in(rx_vs_q),.vs_out(recovered_vs));
 wire [27:0] awaddr,araddr;wire awvalid,arvalid,awready,arready,wready,rvalid,rlast,wlast;
 wire [3:0] awid,arid,awlen,arlen,rid,wid;wire awap,arap;
 wire [255:0] wdata,rdata;wire [31:0] wstrb;
 wire cmd_v,cmd_r,cmd_w,rsp_v,rsp_w,engine_fault,source_block,result_block;wire[2047:0]full_result_block;wire[2047:0]full_source_block;
 wire[2047:0]capture_burst_data;wire [27:0] cmd_a;wire [255:0] cmd_data,rsp_data;wire [31:0] cmd_mask;
 wire hs,vs,den,image_valid,working,frame_error,input_wait,underrun,self_pass,self_fail;
 wire[23:0]rgb,preview_rgb,overlay_rgb,status_rgb,telemetry_rgb;
 wire status_on,telemetry_on;
 wire[31:0]displayed_id,display_age,admitted_count,published_count,rejected_count;wire[511:0]reject_counts;
 wire[11:0]scan_x,scan_y;wire scan_de,scan_start,scan_reset_n,preview_valid,overlay_on;
 wire[3:0]diagnostic_reason,diagnostic_phase,engine_reason;
 wire display_raw,debug_display_bank;wire[31:0]raw_count,corr_count,dropped_count,debug_frame_id,debug_display_id;
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
 fault_diagnostics_stream diagnostics(.proc_clk(proc_clk57),.ui_clk(ui_clk),.rst_n(clocks_ready),.ui_engine_fault(engine_fault),.ui_engine_reason(engine_reason),.ui_phy_fail(phy_fail),.ui_align_error(align_error),.ui_self_fail(self_fail),.ui_stage(service_stage),.ui_dqs_valid(4'd0),.proc_source_fault(source_faults),.current_fault_any(current_fault),.current_mask(current_mask),.current_kind(current_kind),.current_raw_reason(current_raw),.current_engine_reason(),.current_source_fault(current_source),.current_ui_tick(),.current_source_proc_tick(),.current_source_received_ui_tick(),.current_ui_stage(),.current_dqs_valid(),.source_snapshot_valid(),.first_valid(first_valid),.first_mask(first_mask),.first_kind(first_kind),.first_raw_reason(first_raw),.first_engine_reason(first_engine_raw),.first_source_fault(first_source),.first_ui_tick(first_tick),.first_source_proc_tick(),.first_ui_stage(first_stage),.first_dqs_valid(),.source_first_valid(source_first_valid),.source_first_fault(source_first_fault),.source_first_proc_tick(source_first_proc_tick),.source_first_received_ui_tick(source_first_received_ui_tick));
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
 // The independent physical counter must use the same stable input edge.
 // Its reset remains independent of DDR/application retries.
 reg physical_vs_f,physical_hs_f,physical_de_f;
 always @(negedge hd_rx_pclk or negedge clocks_ready)begin
  if(!clocks_ready)begin physical_vs_f<=0;physical_hs_f<=0;physical_de_f<=0;end
  else begin physical_vs_f<=hd_rx_vs;physical_hs_f<=hd_rx_hs;physical_de_f<=hd_rx_de;end
 end
 reg physical_vs_q,physical_hs_q,physical_de_q;
 always @(posedge hd_rx_pclk or negedge clocks_ready)begin
  if(!clocks_ready)begin physical_vs_q<=0;physical_hs_q<=0;physical_de_q<=0;end
  else begin physical_vs_q<=physical_vs_f;physical_hs_q<=physical_hs_f;physical_de_q<=physical_de_f;end
 end
 wire physical_vs;hdmi_vs_recover physical_vsync(.clk(hd_rx_pclk),.reset_n(clocks_ready),.de(physical_de_q),.hs(physical_hs_q),.vs_in(physical_vs_q),.vs_out(physical_vs));
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
 // Read-only diagnosis; no protection, memory command or timing outputs.
 reg[31:0]diag_scan_count;
 always @(posedge pix_clk or negedge clocks_ready)
 if(!clocks_ready)diag_scan_count<=0;else if(scan_reset_n&&scan_start)diag_scan_count<=diag_scan_count+1'b1;
 wire[31:0]proc_scan_count;
 snapshot_cdc #(.WIDTH(32)) scan_observer(.s_clk(pix_clk),.d_clk(proc_clk57),.rst_n(clocks_ready),.s_data(diag_scan_count),.d_data(proc_scan_count),.d_valid());
 (* ASYNC_REG="TRUE" *)reg[2:0]underrun_proc;
 always @(posedge proc_clk57 or negedge clocks_ready)
 if(!clocks_ready)underrun_proc<=0;else underrun_proc<={underrun_proc[1:0],underrun};
 reg[31:0]diag_write_commands,diag_read_commands,diag_write_wait,diag_read_wait;
 always @(posedge ui_clk or negedge ui_rst)begin
 if(!ui_rst)begin diag_write_commands<=0;diag_read_commands<=0;diag_write_wait<=0;diag_read_wait<=0;end
 else begin
 if(awvalid&&awready)diag_write_commands<=diag_write_commands+1'b1;
 if(arvalid&&arready)diag_read_commands<=diag_read_commands+1'b1;
 if((service_stage==1||service_stage==2)&&!wready)diag_write_wait<=diag_write_wait+1'b1;
 if((service_stage==3||service_stage==4)&&!rvalid)diag_read_wait<=diag_read_wait+1'b1;
 end end
 wire[127:0]ui_service_totals={diag_write_commands,diag_read_commands,diag_write_wait,diag_read_wait};
 wire[127:0]proc_service_totals;
 snapshot_cdc #(.WIDTH(128)) service_totals_observer(.s_clk(ui_clk),.d_clk(proc_clk57),.rst_n(clocks_ready),.s_data(ui_service_totals),.d_data(proc_service_totals),.d_valid());
 wire[1919:0]trace_data;wire[79:0]actual_pix_metadata;
 assign trace_data[0+:80]=0;
 assign trace_data[80+:80]={16'd0,input_count,admitted_count};
 assign trace_data[160+:80]={16'd0,dropped_count,rejected_count};
 assign trace_data[240+:80]={16'd0,raw_count,corr_count};
 assign trace_data[320+:80]={16'd0,displayed_id,display_age};
 assign trace_data[400+:80]={26'd0,fifo_peak,debug_frame_id,proc_recovery};
 assign trace_data[480+:80]={16'd0,reject_counts[12*32+:32],reject_counts[13*32+:32]};
 assign trace_data[560+:80]={16'd0,reject_counts[14*32+:32],reject_counts[15*32+:32]};
 assign trace_data[640+:80]={debug_h[0+:40],debug_h[40+:40]};
 assign trace_data[720+:80]={debug_h[80+:40],debug_h[120+:40]};
 assign trace_data[800+:80]={debug_h[160+:40],debug_h[200+:40]};
 assign trace_data[880+:80]={debug_h[240+:40],debug_h[280+:40]};
 assign trace_data[960+:80]={12'd0,debug_result_base,debug_h[320+:40]};
 assign trace_data[1040+:400]=proc_diagnostics;
 assign trace_data[1440+:80]={16'd0,proc_service_totals[127:64]};
 assign trace_data[1520+:80]={16'd0,proc_service_totals[63:0]};
 assign trace_data[1600+:80]={16'd0,proc_first_service[127:64]};
 assign trace_data[1680+:80]={16'd0,proc_first_service[63:0]};
 wire[100:0]source_history={source_first_valid,source_first_fault,source_first_proc_tick,source_first_received_ui_tick};
 wire[100:0]proc_source_history;
 snapshot_cdc #(.WIDTH(101)) source_history_crossing(.s_clk(ui_clk),.d_clk(proc_clk57),.rst_n(clocks_ready),.s_data(source_history),.d_data(proc_source_history),.d_valid());
 assign trace_data[1760+:80]={underrun_proc[2],14'd0,first_fifo_valid,first_fifo_peak,proc_source_history[100],proc_source_history[96+:4],proc_source_history[48+:48]};
 assign trace_data[1840+:80]={proc_scan_count,proc_source_history[0+:48]};
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
 wire[4:0]presentation_status;
 status_overlay status_view(.clk(pix_clk),.rst_n(scan_reset_n),.scan_de(scan_de),.scan_start(scan_start),.x(scan_x),.y(scan_y),.status(presentation_status),.on(status_on),.rgb(status_rgb));
 // BEGIN_PRESENTATION_POLICY
 // The key chord changes only the view, never the numerical algorithm.
 // Existing KEY1 RAW / KEY2 nearest behavior remains in effect while held.
 localparam DIAG_WIDTH=DIAGNOSTIC_HOLD_CYCLES<2?1:$clog2(DIAGNOSTIC_HOLD_CYCLES+1);
 (* ASYNC_REG="TRUE" *)reg[2:0]diagnostic_key_sync;
 reg[DIAG_WIDTH-1:0]diagnostic_hold;
 reg diagnostic_pressed,diagnostic_requested;
 always @(posedge cfg_clk or negedge cfg_rst)begin
  if(!cfg_rst)begin diagnostic_key_sync<=0;diagnostic_hold<=0;diagnostic_pressed<=0;diagnostic_requested<=0;end
  else begin
   diagnostic_key_sync<={diagnostic_key_sync[1:0],!key1_pattern_n&&!key2_nearest_n};
   if(!diagnostic_key_sync[2])begin diagnostic_hold<=0;diagnostic_pressed<=0;end
   else if(!diagnostic_pressed)begin
    if(diagnostic_hold==DIAGNOSTIC_HOLD_CYCLES-1)begin diagnostic_requested<=!diagnostic_requested;diagnostic_pressed<=1;end
    else diagnostic_hold<=diagnostic_hold+1'b1;
   end
  end
 end
 (* ASYNC_REG="TRUE" *)reg[2:0]diagnostic_pix_sync;
 localparam STALE_WIDTH=PRESENTATION_STALE_FRAMES<2?1:$clog2(PRESENTATION_STALE_FRAMES+1);
 reg[STALE_WIDTH-1:0]presentation_same_scans;
 reg[31:0]presentation_last_id;
 wire presentation_stale=image_valid&&debug_display_id==presentation_last_id&&presentation_same_scans>=PRESENTATION_STALE_FRAMES-1;
 assign presentation_status=presentation_stale&&(pix_status==5'd9||pix_status==5'd12||pix_status==5'd13)?5'd13:pix_status;
 reg diagnostic_shown,warning_shown;
 always @(posedge pix_clk or negedge pix_rst)begin
  if(!pix_rst)begin diagnostic_pix_sync<=0;diagnostic_shown<=0;warning_shown<=1;presentation_same_scans<=0;presentation_last_id<=0;end
  else begin
   diagnostic_pix_sync<={diagnostic_pix_sync[1:0],diagnostic_requested};
   if(scan_start)begin
    diagnostic_shown<=diagnostic_pix_sync[2];
    presentation_last_id<=debug_display_id;
    if(!image_valid||debug_display_id!=presentation_last_id)presentation_same_scans<=0;
    else if(presentation_same_scans<PRESENTATION_STALE_FRAMES)presentation_same_scans<=presentation_same_scans+1'b1;
    warning_shown<=!image_valid||presentation_stale||(pix_status!=5'd9&&pix_status!=5'd12&&pix_status!=5'd13);
   end
  end
 end
 assign overlay_on=status_on||telemetry_on;
 assign overlay_rgb=status_on?status_rgb:telemetry_rgb;
 // END_PRESENTATION_POLICY
 assign preview_valid=1'b0;assign preview_rgb=24'd0;
 video_correct_ddr_continuous_core #(.BIST_ONLY_NATIVE_WDATA(1),.PROC_CYCLES_PER_MS(57115),.CAPTURE_TIMEOUT(114230000),.RETRY_CYCLES(571150),.CAPTURE_BURST_BEATS(8),.IN_W(SOURCE_W),.IN_H(SOURCE_H),.SRC_W(SOURCE_W),.SRC_H(SOURCE_H),.BIST_BEATS(BIST_BEATS),.H_SYNC(HS),.H_BACK(HB),.H_ACTIVE(SOURCE_W),.H_FRONT(HF),.V_SYNC(VS),.V_BACK(VB),.V_ACTIVE(SOURCE_H),.V_FRONT(VF),.OVERLAP_CAPTURE(1),.LATE_CAPTURE_PERCENT(0),.ADAPTIVE_DISPLAY_GUARD(1),.INLINE_GEOMETRY(1),.BLACK_RMIN(0),.BLACK_RMAX(64),.BLACK_GMIN(0),.BLACK_GMAX(64),.BLACK_BMIN(0),.BLACK_BMAX(64),.P0_XMIN(580),.P0_XMAX(681),.P0_YMIN(86),.P0_YMAX(187),.P1_XMIN(1410),.P1_XMAX(1511),.P1_YMIN(174),.P1_YMAX(275),.P2_XMIN(1480),.P2_XMAX(1581),.P2_YMIN(920),.P2_YMAX(1021),.P3_XMIN(226),.P3_XMAX(327),.P3_YMIN(886),.P3_YMAX(987),.SOURCE_BASE1(28'h0800000),.OUT_W(RESULT_W),.OUT_H(RESULT_H),.SCALE(1),.FIFO_ADDR_BITS(10),
  .MARKER_MIN_PIXELS(64),.MARKER_MAX_PIXELS(16384),.MARKER_MAX_SPAN(256),
  .RESULT_BASE0(28'h0200000),.RESULT_BASE1(28'h0400000),.BIST_BASE(28'h0600000)) core(.proc_clk(proc_clk57),.proc_rst_n(proc_rst),.rx_clk(hd_rx_pclk),.rx_rst_n(rx_rst),
  .pix_clk(pix_clk),.pix_rst_n(pix_rst),.ui_clk(ui_clk),.ui_rst_n(ui_rst),
  .hdmi_ready(ready_sync[2]&&!recovery_sync[2]),.ddr_ready(ddr_ready),.memory_fault(engine_fault||phy_fail||align_error||epoch_fault),
  .rx_vs(recovered_vs),.rx_de(rx_de_q),.rx_rgb(rx_rgb_q),.nearest(nearest_sync[2]),.force_pattern(1'b0),.raw_requested(raw_sync[2]),.display_raw(display_raw),.raw_publications(raw_count),.corrected_publications(corr_count),
 .source_fault_components(source_faults),.data_fifo_peak(fifo_peak),.debug_h(debug_h),.debug_corners(debug_corners),.debug_frame_id(debug_frame_id),
 .debug_source_base(debug_source_base),.debug_result_base(debug_result_base),.debug_display_bank(debug_display_bank),.debug_display_id(debug_display_id),
  .hsync(hs),.vsync(vs),.de(den),.rgb(rgb),.image_valid(image_valid),.working(working),.frame_error(frame_error),.input_wait(input_wait),
  .display_underrun(underrun),.selftest_passed(self_pass),.selftest_failed(self_fail),.good_frames(published_count),.rejected_frames(rejected_count),
 .capture_frame_id(),.processing_frame_id(),.published_frame_id(),.displayed_frame_id(displayed_id),.display_age_ms(display_age),.admitted_frames(admitted_count),.dropped_frames(dropped_count),.rejected_reason_counts(reject_counts),
  .diagnostic_reason(diagnostic_reason),.diagnostic_phase(diagnostic_phase),
  .preview_valid(preview_valid),.preview_rgb(preview_rgb),.overlay_on(overlay_on),.overlay_rgb(overlay_rgb),
  .scan_x(scan_x),.scan_y(scan_y),.scan_de(scan_de),.scan_start(scan_start),.scan_reset_n(scan_reset_n),
  .cmd_result_block(result_block),.result_block_data(full_result_block),.cmd_source_block(source_block),.rsp_source_block(full_source_block),.cmd_burst_data(capture_burst_data),.cmd_valid(cmd_v),.cmd_ready(cmd_r),.cmd_write(cmd_w),.cmd_addr(cmd_a),.cmd_wdata(cmd_data),.cmd_wstrb(cmd_mask),
  .rsp_valid(rsp_v),.rsp_write(rsp_w),.rsp_rdata(rsp_data));
 ddr_word_engine_result_burst #(.CAPTURE_BURST_BEATS(8),.READ_AHEAD_ENABLE(1),.SOURCE_PREFETCH_ENABLE(1),.SOURCE_WORDS(SOURCE_W*SOURCE_H),.SOURCE_BASE1(28'h0800000),.RESULT_WORDS(RESULT_W*RESULT_H),
  .RESULT_BASE0(28'h0200000),.RESULT_BASE1(28'h0400000)) engine(.cmd_result_block(result_block),.result_block_data(full_result_block),.cmd_source_block(source_block),.rsp_source_block(full_source_block),.clk(ui_clk),.rst_n(ui_rst),.init_done(ddr_ready),
  .cmd_valid(cmd_v),.cmd_ready(cmd_r),.cmd_write(cmd_w),.cmd_addr(cmd_a),.cmd_wdata(cmd_data),.cmd_wstrb(cmd_mask),
  .rsp_valid(rsp_v),.rsp_write(rsp_w),.rsp_rdata(rsp_data),.fault(engine_fault),.capture_burst_data(capture_burst_data),.fault_reason(engine_reason),
  .axi_awaddr(awaddr),.axi_awuser_ap(awap),.axi_awuser_id(awid),.axi_awlen(awlen),.axi_awvalid(awvalid),.axi_awready(awready),
  .axi_wdata(wdata),.axi_wstrb(wstrb),.axi_wready(wready),.axi_wusero_id(wid),.axi_wusero_last(wlast),
  .axi_araddr(araddr),.axi_aruser_ap(arap),.axi_aruser_id(arid),.axi_arlen(arlen),.axi_arvalid(arvalid),.axi_arready(arready),
  .axi_rdata(rdata),.axi_rid(rid),.axi_rlast(rlast),.axi_rvalid(rvalid));
 ddr3_ip memory_ip(.ref_clk(ref_clk),.resetn(mem_reset),.core_clk(ui_clk),.pll_lock(ddr_lock),
  .phy_pll_lock(),.gpll_lock(),.rst_gpll_lock(),.ddrphy_cpd_lock(),.ddr_init_done(ddr_ready),
  .axi_awaddr(awaddr),.axi_awuser_ap(awap),.axi_awuser_id(awid),.axi_awlen(awlen),.axi_awready(awready),.axi_awvalid(awvalid),
  .axi_wdata(wdata),.axi_wstrb(wstrb),.axi_wready(wready),.axi_wusero_id(wid),.axi_wusero_last(wlast),
  .axi_araddr(araddr),.axi_aruser_ap(arap),.axi_aruser_id(arid),.axi_arlen(arlen),.axi_arready(arready),.axi_arvalid(arvalid),
  .axi_rdata(rdata),.axi_rid(rid),.axi_rlast(rlast),.axi_rvalid(rvalid),
  .apb_clk(1'b0),.apb_rst_n(1'b0),.apb_sel(1'b0),.apb_enable(1'b0),.apb_addr(8'd0),.apb_write(1'b0),.apb_wdata(16'd0),.apb_ready(),.apb_rdata(),
  .mem_cs_n(mem_cs_n),.mem_rst_n(mem_rst_n),.mem_ck(mem_ck),.mem_ck_n(mem_ck_n),.mem_cke(mem_cke),
  .mem_ras_n(mem_ras_n),.mem_cas_n(mem_cas_n),.mem_we_n(mem_we_n),.mem_odt(mem_odt),.mem_a(mem_a),.mem_ba(mem_ba),
  .mem_dqs(mem_dqs),.mem_dqs_n(mem_dqs_n),.mem_dq(mem_dq),.mem_dm(mem_dm),
  .dbg_gate_start(1'b0),.dbg_cpd_start(1'b0),.dbg_ddrphy_rst_n(1'b1),.dbg_gpll_scan_rst(1'b0),
  .samp_position_dyn_adj(1'b0),.init_samp_position_even(32'd0),.init_samp_position_odd(32'd0),
  .wrcal_position_dyn_adj(1'b0),.init_wrcal_position(32'd0),.force_read_clk_ctrl(1'b0),.init_slip_step(16'd0),.init_read_clk_ctrl(12'd0),
  .debug_calib_ctrl(),.dbg_slice_status(),.dbg_slice_state(),.debug_data(),.dbg_dll_upd_state(),.debug_gpll_dps_phase(),
  .dbg_rst_dps_state(),.dbg_tran_err_rst_cnt(),.dbg_ddrphy_init_fail(phy_fail),
  .debug_cpd_offset_adj(1'b0),.debug_cpd_offset_dir(1'b0),.debug_cpd_offset(10'd0),.debug_dps_cnt_dir0(),.debug_dps_cnt_dir1(),
  .ck_dly_en(1'b1),.init_ck_dly_step(8'd0),.ck_dly_set_bin(),.align_error(align_error),.debug_rst_state(),.debug_cpd_state());
 always @(posedge pix_clk or negedge pix_rst)begin
  if(!pix_rst)begin hd_tx_hs<=0;hd_tx_vs<=0;hd_tx_de<=0;hd_tx_data<=0;end
  else begin hd_tx_hs<=hs;hd_tx_vs<=vs;hd_tx_de<=den;hd_tx_data<=rgb;end
 end
 assign hd_tx_pclk=pix_clk;
 reg [25:0] heartbeat;
 always @(posedge sys_clk_27m or negedge proc_rst)begin
  if(!proc_rst)heartbeat<=0;else heartbeat<=heartbeat+1'b1;
 end
 assign led={rx_done&&tx_done,config_error||engine_fault||phy_fail||align_error||self_fail,
  underrun,frame_error||input_wait,image_valid,self_pass,ddr_ready,heartbeat[24]};
endmodule
`default_nettype wire
