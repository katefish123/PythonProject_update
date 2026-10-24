"""Exact allowed diagnostic-only top transformation; no file or tool access."""
def transform(t):
 def replace(old,new):
  nonlocal t
  if t.count(old)!=1:raise RuntimeError('Expected unique binding: '+old)
  t=t.replace(old,new)
 replace('assign overlay_on=(status_on&&(diagnostic_shown||warning_shown))||(telemetry_on&&diagnostic_shown);','assign overlay_on=status_on||telemetry_on;')
 replace('assign overlay_rgb=status_on&&(diagnostic_shown||warning_shown)?status_rgb:telemetry_rgb;','assign overlay_rgb=status_on?status_rgb:telemetry_rgb;')
 replace("assign trace_data[480+:80]={32'd0,debug_corners[95:48]};","assign trace_data[480+:80]={16'd0,reject_counts[12*32+:32],reject_counts[13*32+:32]};")
 replace("assign trace_data[560+:80]={32'd0,debug_corners[47:0]};","assign trace_data[560+:80]={16'd0,reject_counts[14*32+:32],reject_counts[15*32+:32]};")
 replace("assign trace_data[1440+:80]={52'd0,debug_source_base};","assign trace_data[1440+:80]={16'd0,proc_service_totals[127:64]};")
 replace("assign trace_data[1520+:80]={16'd0,proc_first_service[191:128]};","assign trace_data[1520+:80]={16'd0,proc_service_totals[63:0]};")
 replace("assign trace_data[1840+:80]={32'd0,proc_source_history[0+:48]};","assign trace_data[1840+:80]={proc_scan_count,proc_source_history[0+:48]};")
 replace("assign trace_data[1760+:80]={15'd0,first_fifo_valid", "assign trace_data[1760+:80]={underrun_proc[2],14'd0,first_fifo_valid")
 anchor=' wire[1919:0]trace_data;wire[79:0]actual_pix_metadata;'
 observers=' // Read-only diagnosis; no protection, memory command or timing outputs.\n reg[31:0]diag_scan_count;\n always @(posedge pix_clk or negedge clocks_ready)\n if(!clocks_ready)diag_scan_count<=0;else if(scan_reset_n&&scan_start)diag_scan_count<=diag_scan_count+1\'b1;\n wire[31:0]proc_scan_count;\n snapshot_cdc #(.WIDTH(32)) scan_observer(.s_clk(pix_clk),.d_clk(proc_clk57),.rst_n(clocks_ready),.s_data(diag_scan_count),.d_data(proc_scan_count),.d_valid());\n (* ASYNC_REG="TRUE" *)reg[2:0]underrun_proc;\n always @(posedge proc_clk57 or negedge clocks_ready)\n if(!clocks_ready)underrun_proc<=0;else underrun_proc<={underrun_proc[1:0],underrun};\n reg[31:0]diag_write_commands,diag_read_commands,diag_write_wait,diag_read_wait;\n always @(posedge ui_clk or negedge ui_rst)begin\n if(!ui_rst)begin diag_write_commands<=0;diag_read_commands<=0;diag_write_wait<=0;diag_read_wait<=0;end\n else begin\n if(awvalid&&awready)diag_write_commands<=diag_write_commands+1\'b1;\n if(arvalid&&arready)diag_read_commands<=diag_read_commands+1\'b1;\n if((service_stage==1||service_stage==2)&&!wready)diag_write_wait<=diag_write_wait+1\'b1;\n if((service_stage==3||service_stage==4)&&!rvalid)diag_read_wait<=diag_read_wait+1\'b1;\n end end\n wire[127:0]ui_service_totals={diag_write_commands,diag_read_commands,diag_write_wait,diag_read_wait};\n wire[127:0]proc_service_totals;\n snapshot_cdc #(.WIDTH(128)) service_totals_observer(.s_clk(ui_clk),.d_clk(proc_clk57),.rst_n(clocks_ready),.s_data(ui_service_totals),.d_data(proc_service_totals),.d_valid());\n'
 replace(anchor,observers+anchor);
 return t
