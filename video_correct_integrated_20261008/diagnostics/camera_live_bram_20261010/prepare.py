"""Isolated raw-camera preview; preserve all previous sources and bitstreams."""
from pathlib import Path
import hashlib
import json

D = Path(__file__).resolve().parent
R = D.parents[1]
O = D / 'results'
O.mkdir(parents=True, exist_ok=True)

base = (R/'diagnostics/hdmi_runtime/hdmi_runtime_probe_top.v').read_text(encoding='utf-8-sig')
assert base.count('module hdmi_runtime_probe_top (') == 1
top = base.replace('module hdmi_runtime_probe_top (', 'module camera_live_bram_top (', 1)
top = top.replace('// Temporary diagnostic: an independent TX raster carries real RX/I2C status.',
                  '// Raw camera pixels in two BRAM banks, scaled 6x onto independent 1080p60 TX.')
top = top.replace('reg [255:0] status_frame;', 'reg [319:0] status_frame;')
old = ''' wire [255:0] status_word={16'hD103,flags,cfg_snapshot[135:8],
  rx_snapshot[90:3],cfg_snapshot[7:0]};'''
new = ''' wire frame_valid;
 wire [18:0] buffer_snapshot;
 reg [12:0] display_frame_count;
 wire [319:0] status_word={16'hD104,flags,cfg_snapshot[135:8],
  rx_snapshot[90:3],cfg_snapshot[7:0],16'hB401,15'd0,frame_valid,
  buffer_snapshot,display_frame_count};'''
assert top.count(old) == 1
top = top.replace(old, new)
start = top.index(' wire [3:0] col=')
end = top.index(' assign hd_tx_pclk=pix_clk;', start)
top = top[:start] + ''' // C's real two-clock, two-bank pixel store; no simulated camera in hardware.
 wire [23:0] stored_pixel;
 wire [15:0] samples_written;
 wire [2:0] writer_flags;
 wire output_frame_start=raw_vs&&!raw_vs_prev;
 reg [8:0] scaled_x;
 reg [7:0] scaled_y;
 reg [15:0] read_address;
 reg [2:0] hs_pipe,vs_pipe,de_pipe;
 reg [23:0] fallback_0,fallback_1,fallback_2;
 wire buffer_snapshot_valid,buffer_snapshot_busy;
 cdc_snapshot #(.WIDTH(19)) buffer_observation(
  .src_clk(hd_rx_pclk),.src_reset_n(rx_rst_n),
  .src_data({writer_flags,samples_written}),
  .dst_clk(pix_clk),.dst_reset_n(pix_rst_n),.request(output_frame_start),
  .dst_data(buffer_snapshot),.valid(buffer_snapshot_valid),.busy(buffer_snapshot_busy));
 hdmi_bram_probe camera_store(
  .wr_clk(hd_rx_pclk),.wr_reset_n(rx_rst_n),.de(de_q),.pixel(rgb_q),
  .rd_clk(pix_clk),.rd_reset_n(pix_rst_n),.frame_start(output_frame_start),
  .rd_enable(de_pipe[1]),.rd_addr(de_pipe[1]?read_address:16'd0),
  .rd_pixel(stored_pixel),.frame_valid(frame_valid),
  .samples_written(samples_written),.writer_flags(writer_flags));
 wire [3:0] col=x/12'd120;
 wire [4:0] row=(y-12'd840)/12'd12;
 wire [8:0] bit_index=9'd319-{row,col};
 wire status_area=raw_de&&(y>=12'd840);
 // Without a fresh camera frame, show a diagnostic grid on a dark background.
 // Never substitute a test picture for actual camera pixels.
 wire [23:0] fallback_rgb=status_area?
  (status_frame[bit_index]?24'h00b000:24'hb00000):24'h100010;
 always @(posedge pix_clk or negedge pix_rst_n)begin
  if(!pix_rst_n)begin
   scaled_x<=0;scaled_y<=0;read_address<=0;
   hs_pipe<=0;vs_pipe<=0;de_pipe<=0;
   fallback_0<=0;fallback_1<=0;fallback_2<=0;display_frame_count<=0;
  end else begin
   scaled_x<=raw_de?x/6:0;scaled_y<=raw_de?y/6:0;
   read_address<=scaled_y*320+scaled_x;
   hs_pipe<={hs_pipe[1:0],raw_hs};vs_pipe<={vs_pipe[1:0],raw_vs};
   de_pipe<={de_pipe[1:0],raw_de};
   fallback_0<=fallback_rgb;fallback_1<=fallback_0;fallback_2<=fallback_1;
   if(output_frame_start)display_frame_count<=display_frame_count+1'b1;
  end
 end
 // Register the final pixel selection and its timing together before the pins.
 always @(posedge pix_clk or negedge pix_rst_n)begin
  if(!pix_rst_n)begin hd_tx_hs<=0;hd_tx_vs<=0;hd_tx_de<=0;hd_tx_data<=0;end
  else begin
   hd_tx_hs<=hs_pipe[2];hd_tx_vs<=vs_pipe[2];hd_tx_de<=de_pipe[2];
   hd_tx_data<=de_pipe[2]?(frame_valid?stored_pixel:fallback_2):24'd0;
  end
 end
''' + top[end:]
top = top.replace('assign led={cfg_lock,config_error,startup_retry_seen,de_seen,clock_seen,tx_done,rx_done,heartbeat[24]};',
                  'assign led={cfg_lock,config_error,frame_valid,de_seen,clock_seen,tx_done,rx_done,heartbeat[24]};')
