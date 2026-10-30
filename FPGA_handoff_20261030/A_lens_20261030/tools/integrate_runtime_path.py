from pathlib import Path
b=Path('C:/D/FPGA/A_lens_20261030/candidate_host_angle_v1/sources')
p=b/'c_stream_burst_correction_path.v';s=p.read_text();s=s.replace('parameter CACHE_LINES=64','parameter CACHE_LINES=64,RUNTIME_AFFINE=0,TILED_ORDER=0')
s=s.replace(' input wire proc_clk,ui_clk,rst_n,start,abort,nearest,input_geometry_valid,',' input wire proc_clk,ui_clk,rst_n,start,abort,nearest,input_geometry_valid,\n input wire cfg_valid,input wire[239:0]cfg_affine,input wire[15:0]cfg_sequence,output wire cfg_ready,commit_valid,output wire[15:0]commit_sequence,')
s=s.replace('.FIXED_IDENTITY(FIXED_IDENTITY)) processor(','.FIXED_IDENTITY(FIXED_IDENTITY),.RUNTIME_AFFINE(RUNTIME_AFFINE),.TILED_ORDER(TILED_ORDER)) processor(')
s=s.replace(' .debug_h(debug_h),.clk(proc_clk)', ' .cfg_valid(cfg_valid),.cfg_ready(cfg_ready),.cfg_affine(cfg_affine),.cfg_sequence(cfg_sequence),.commit_valid(commit_valid),.commit_sequence(commit_sequence),\n .debug_h(debug_h),.clk(proc_clk)')
s=s.replace('.BASE1(RESULT_BASE1)) writer(','.BASE1(RESULT_BASE1),.TILED_ORDER(TILED_ORDER)) writer(');p.write_text(s)
p=b/'video_correct_ddr_continuous_core.v';s=p.read_text();s=s.replace(')(\n input wire proc_clk,',',parameter RUNTIME_AFFINE=0,TILED_ORDER=0,SOURCE_CACHE_LINES=64\n)(\n input wire proc_clk,',1)
s=s.replace(' input wire nearest,force_pattern,raw_requested,',' input wire nearest,force_pattern,raw_requested,\n input wire cfg_valid,input wire[239:0]cfg_affine,input wire[15:0]cfg_sequence,output wire cfg_ready,commit_valid,output wire[15:0]commit_sequence,')
s=s.replace('.RESULT_BASE1(RESULT_BASE1)) stream_path(','.RESULT_BASE1(RESULT_BASE1),.RUNTIME_AFFINE(RUNTIME_AFFINE),.TILED_ORDER(TILED_ORDER),.CACHE_LINES(SOURCE_CACHE_LINES)) stream_path(')
needle=')) stream_path(\n';assert needle in s;s=s.replace(needle,needle+' .cfg_valid(cfg_valid),.cfg_ready(cfg_ready),.cfg_affine(cfg_affine),.cfg_sequence(cfg_sequence),.commit_valid(commit_valid),.commit_sequence(commit_sequence),\n',1);p.write_text(s)
p=b/'video_correct_ddr_top.v';s=p.read_text();s=s.replace(' input wire sys_clk_27m,rst_n,key1_pattern_n,key2_nearest_n,',' input wire sys_clk_27m,rst_n,key1_pattern_n,key2_nearest_n,\n input wire uart_rx,output wire uart_tx,')
needle=' wire cfg_rst,mem_reset,proc_rst,rx_rst,pix_rst,ui_rst;';assert s.count(needle)==1
block='''
 wire host_valid,host_ready,host_committed,angle_valid,angle_ready;
 wire[239:0]host_affine,angle_affine;wire[15:0]host_seq,host_committed_seq,angle_seq;
 lens_uart_control host_control(.clk(sys_clk_27m),.rst_n(clocks_ready),.uart_rx(uart_rx),.uart_tx(uart_tx),
 .cfg_valid(host_valid),.cfg_ready(host_ready),.cfg_sequence(host_seq),.cfg_affine(host_affine),.commit_valid(host_committed),.commit_sequence(host_committed_seq));
 lens_parameter_mailbox angle_mailbox(.s_clk(sys_clk_27m),.d_clk(proc_clk57),.rst_n(clocks_ready),
 .s_valid(host_valid),.s_ready(host_ready),.s_affine(host_affine),.s_sequence(host_seq),.s_commit_valid(host_committed),.s_commit_sequence(host_committed_seq),
 .d_valid(angle_valid),.d_ready(angle_ready),.d_affine(angle_affine),.d_sequence(angle_seq));
'''
s=s.replace(needle,needle+block)
# Add core parameters at its existing instantiation without altering defaults elsewhere.
start=s.index(' video_correct_ddr_continuous_core #(');end=s.index(') core(',start);part=s[start:end];part+=',.RUNTIME_AFFINE(1),.TILED_ORDER(1),.SOURCE_CACHE_LINES(128)';s=s[:start]+part+s[end:]
needle=') core(\n';assert needle in s;s=s.replace(needle,needle+' .cfg_valid(angle_valid),.cfg_ready(angle_ready),.cfg_affine(angle_affine),.cfg_sequence(angle_seq),.commit_valid(),.commit_sequence(),\n',1);p.write_text(s)
print('Runtime-angle data/commit ports connected through C path/core/top; mailbox and UART27MHz retain parameters over application recovery.')