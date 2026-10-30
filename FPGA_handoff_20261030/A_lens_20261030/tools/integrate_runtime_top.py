from pathlib import Path
b=Path('C:/D/FPGA/A_lens_20261030/candidate_host_angle_v1/sources');p=b/'video_correct_ddr_top.v';s=p.read_text();assert 'uart_rx' not in s
s=s.replace(' input wire sys_clk_27m,rst_n,key1_pattern_n,key2_nearest_n,',' input wire sys_clk_27m,rst_n,key1_pattern_n,key2_nearest_n,\n input wire uart_rx,output wire uart_tx,')
block='''
 wire host_valid,host_ready,host_committed,angle_valid,angle_ready;
 wire[239:0]host_affine,angle_affine;wire[15:0]host_seq,host_committed_seq,angle_seq;
 lens_uart_control host_control(.clk(sys_clk_27m),.rst_n(clocks_ready),.uart_rx(uart_rx),.uart_tx(uart_tx),
 .cfg_valid(host_valid),.cfg_ready(host_ready),.cfg_sequence(host_seq),.cfg_affine(host_affine),.commit_valid(host_committed),.commit_sequence(host_committed_seq));
 lens_parameter_mailbox angle_mailbox(.s_clk(sys_clk_27m),.d_clk(proc_clk57),.rst_n(clocks_ready),
 .s_valid(host_valid),.s_ready(host_ready),.s_affine(host_affine),.s_sequence(host_seq),.s_commit_valid(host_committed),.s_commit_sequence(host_committed_seq),
 .d_valid(angle_valid),.d_ready(angle_ready),.d_affine(angle_affine),.d_sequence(angle_seq));
'''
s=s.replace(' wire cfg_rst,mem_reset,proc_rst,rx_rst,pix_rst,ui_rst;',' wire cfg_rst,mem_reset,proc_rst,rx_rst,pix_rst,ui_rst;'+block)
start=s.index(' video_correct_ddr_continuous_core #(');end=s.index(') core(',start);part=s[start:end]+',.RUNTIME_AFFINE(1),.TILED_ORDER(1),.SOURCE_CACHE_LINES(128)';s=s[:start]+part+s[end:]
s=s.replace(') core(',') core(.cfg_valid(angle_valid),.cfg_ready(angle_ready),.cfg_affine(angle_affine),.cfg_sequence(angle_seq),.commit_valid(),.commit_sequence(),\n',1);p.write_text(s)
p=b/'board_ddr.fdc';s=p.read_text();assert 'p:uart_rx' not in s
s+='\n# Board USB-CP2102: official MES2L676-100HP hardware guide pp.43-44.\n'
for name,site,direction in [('uart_rx','B24','INPUT'),('uart_tx','C24','OUTPUT')]:
 for key,val in [('PAP_IO_DIRECTION',direction),('PAP_IO_LOC',site),('PAP_IO_VCCIO','3.3'),('PAP_IO_STANDARD','LVCMOS33')]:s+='define_attribute {p:'+name+'} {'+key+'} {'+val+'}\n'
p.write_text(s)
print('Top host UART, persistent parameter CDC and official3.3V B24/C24 pins integrated.')