(O/'camera_live_bram_top.v').write_text(top, encoding='utf-8')
copies = {
    'hdmi_bram_probe.v': R/'vendor/c_current/01_design_code/hdmi_bram_probe.v',
    'cdc_snapshot.v': R/'vendor/c_current/01_design_code/cdc_snapshot.v',
    'hdmi_config_runtime_diag.v': R/'diagnostics/hdmi_runtime/results/hdmi_config_runtime_diag.v',
    'tb_hdmi_bram_probe.v': R/'vendor/c_current/02_simulation/tb_hdmi_bram_probe.v',
    'tb_hdmi_bram_stale.v': R/'vendor/c_current/02_simulation/tb_hdmi_bram_stale.v',
}
for name, src in copies.items():
    (O/name).write_bytes(src.read_bytes())
probe_tb = (O/'tb_hdmi_bram_probe.v').read_text(encoding='utf-8')
probe_tb = probe_tb.replace('.frame_valid(valid));',
                            '.frame_valid(valid),.samples_written(),.writer_flags());')
(O/'tb_hdmi_bram_probe.v').write_text(probe_tb, encoding='utf-8')
fdc = O/'camera_live_bram.fdc'
fdc.write_bytes((R/'diagnostics/hdmi_runtime/results/runtime_probe.fdc').read_bytes())
sources = [O/'camera_live_bram_top.v', O/'hdmi_bram_probe.v', O/'cdc_snapshot.v',
           O/'hdmi_config_runtime_diag.v', R/'rtl/common/reset_sync.v']
sources += [R/f'rtl/hdmi/{n}.v' for n in ['iic_dri','ms7200_ctl','ms7210_ctl']]
sources += [R/'vendor/c_current/01_design_code/video_timing_vtc.v']
sources += [R/f'vendor/c_current/01_design_code/ip/{n}/{n}.v'
            for n in ['video_pll_27m_148m5','config_pll_27m_10m']]
assert all(p.is_file() for p in sources)
flow = ['set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676']
flow += [f'add_design {{{p.as_posix()}}}' for p in sources]
flow += [f'add_constraint -logic -fdc {{{fdc.as_posix()}}}',
         'compile -top_module camera_live_bram_top','synthesize -ads',
         'dev_map','pnr','report_timing','gen_bit_stream']
(O/'build.tcl').write_text('\n'.join(flow)+'\n', encoding='utf-8')
for test in ['tb_hdmi_bram_probe','tb_hdmi_bram_stale','tb_camera_live_bram']:
    compile_files = ['hdmi_bram_probe.v', f'{test}.v']
    if test == 'tb_camera_live_bram':
        compile_files = ['camera_live_bram_top.v','hdmi_bram_probe.v','cdc_snapshot.v',
                         (R/'rtl/common/reset_sync.v').as_posix(),
                         (R/'vendor/c_current/01_design_code/video_timing_vtc.v').as_posix(),
                         (D/f'{test}.v').as_posix()]
    sim = ['onerror {quit -f -code 1}', f'transcript file {test}.log',
           f'if {{![file isdirectory work_{test}]}} {{vlib work_{test}}}',
           f'vmap work_{test} work_{test}',
           f'vlog -sv -work work_{test} '+ ' '.join('{'+p+'}' for p in compile_files),
           f'vsim -c -voptargs=+acc -wlf {test}.wlf work_{test}.{test}', 'run -all',
           f'if {{[examine -radix decimal sim:/{test}/test_failed] != 0}} {{quit -f -code 1}}',
           f'if {{[examine -radix decimal sim:/{test}/test_passed] != 1}} {{quit -f -code 1}}',
           'quit -f -code 0']
    (O/f'{test}.do').write_text('\n'.join(sim)+'\n', encoding='utf-8')
manifest = {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[fdc]}
(O/'source_hashes.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
print('Prepared independent-clock raw camera BRAM preview, no original edits.')
