"""Build a standalone diagnostic using the current, validated HDMI controller."""
from pathlib import Path
import json
import re

D = Path(__file__).resolve().parent
R = D.parents[1]
O = D / 'results'
O.mkdir(exist_ok=True)
cfg = (R/'rtl/hdmi/hdmi_config.v').read_text(encoding='utf-8-sig')
cfg = cfg.replace('module hdmi_config #(', 'module hdmi_config_runtime_diag #(', 1)
needle = '    output reg startup_retry_seen\n'
assert cfg.count(needle) == 1
cfg = cfg.replace(needle, needle.rstrip('\n') + ',\n    output wire [143:0] debug_word\n')
instrumentation = '''
    // Observation only: no assignments back into the operational controller.
    reg [31:0] debug_frequency;
    reg [7:0] debug_1281, debug_device, debug_data, debug_nack_device;
    reg [15:0] debug_addr, debug_nack_addr, debug_nack_count, debug_transaction_count;
    reg debug_owner, debug_write, debug_nack_owner, debug_nack_write;
    always @(posedge cfg_clk or negedge controller_reset_n) begin
        if (!controller_reset_n) begin
            debug_frequency<=0;debug_1281<=0;debug_device<=0;debug_data<=0;
            debug_addr<=0;debug_nack_device<=0;debug_nack_addr<=0;
            debug_nack_count<=0;debug_transaction_count<=0;
            debug_owner<=0;debug_write<=0;debug_nack_owner<=0;debug_nack_write<=0;
        end else begin
            if (bus_falling) begin
                debug_device<=transaction_device;debug_addr<=transaction_addr;
                debug_data<=read_data;debug_owner<=transaction_owner_tx;debug_write<=transaction_write;
                if(debug_transaction_count!=16'hffff)debug_transaction_count<=debug_transaction_count+1'b1;
                if(!transaction_owner_tx&&!transaction_write&&!transaction_nack) begin
                    case(transaction_addr)
                        16'h209C:debug_frequency[7:0]<=read_data;
                        16'h209D:debug_frequency[15:8]<=read_data;
                        16'h209E:debug_frequency[23:16]<=read_data;
                        16'h209F:debug_frequency[31:24]<=read_data;
                        16'h1281:debug_1281<=read_data;
                    endcase
                end
            end
            if(nack_pulse)begin
                debug_nack_device<=transaction_device;debug_nack_addr<=transaction_addr;
                debug_nack_owner<=transaction_owner_tx;debug_nack_write<=transaction_write;
                if(debug_nack_count!=16'hffff)debug_nack_count<=debug_nack_count+1'b1;
            end
        end
    end
    assign debug_word={config_error,startup_retry_seen,tx_done,rx_done,ack_error,
        tx_probe_done,rx_probe_done,select_tx,debug_frequency,debug_1281,
        debug_device,debug_addr,debug_data,debug_nack_device,debug_nack_addr,
        debug_nack_count,debug_transaction_count,3'b000,bus_busy,debug_owner,
        debug_write,debug_nack_owner,debug_nack_write};
'''
assert cfg.count('\nendmodule') == 1
cfg = cfg.replace('\nendmodule', instrumentation+'\nendmodule')
(O/'hdmi_config_runtime_diag.v').write_text(cfg,encoding='utf-8')

ports={'sys_clk_27m','rst_n','hd_rx_pclk','hd_rx_vs','hd_rx_hs','hd_rx_de',
       'hd_tx_pclk','hd_tx_vs','hd_tx_hs','hd_tx_de','hd_reset_n','hd_scl','hd_sda',
       *{f'hd_rx_data[{i}]' for i in range(24)},*{f'hd_tx_data[{i}]' for i in range(24)},
       *{f'led[{i}]' for i in range(8)}}
lines=[]
for line in (R/'constr/board_bram.fdc').read_text(encoding='utf-8-sig').splitlines():
    if line.startswith('define_attribute {p:'):
        match=re.match(r'define_attribute \{p:(.+?)\} ',line)
        if match and match.group(1) in ports:lines.append(line)
    elif line.startswith('set_false_path -from [get_ports {rst_n'):
        lines.append('set_false_path -from [get_ports {rst_n}]')
    else:lines.append(line)
constrained={m.group(1) for line in lines if (m:=re.match(r'define_attribute \{p:(.+?)\} \{PAP_IO_DIRECTION\}',line))}
assert constrained==ports
fdc=O/'runtime_probe.fdc'
fdc.write_text('\n'.join(lines)+'\n',encoding='utf-8')
sources=[D/'hdmi_runtime_probe_top.v',O/'hdmi_config_runtime_diag.v',R/'rtl/common/reset_sync.v']
sources += [R/f'rtl/hdmi/{n}.v' for n in ['iic_dri','ms7200_ctl','ms7210_ctl']]
sources += [R/'vendor/c_current/01_design_code/video_timing_vtc.v']
sources += [R/f'vendor/c_current/01_design_code/ip/{n}/{n}.v' for n in ['video_pll_27m_148m5','config_pll_27m_10m']]
assert all(p.is_file() for p in sources)
flow=['set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676']
flow += [f'add_design {{{p.as_posix()}}}' for p in sources]
flow += [f'add_constraint -logic -fdc {{{fdc.as_posix()}}}','compile -top_module hdmi_runtime_probe_top',
         'synthesize -ads','dev_map','pnr','report_timing','gen_bit_stream']
(O/'build.tcl').write_text('\n'.join(flow)+'\n',encoding='utf-8')
(O/'sources.json').write_text(json.dumps([str(p) for p in sources],indent=2)+'\n',encoding='utf-8')
print('Prepared current HDMI controller with observation-only status and held CDC bundles.')
