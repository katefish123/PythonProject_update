"""Create a full-resolution camera candidate in a separate source snapshot."""
from pathlib import Path
import hashlib
import json

D = Path(__file__).resolve().parent
R = D.parents[1]
O = D / 'results'
O.mkdir(exist_ok=True)
old = R / 'diagnostics/camera_passthrough_rx_first/results'
top = (old / 'hdmi_camera_passthrough_rx_first_top.v').read_text(encoding='utf-8')
assert top.count(".TX_FIRST(1'b0)") == 1
top = top.replace('hdmi_camera_passthrough_rx_first_top', 'camera_live_native_top')
top = top.replace(".TX_FIRST(1'b0)", ".TX_FIRST(1'b1)")
top = top.replace('// Temporary live-camera alignment mode: forwards the real RX pixel stream.',
                  '// Full-resolution RGB888 preview: every real RX pixel reaches TX.')
(O / 'camera_live_native_top.v').write_text(top, encoding='utf-8')
sources = [O / 'camera_live_native_top.v']
inputs = [R / 'rtl/common/reset_sync.v']
inputs += [R / f'rtl/hdmi/{name}.v' for name in ['hdmi_config', 'iic_dri', 'ms7210_ctl']]
inputs += [R / 'diagnostics/receiver_reconnect_20261010/board_results/ms7200_ctl.v',
           R / 'vendor/c_current/01_design_code/hdmi_vs_recover.v',
           R / 'vendor/c_current/01_design_code/ip/config_pll_27m_10m/config_pll_27m_10m.v']
provenance = {}
for p in inputs:
    data = p.read_bytes()
    if p.name == 'ms7200_ctl.v':
        assert hashlib.sha256(data).hexdigest() == '634bdc4160499c30139ce1765ebfa62ca081927a44c602b8a044940478372e26'
    target = O / p.name
    target.write_bytes(data)
    sources.append(target)
    provenance[str(target)] = str(p)
fdc = O / 'camera_live_native.fdc'
fdc.write_bytes((old / 'camera_passthrough_rx_first.fdc').read_bytes())
flow = ['set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676']
flow += [f'add_design {{{p.as_posix()}}}' for p in sources]
flow += [f'add_constraint -logic -fdc {{{fdc.as_posix()}}}',
         'compile -top_module camera_live_native_top', 'synthesize -ads',
         'dev_map', 'pnr', 'report_timing', 'gen_bit_stream']
(O / 'build.tcl').write_text('\n'.join(flow) + '\n', encoding='utf-8')
hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources + [fdc]}
(O / 'source_hashes.json').write_text(json.dumps(hashes, indent=2) + '\n', encoding='utf-8')
(O / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n', encoding='utf-8')

tb = (old / 'tb_rx_first_pixels.sv').read_text(encoding='utf-8')
tb = tb.replace('hdmi_camera_passthrough_rx_first_top', 'camera_live_native_top')
(O / 'tb_native_pixels.sv').write_text(tb, encoding='utf-8')
(O / 'video_timing_vtc.v').write_bytes((R / 'vendor/c_current/01_design_code/video_timing_vtc.v').read_bytes())
(O / 'tb_hdmi_config.sv').write_bytes((R / 'sim/tb_hdmi_config.sv').read_bytes())
(O / 'tb_rx_reconnect.sv').write_bytes((R / 'diagnostics/receiver_reconnect_20261010/tb_rx_reconnect.sv').read_bytes())
model = (R / 'sim/tb_hdmi_config.sv').read_text(encoding='utf-8')
model = model[model.index('module ms72xx_i2c_test_device ('):]
(O / 'ms72xx_i2c_test_device.sv').write_text('`timescale 1ns/1ps\n' + model, encoding='utf-8')
cases = {
    'pixels_normal': ('tb_hdmi_camera_native', '-gMISSING_VS=0 -gH_FRONT=88',
                     ['camera_live_native_top.v', 'reset_sync.v', 'hdmi_vs_recover.v', 'video_timing_vtc.v', 'tb_native_pixels.sv']),
    'pixels_missing_vs': ('tb_hdmi_camera_native', '-gMISSING_VS=1 -gH_FRONT=90',
                         ['camera_live_native_top.v', 'reset_sync.v', 'hdmi_vs_recover.v', 'video_timing_vtc.v', 'tb_native_pixels.sv']),
    'real_config': ('tb_hdmi_config', '-gTX_FIRST=1',
                    ['hdmi_config.v', 'ms7200_ctl.v', 'ms7210_ctl.v', 'iic_dri.v', 'tb_hdmi_config.sv']),
    'real_reconnect': ('tb_rx_reconnect', '-gINITIAL_STATUS=3',
                       ['hdmi_config.v', 'ms7200_ctl.v', 'ms7210_ctl.v', 'iic_dri.v', 'ms72xx_i2c_test_device.sv', 'tb_rx_reconnect.sv']),
}
for name, (module, generic, files) in cases.items():
    lib = 'work_' + name
    script = ['onerror {quit -f -code 1}', f'transcript file {name}.transcript.log',
              f'if {{![file isdirectory {lib}]}} {{vlib {lib}}}', f'vmap {lib} {lib}',
              f'vlog -sv -work {lib} ' + ' '.join(files),
              f'vsim -c -voptargs=+acc -wlf {name}.wlf {generic} {lib}.{module}',
              'onfinish stop', 'run -all',
              f'if {{[examine -radix decimal sim:/{module}/test_failed] != 0}} {{quit -f -code 1}}']
    if module != 'tb_hdmi_config':
        script.append(f'if {{[examine -radix decimal sim:/{module}/test_passed] != 1}} {{quit -f -code 1}}')
    script.append('quit -f -code 0')
    (O / f'{name}.do').write_text('\n'.join(script) + '\n', encoding='utf-8')

restore = (R / '恢复相机预览.cmd').read_text(encoding='utf-8')
restore = restore.replace('program_camera_live_bram.ps1', 'program_camera_live_bram_reconnect.ps1')
(R / '恢复相机预览_重连修正版.cmd').write_text(restore, encoding='ascii')
print('Prepared isolated native RGB888 path with qualified TX-first startup and receiver reconnect fix.')
