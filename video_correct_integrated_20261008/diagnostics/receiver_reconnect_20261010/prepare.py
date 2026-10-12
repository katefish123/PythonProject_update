"""Reproduce HDMI lock=03 reconnect against the baseline and an isolated fix."""
from pathlib import Path
import hashlib
import json

D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/'results'
O.mkdir(parents=True,exist_ok=True)
baseline=(R/'rtl/hdmi/ms7200_ctl.v').read_text(encoding='utf-8-sig')
old="(!init_over || ((freq_rec_2d[17:16] == 2'b00) && (freq_rec_1d[17:16] == 2'b10)))"
new="(!init_over || (freq_rec_2d[17] == 1'b0))"
assert baseline.count(old)==1
(O/'ms7200_ctl_baseline.v').write_text(baseline,encoding='utf-8')
(O/'ms7200_ctl_reconnect.v').write_text(baseline.replace(old,new),encoding='utf-8')
device=(R/'sim/tb_hdmi_config.sv').read_text(encoding='utf-8')
device=device[device.index('module ms72xx_i2c_test_device ('):]
(O/'ms72xx_i2c_test_device.sv').write_text('`timescale 1ns/1ps\n'+device,encoding='utf-8')
(O/'tb_hdmi_config_regression.sv').write_bytes((R/'sim/tb_hdmi_config.sv').read_bytes())
for name,rx_source,top,generic in [
    ('baseline','ms7200_ctl_baseline.v','tb_rx_reconnect',''),
    ('fixed_hdmi','ms7200_ctl_reconnect.v','tb_rx_reconnect','-gINITIAL_STATUS=3'),
    ('fixed_dvi','ms7200_ctl_reconnect.v','tb_rx_reconnect','-gINITIAL_STATUS=2'),
    ('config_tx_first','ms7200_ctl_reconnect.v','tb_hdmi_config','-gTX_FIRST=1'),
    ('config_rx_first','ms7200_ctl_reconnect.v','tb_hdmi_config','-gTX_FIRST=0'),
]:
    common=[O/rx_source,R/'rtl/hdmi/ms7210_ctl.v',R/'rtl/hdmi/iic_dri.v',R/'rtl/hdmi/hdmi_config.v']
    if top=='tb_rx_reconnect':common += [O/'ms72xx_i2c_test_device.sv',D/'tb_rx_reconnect.sv']
    else:common += [O/'tb_hdmi_config_regression.sv']
    script=['onerror {quit -f -code 1}',f'transcript file {name}.transcript.log',
            f'if {{![file isdirectory work_{name}]}} {{vlib work_{name}}}',f'vmap work_{name} work_{name}',
            f'vlog -sv -work work_{name} '+' '.join('{'+p.as_posix()+'}' for p in common),
            f'vsim -c -voptargs=+acc -wlf {name}.wlf {generic} work_{name}.{top}','onfinish stop','run -all',
            f'if {{[examine -radix decimal sim:/{top}/test_failed] != 0}} {{quit -f -code 1}}',
            'quit -f -code 0']
    (O/f'{name}.do').write_text('\n'.join(script)+'\n',encoding='utf-8')
manifest={str(R/'rtl/hdmi/ms7200_ctl.v'):hashlib.sha256((R/'rtl/hdmi/ms7200_ctl.v').read_bytes()).hexdigest(),
          'fixed_receiver_sha256':hashlib.sha256((O/'ms7200_ctl_reconnect.v').read_bytes()).hexdigest(),
          'hardware_programmed':False}
(O/'candidate_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
print('Prepared isolated HDMI/DVI loss/relock tests; existing receiver source is unchanged.')
