"""Make a separate RX-first passthrough trial without changing previous builds."""
from pathlib import Path
import json
D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/'results'
O.mkdir(exist_ok=True)
previous=R/'diagnostics/camera_passthrough'
top=(previous/'hdmi_camera_passthrough_top.v').read_text(encoding='utf-8')
assert top.count('module hdmi_camera_passthrough_top(')==1
assert top.count(".TX_FIRST(1'b1)")==1
top=top.replace('module hdmi_camera_passthrough_top(', 'module hdmi_camera_passthrough_rx_first_top(')
top=top.replace(".TX_FIRST(1'b1)",".TX_FIRST(1'b0)")
(O/'hdmi_camera_passthrough_rx_first_top.v').write_text(top,encoding='utf-8')
fdc=O/'camera_passthrough_rx_first.fdc'
fdc.write_bytes((previous/'results/camera_passthrough.fdc').read_bytes())
sources=[O/'hdmi_camera_passthrough_rx_first_top.v',R/'rtl/common/reset_sync.v']
sources += [R/f'rtl/hdmi/{n}.v' for n in ['hdmi_config','iic_dri','ms7200_ctl','ms7210_ctl']]
sources += [R/'vendor/c_current/01_design_code/hdmi_vs_recover.v',
            R/'vendor/c_current/01_design_code/ip/config_pll_27m_10m/config_pll_27m_10m.v']
assert all(p.is_file() for p in sources)
flow=['set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676']
flow += [f'add_design {{{p.as_posix()}}}' for p in sources]
flow += [f'add_constraint -logic -fdc {{{fdc.as_posix()}}}',
 'compile -top_module hdmi_camera_passthrough_rx_first_top','synthesize -ads',
 'dev_map','pnr','report_timing','gen_bit_stream']
(O/'build.tcl').write_text('\n'.join(flow)+'\n',encoding='utf-8')
tb=(previous/'results/tb_camera_passthrough.sv').read_text(encoding='utf-8')
tb=tb.replace('hdmi_camera_passthrough_top dut','hdmi_camera_passthrough_rx_first_top dut')
(O/'tb_rx_first_pixels.sv').write_text(tb,encoding='utf-8')
sim=['onerror {quit -f -code 1}','transcript file pixels.log',
 'if {[info exists env(RX_FIRST_MISSING_VS)]} {set missing_vs $env(RX_FIRST_MISSING_VS)} else {set missing_vs 0}',
 'if {[info exists env(RX_FIRST_H_FRONT)]} {set h_front $env(RX_FIRST_H_FRONT)} else {set h_front 88}',
 'if {![file isdirectory work_pixels]} {vlib work_pixels}','vmap work_pixels work_pixels',
 f'vlog -sv -work work_pixels hdmi_camera_passthrough_rx_first_top.v {{{(R/"rtl/common/reset_sync.v").as_posix()}}} {{{(R/"vendor/c_current/01_design_code/hdmi_vs_recover.v").as_posix()}}} {{{(R/"vendor/c_current/01_design_code/video_timing_vtc.v").as_posix()}}} tb_rx_first_pixels.sv',
 'vsim -c -voptargs=+acc -wlf pixels.wlf -gMISSING_VS=$missing_vs -gH_FRONT=$h_front work_pixels.tb_hdmi_camera_native',
 'run -all',
 'if {[examine -radix decimal sim:/tb_hdmi_camera_native/test_failed] != 0} {quit -f -code 1}',
 'if {[examine -radix decimal sim:/tb_hdmi_camera_native/test_passed] != 1} {quit -f -code 1}',
 'quit -f -code 0']
(O/'run_pixels.do').write_text('\n'.join(sim)+'\n',encoding='utf-8')
config=['onerror {quit -f -code 1}','transcript file rx_first_config.log',
 'if {![file isdirectory work_rx_config]} {vlib work_rx_config}',
 'vmap work_rx_config work_rx_config',
 'vlog -sv -work work_rx_config ' + ' '.join(f'{{{p.as_posix()}}}' for p in
     [R/f'rtl/hdmi/{n}.v' for n in ['ms7200_ctl','ms7210_ctl','iic_dri','hdmi_config']]+[R/'sim/tb_hdmi_config.sv']),
 'vsim -c -voptargs=+acc -wlf rx_first_config.wlf -gTX_FIRST=0 work_rx_config.tb_hdmi_config',
 'run -all',
 'if {[examine -radix decimal sim:/tb_hdmi_config/test_failed] != 0} {quit -f -code 1}',
 'quit -f -code 0']
(O/'run_config.do').write_text('\n'.join(config)+'\n',encoding='utf-8')
(O/'sources.json').write_text(json.dumps([str(p) for p in sources],indent=2)+'\n',encoding='utf-8')
print('Prepared isolated RX-first passthrough: only init order changed.')
