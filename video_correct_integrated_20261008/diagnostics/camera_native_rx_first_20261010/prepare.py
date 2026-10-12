"""Compare the retained RX-first arbiter against an isolated polling fix."""
from pathlib import Path
import hashlib
import json

D = Path(__file__).resolve().parent
R = D.parents[1]
O = D / 'results'
O.mkdir(exist_ok=True)
original = (R / 'rtl/hdmi/hdmi_config.v').read_text(encoding='utf-8-sig')
(O / 'hdmi_config_baseline.v').write_text(original, encoding='utf-8')
old = '''            if (TX_FIRST && tx_done)
                switch_to_rx <= 1'b1;'''
new = '''            if (tx_done && (TX_FIRST || switch_to_tx))
                switch_to_rx <= 1'b1;'''
assert original.count(old) == 1
fixed = original.replace(old, new)
old = 'assign select_tx = TX_FIRST ? !switch_to_rx : switch_to_tx;'
new = 'assign select_tx = TX_FIRST ? !switch_to_rx : (switch_to_tx && !switch_to_rx);'
assert fixed.count(old) == 1
fixed = fixed.replace(old, new)
# Preserve the receiver's single pending command while TX initializes. The
# receiver command fields stay stable until the command has actually completed.
marker = '    ms7200_ctl u_ms7200_rx ('
assert fixed.count(marker) == 1
fixed = fixed.replace(marker, '''    reg deferred_rx_trigger;
    always @(posedge cfg_clk or negedge controller_reset_n) begin
        if (!controller_reset_n) deferred_rx_trigger <= 1'b0;
        else if (!TX_FIRST && select_tx && rx_trig)
            deferred_rx_trigger <= 1'b1;
        else if (!select_tx && !bus_busy && deferred_rx_trigger)
            deferred_rx_trigger <= 1'b0;
    end
    wire resumed_rx_trigger = rx_trig || (deferred_rx_trigger && !bus_busy);

''' + marker)
assert fixed.count('.pluse(select_tx ? tx_trig : rx_trig)') == 1
fixed = fixed.replace('.pluse(select_tx ? tx_trig : rx_trig)', '.pluse(select_tx ? tx_trig : resumed_rx_trigger)')
(O / 'hdmi_config.v').write_text(fixed, encoding='utf-8')
native = R / 'diagnostics/camera_live_native_20261010/results'
for name in ['ms7200_ctl.v','ms7210_ctl.v','iic_dri.v','reset_sync.v','hdmi_vs_recover.v',
             'config_pll_27m_10m.v','video_timing_vtc.v','tb_hdmi_config.sv','ms72xx_i2c_test_device.sv']:
    (O / name).write_bytes((native / name).read_bytes())
tb = (native / 'tb_rx_reconnect.sv').read_text(encoding='utf-8')
tb = tb.replace('parameter INITIAL_STATUS=3;', 'parameter INITIAL_STATUS=3;\nparameter TX_FIRST=0;')
tb = tb.replace('.TX_FIRST(1)', '.TX_FIRST(TX_FIRST)').replace('.tx_first(1\'b1)', '.tx_first(TX_FIRST != 0)')
tb = tb.replace('integer stable_writes,status_reads_before_loss,reconnected_writes;',
                'integer stable_writes,status_reads_before_loss,reconnected_writes,polls_when_ready;')
tb = tb.replace('stable_writes=writes;\n #5000000;',
                'stable_writes=writes;polls_when_ready=dev.rx_status_reads;\n #5000000;\n if(dev.rx_status_reads<=polls_when_ready)fail("receiver polling stopped after TX initialization");')
(O / 'tb_rx_reconnect.sv').write_text(tb, encoding='utf-8')
top = (native / 'camera_live_native_top.v').read_text(encoding='utf-8')
top = top.replace('camera_live_native_top', 'camera_native_rx_first_top').replace(".TX_FIRST(1'b1)", ".TX_FIRST(1'b0)")
(O / 'camera_native_rx_first_top.v').write_text(top, encoding='utf-8')
pixel_tb = (native / 'tb_native_pixels.sv').read_text(encoding='utf-8').replace('camera_live_native_top', 'camera_native_rx_first_top')
(O / 'tb_native_pixels.sv').write_text(pixel_tb, encoding='utf-8')
fdc = O / 'camera_native_rx_first.fdc'
fdc.write_bytes((native / 'camera_live_native.fdc').read_bytes())
sources = [O / name for name in ['camera_native_rx_first_top.v','reset_sync.v','hdmi_config.v',
           'ms7200_ctl.v','ms7210_ctl.v','iic_dri.v','hdmi_vs_recover.v','config_pll_27m_10m.v']]
flow = ['set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676']
flow += [f'add_design {{{p.as_posix()}}}' for p in sources]
flow += [f'add_constraint -logic -fdc {{{fdc.as_posix()}}}', 'compile -top_module camera_native_rx_first_top',
         'synthesize -ads','dev_map','pnr','report_timing','gen_bit_stream']
(O / 'build.tcl').write_text('\n'.join(flow) + '\n', encoding='utf-8')
(O / 'source_hashes.json').write_text(json.dumps({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[fdc]},indent=2)+'\n',encoding='utf-8')
cases = {
    'baseline_polling': ('hdmi_config_baseline.v','tb_rx_reconnect','-gTX_FIRST=0 -gINITIAL_STATUS=3'),
    'fixed_rx_reconnect': ('hdmi_config.v','tb_rx_reconnect','-gTX_FIRST=0 -gINITIAL_STATUS=3'),
    'fixed_rx_dvi': ('hdmi_config.v','tb_rx_reconnect','-gTX_FIRST=0 -gINITIAL_STATUS=2'),
    'fixed_tx_reconnect': ('hdmi_config.v','tb_rx_reconnect','-gTX_FIRST=1 -gINITIAL_STATUS=3'),
    'config_rx': ('hdmi_config.v','tb_hdmi_config','-gTX_FIRST=0'),
    'config_tx': ('hdmi_config.v','tb_hdmi_config','-gTX_FIRST=1'),
    'pixels': (None,'tb_hdmi_camera_native','-gMISSING_VS=0 -gH_FRONT=88'),
    'pixels_missing_vs': (None,'tb_hdmi_camera_native','-gMISSING_VS=1 -gH_FRONT=90'),
}
for name,(config,top_name,generic) in cases.items():
    if config:
        files = [config,'ms7200_ctl.v','ms7210_ctl.v','iic_dri.v']
        files += ['ms72xx_i2c_test_device.sv','tb_rx_reconnect.sv'] if top_name=='tb_rx_reconnect' else ['tb_hdmi_config.sv']
    else:
        files = ['camera_native_rx_first_top.v','reset_sync.v','hdmi_vs_recover.v','video_timing_vtc.v','tb_native_pixels.sv']
    library = 'work_' + name
    script = ['onerror {quit -f -code 1}',f'transcript file {name}.transcript.log',
              f'if {{![file isdirectory {library}]}} {{vlib {library}}}',f'vmap {library} {library}',
              f'vlog -sv -work {library} '+' '.join(files),
              f'vsim -c -voptargs=+acc -wlf {name}.wlf {generic} {library}.{top_name}',
              'onfinish stop','run -all',
              f'if {{[examine -radix decimal sim:/{top_name}/test_failed] != 0}} {{quit -f -code 1}}',
              'quit -f -code 0']
    (O / f'{name}.do').write_text('\n'.join(script) + '\n',encoding='utf-8')
print('Prepared isolated RX-first polling reproduction and deferred-command fix; no retained release modified.')
