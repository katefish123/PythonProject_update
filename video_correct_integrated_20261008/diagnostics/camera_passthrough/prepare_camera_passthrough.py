"""Prepare a small live-camera passthrough, preserving C's pin/timing model."""
from pathlib import Path
import re
R=Path(__file__).resolve().parents[2]
D=Path(__file__).resolve().parent
O=D/'results'
O.mkdir(exist_ok=True)
base=(R/'constr/board_bram.fdc').read_text(encoding='utf-8-sig')
lines=[]
for line in base.splitlines():
    if 'key1_pattern_n' in line or 'key2_nearest_n' in line:
        if line.startswith('set_false_path -from'):lines.append('set_false_path -from [get_ports {rst_n}]')
        continue
    if line.startswith('create_clock -name pixel_clock') or line.startswith('set_clock_groups'):continue
    if line.startswith('create_generated_clock -name tx_pixel'):
        lines.append('create_generated_clock -name tx_pixel -divide_by 1 -source [get_ports {hd_rx_pclk}] [get_ports {hd_tx_pclk}]')
    else:lines.append(line)
lines.append('set_clock_groups -asynchronous -group [get_clocks {sys_clk_27m}] -group [get_clocks {cfg_clock}] -group [get_clocks {rx_pixel tx_pixel}]')
fdc=O/'camera_passthrough.fdc'
fdc.write_text('\n'.join(lines)+'\n',encoding='utf-8')
sources=[D/'hdmi_camera_passthrough_top.v',R/'rtl/common/reset_sync.v']
sources += [R/f'rtl/hdmi/{n}.v' for n in ['hdmi_config','iic_dri','ms7200_ctl','ms7210_ctl']]
sources += [R/'vendor/c_current/01_design_code/hdmi_vs_recover.v',R/'vendor/c_current/01_design_code/ip/config_pll_27m_10m/config_pll_27m_10m.v']
flow=['set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676']
flow += [f'add_design {{{p.as_posix()}}}' for p in sources]
flow += [f'add_constraint -logic -fdc {{{fdc.as_posix()}}}','compile -top_module hdmi_camera_passthrough_top','synthesize -ads','dev_map','pnr','report_timing','gen_bit_stream']
(O/'build.tcl').write_text('\n'.join(flow)+'\n',encoding='utf-8')
# Reuse C's full-frame timing/pixel test with only the top/config-interface names changed.
tb=(R/'vendor/c_current/02_simulation/tb_hdmi_camera_native.v').read_text()
start=tb.index('module ms72xx_shared_config')
end=tb.index('endmodule',start)+len('endmodule')
stub='module hdmi_config #(parameter TX_FIRST=0)(input cfg_clk,reset_n,output rx_done,tx_done,scl,ack_error,config_error,startup_retry_seen,inout sda); assign rx_done=reset_n;assign tx_done=reset_n;assign scl=1;assign sda=1\'bz;assign ack_error=0;assign config_error=0;assign startup_retry_seen=0; endmodule'
tb=tb[:start]+stub+tb[end:]
tb=tb.replace('hdmi_camera_loop_top dut','hdmi_camera_passthrough_top dut').replace('.hdmi_init_done(txdone),.rx_init_done(rxdone),','.led(),')
(O/'tb_camera_passthrough.sv').write_text(tb,encoding='utf-8')
print('Prepared passthrough sources and C full-frame pixel/timing verification')
