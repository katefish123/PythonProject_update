"""Full native RGB/DDR/HDMI oracle for the controlled affine/lens candidate.

Uses the proven independent source ownership, DDR write and HDMI pixel scoreboard.
Fresh frame deadlines are enforced under explicit DDR service delays. No hardware.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
CANDIDATE = ROOT / 'candidate_host_angle_v1'
TOOLS = Path('C:/modeltech64_2020.4/win64')
ORIGINAL = Path('C:/D/FPGA/A_software_20261024/candidate_30fps/sim/tb_1080p30.sv')
BREF = Path('C:/D/FPGA/A_software_20261024/reference/B_lens_v2')
sys.path.insert(0, 'C:/D/FPGA/A_software_20261024/deps')
sys.path.insert(0, str(BREF / 'python'))
import cv2
import numpy as np
from brect.calibration import load_calibration
from brect.viewport import fixed_grid
from send_lens_angle import affine_for_angle, plan_lens_viewport, hardware_binding

sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()


def run(argv, folder, name):
    with (folder / name).open('w', encoding='utf-8') as out:
        p = subprocess.run([v.as_posix() if isinstance(v, Path) else str(v) for v in argv],
                           cwd=folder, stdout=out, stderr=subprocess.STDOUT,
                           creationflags=subprocess.CREATE_NO_WINDOW)
    if p.returncode:
        raise RuntimeError(str(folder / name))


def write_rgb(path, image):
    rgb = image.astype(np.uint32)
    packed = (rgb[:, :, 2] << 16) | (rgb[:, :, 1] << 8) | rgb[:, :, 0]
    with path.open('w') as f:
        f.writelines('%06x\n' % int(v) for v in packed.ravel())


def fixtures(folder, angle, nearest):
    calibration = ROOT / 'calibration/r50_18mm_hdmi_trial.json'
    profile = load_calibration(calibration, (1920, 1080))
    plan = plan_lens_viewport(affine_for_angle(angle, 1, safe_crop=False), calibration, False)
    binding = hardware_binding(calibration, CANDIDATE, [1920, 1080])
    assert binding['compatible']
    H = plan['matrix']
    src = BREF / 'examples/real_18mm_input.png'
    image = cv2.imread(str(src))
    assert image is not None and image.shape == (1080, 1920, 3)
    result = np.zeros_like(image)
    valid_count = 0
    for first in range(0, 1080, 32):
        xx, yy = np.meshgrid(np.arange(1920), np.arange(first, min(first + 32, 1080)))
        sx, sy, valid = fixed_grid(profile, H, xx, yy)
        if nearest:
            bx, by = (sx + 128) >> 8, (sy + 128) >> 8
            valid &= (bx >= 0) & (by >= 0) & (bx < 1920) & (by < 1080)
            block = image[np.clip(by, 0, 1079), np.clip(bx, 0, 1919)].copy()
        else:
            valid &= (sx >= 0) & (sy >= 0) & (sx <= 1919 * 256) & (sy <= 1079 * 256)
            bx, by = np.clip(sx >> 8, 0, 1919), np.clip(sy >> 8, 0, 1079)
            ex, ey = np.minimum(bx + 1, 1919), np.minimum(by + 1, 1079)
            fx, fy = (sx & 255)[..., None], (sy & 255)[..., None]
            top = image[by, bx].astype(np.int64) * (256 - fx) + image[by, ex].astype(np.int64) * fx
            bot = image[ey, bx].astype(np.int64) * (256 - fx) + image[ey, ex].astype(np.int64) * fx
            block = ((top * (256 - fy) + bot * fy) >> 16).astype(np.uint8)
        block[~valid] = 0
        result[first:first + len(yy)] = block
        valid_count += int(valid.sum())
    assert valid_count == 1920 * 1080
    write_rgb(folder / 'source.hex', image)
    write_rgb(folder / 'expected.hex', result)
    q = plan['coefficients_q24'] + [0, 0, 1 << 24]
    (folder / 'H40.hex').write_text(''.join('%010x\n' % (n & ((1 << 40) - 1)) for n in q))
    cv2.imwrite(str(folder / 'expected.png'), result)
    record = {'scope': 'Actual B trial input image; exact independent integer inverse affine/lens and one RGB resample oracle. Not a measured hardware output.',
              'angle_plan': plan, 'hardware_binding': binding, 'source_image': str(src), 'source_image_sha256': sha(src),
              'valid_pixels': valid_count, 'nearest': nearest,
              'reference_sha256': {str(p): sha(p) for p in [BREF/'python/brect/viewport.py', BREF/'python/brect/calibration.py', BREF/'python/brect/lens.py']},
              'files': {name: sha(folder/name) for name in ['source.hex', 'expected.hex', 'H40.hex', 'expected.png']}}
    (folder/'fixtures.json').write_text(json.dumps(record, indent=2))
    return plan


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--angle-deg', type=float, default=0)
    ap.add_argument('--frames', type=int, default=6)
    ap.add_argument('--raw', action='store_true')
    ap.add_argument('--nearest', action='store_true')
    ap.add_argument('--measurement-only', action='store_true')
    ap.add_argument('--pixel-phase-ns', type=int, default=0)
    a = ap.parse_args()
    if a.frames < 3 or a.pixel_phase_ns < 0:
        ap.error('Need at least three frames and nonnegative phase')
    folder = ROOT/'verification'/('video_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    folder.mkdir()
    print('LENS_VIDEO_RUN '+str(folder), flush=True)
    shutil.copyfile(Path(__file__), folder/'checker_snapshot.py')
    source_hashes = {p.name: sha(p) for p in (CANDIDATE/'sources').iterdir() if p.is_file()}
    plan = fixtures(folder, a.angle_deg, a.nearest)
    text = ORIGINAL.read_text()
    def replace(old, new):
        nonlocal text
        if text.count(old) != 1:
            raise RuntimeError('Fixture mismatch: '+old)
        text = text.replace(old, new, 1)
    replace('parameter NATIVE=1,FRAMES=2,', 'parameter WRITE_DELAY=18,READ_DELAY=28,CAPTURE_BEATS=16,NATIVE=1,FRAMES=6,')
    replace('always #6.734007 proc_clk=~proc_clk;', 'always #5.387205387 proc_clk=~proc_clk;')
    replace('.PROC_CYCLES_PER_MS(74250)', '.PROC_CYCLES_PER_MS(92813)')
    replace('wire recovered_vs;hdmi_vs_recover recover(', 'wire recovered_vs;hdmi_vs_recover #(.PREFER_DE_FRAME(1),.FRAME_ACTIVE_PIXELS(SW)) recover(')
    replace('video_correct_ddr_continuous_core #(.BIST_ONLY_NATIVE_WDATA(1),',
            'video_correct_ddr_continuous_core #(.RUNTIME_AFFINE(1),.TILED_ORDER(1),.SOURCE_CACHE_LINES(128),.CAPTURE_BURST_BEATS(CAPTURE_BEATS),.BIST_ONLY_NATIVE_WDATA(1),')
    coeff = plan['coefficients_q24']
    packed = sum((n & ((1 << 40) - 1)) << (40*i) for i, n in enumerate(coeff))
    replace('wire[2047:0]burst_payload,source_block_payload,result_block_payload;',
            'wire[CAPTURE_BEATS*256-1:0]burst_payload;wire[2047:0]source_block_payload,result_block_payload;wire[4095:0]source_line_payload;\n'
            f" localparam[239:0]AFFINE=240'h{packed:060x};reg cfg_valid=1;wire cfg_ready,commit_valid;wire[15:0]commit_sequence;integer commits=0;\n"
            ' always @(posedge proc_clk)if(rst_n)begin\n'
            ' if(cfg_valid&&cfg_ready)cfg_valid<=0;\n'
            ' if(commit_valid)begin if(commit_sequence!=77||commits!=0)$fatal(1,"FRAME_COMMIT_MISMATCH");commits++;end\n end')
    replace('.proc_clk(proc_clk),.proc_rst_n(rst_n),',
            ".cfg_valid(cfg_valid),.cfg_ready(cfg_ready),.cfg_affine(AFFINE),.cfg_sequence(16'd77),.commit_valid(commit_valid),.commit_sequence(commit_sequence),.proc_clk(proc_clk),.proc_rst_n(rst_n),")
    replace('.CAPTURE_BURST_BEATS(8)', '.CAPTURE_BURST_BEATS(CAPTURE_BEATS)')
    replace('.SOURCE_PREFETCH_ENABLE(1)', '.SOURCE_PREFETCH_ENABLE(0)')
    assert text.count('.rsp_source_block(source_block_payload)') == 2
    text = text.replace('.rsp_source_block(source_block_payload)', '.rsp_source_block(source_block_payload),.rsp_source_line(source_line_payload)')
    replace('wire wready=rst_n&&(ui_tick%11!=0),awready=rst_n&&(ui_tick%17>=2),arready=rst_n&&!read_pending&&(ui_tick%7!=0);',
            'integer write_delay=0,write_transaction=0;\n wire wready=rst_n&&write_pending&&write_delay==0,awready=rst_n&&!write_pending,arready=rst_n&&!read_pending;')
    replace('read_delay<=28+((reads%128==127)?100:0);', 'read_delay<=READ_DELAY+((reads%128==127)?100:0);')
    replace('ui_tick++;', 'ui_tick++;if(write_pending&&write_delay>0)write_delay<=write_delay-1;')
    replace('write_pending<=1;write_base<=awaddr;write_index<=0;write_total<=awlen+1;',
            'write_pending<=1;write_base<=awaddr;write_index<=0;write_total<=awlen+1;write_delay<=WRITE_DELAY+((write_transaction%128==127)?100:0);write_transaction++;')
    replace('always #6.734007 pix_clk=~pix_clk;', f'initial begin #{a.pixel_phase_ns};forever #6.734007 pix_clk=~pix_clk;end')
    if a.nearest:
        replace(".nearest(1'b0)", ".nearest(1'b1)")
    if a.measurement_only:
        replace('if(fresh_swaps>=2&&$time-last_fresh_time>33333500)', "if(1'b0&&fresh_swaps>=2&&$time-last_fresh_time>33333500)")
    replace('if(dut.stream_path.processor.FIXED_IDENTITY!=1)$fatal(1,"B_LENS_TRIAL_NOT_CONNECTED");',
            'if(dut.stream_path.processor.RUNTIME_AFFINE!=1||dut.stream_path.processor.TILED_ORDER!=1||dut.stream_path.cache.LINES!=128)$fatal(1,"RUNTIME_TILED_LENS_NOT_CONNECTED");')
    start = text.index(' $readmemh(')
    end = text.index(' bank_id[0]=0;', start)
    loads = []
    for filename, arrays in [('source.hex', ['source_fixture', 'source_alt']), ('expected.hex', ['expected_fixture', 'expected_alt']), ('H40.hex', ['expected_h', 'expected_h_alt'])]:
        for array in arrays:
            loads.append(f' $readmemh("{(folder/filename).as_posix()}",{array});')
    text = text[:start] + '\n'.join(loads) + '\n' + text[end:]
    replace('$display("FRESH30_RESULT', 'if(CORRECTED&&commits!=1)$fatal(1,"NO_COMMITTED_ANGLE");\n $display("FRESH30_RESULT')
    replace('PASS RAW_PIPELINE', 'PASS LENS_ANGLE_VIDEO')
    instrumentation = r'''
 time process_start=0;integer source_reads=0,result_writes=0,last_source_reads=0,last_result_writes=0;
 always @(posedge ui_clk)if(rst_n&&cmd_v&&cmd_r)begin
  if(!cmd_w&&source_block_cmd)source_reads++;
  if(cmd_w&&result_block_cmd)result_writes++;
 end
 always @(posedge proc_clk)if(rst_n)begin
  if(dut.start)begin process_start=$time;$display("ANGLE_FRAME_START id=%0d time_ns=%0d",dut.descriptor_generation,$time);end
  if(dut.p_done)begin
   $display("ANGLE_FRAME_DONE id=%0d elapsed_ns=%0d source_blocks=%0d result_blocks=%0d",dut.processing_frame_id,$time-process_start,source_reads-last_source_reads,result_writes-last_result_writes);
   last_source_reads=source_reads;last_result_writes=result_writes;
  end
 end
'''
    replace('endmodule', instrumentation+'\nendmodule')
    test = folder/'tb_lens_video.sv'
    test.write_text(text)
    excluded = {'ddr3_ip.v','ddr3_ip_ddrphy_top.v','ddr3_ip_slice_top_v1_10.v','config_pll_27m_10m.v','video_pll_27m_148m5.v'}
    files = sorted(p for p in (CANDIDATE/'sources').glob('*.v') if p.name not in excluded)
    ini = folder/'modelsim.ini'
    shutil.copyfile(TOOLS.parent/'modelsim.ini', ini)
    run([TOOLS/'vlib.exe', folder/'work'], folder, 'library.log')
    run([TOOLS/'vmap.exe','-modelsimini',ini,'work',folder/'work'], folder, 'mapping.log')
    run([TOOLS/'vlog.exe','-sv','-modelsimini',ini,*files,test], folder, 'compile.log')
    do = folder/'run.do'
    do.write_text('onerror {quit -code 2 -f}\nonbreak {resume}\nonfinish stop\nrun -all\nquit -f\n')
    started = time.time()
    failure = None
    try:
        run([TOOLS/'vsim.exe','-modelsimini',ini,'-c','-voptargs=+acc=r+tb_raw_pipeline',
             '-gFRAMES='+str(a.frames),'-gCORRECTED='+str(int(not a.raw)), '-gRGB_PATTERN='+str(int(a.raw)),
             'work.tb_raw_pipeline','-do',do], folder, 'simulation.log')
    except RuntimeError as e:
        failure = str(e)
    output = (folder/'simulation.log').read_text(errors='replace')
    compiled = (folder/'compile.log').read_text(errors='replace')
    stable = source_hashes == {p.name: sha(p) for p in (CANDIDATE/'sources').iterdir() if p.is_file()}
    clean = not re.search(r'\*\* (?:Fatal|Error|Warning)(?:\s|:)', output+compiled)
    passed = 'PASS LENS_ANGLE_VIDEO' in output and clean and stable and failure is None
    match = re.search(r'FRESH30_RESULT swaps=(\d+) first_ns=(\d+) last_ns=(\d+) max_gap_ns=(\d+)', output)
    fresh = dict(zip(['swaps','first_ns','last_ns','max_gap_ns'],map(int,match.groups()))) if match else None
    if fresh:
        fresh['observed_fps'] = (fresh['swaps']-1)*1e9/(fresh['last_ns']-fresh['first_ns'])
    observations = [line for line in output.splitlines() if any(k in line for k in ['ANGLE_FRAME_', 'FRESH', 'PUBLICATION','PASS ', '** Fatal', '** Error', '** Warning'])]
    record = {'passed': passed, 'qualifies_simulated_30fps': bool(passed and not a.measurement_only and a.frames>=6 and fresh and fresh['max_gap_ns']<=33333500),
              'hardware_accessed': False, 'scope': __doc__, 'parameters': vars(a), 'candidate': str(CANDIDATE),
              'source_sha256': source_hashes, 'sources_unchanged': stable, 'freshness': fresh,
              'original_bench_sha256': sha(ORIGINAL), 'bench_sha256': sha(test), 'checker_sha256': sha(Path(__file__)),
              'fixtures_sha256': sha(folder/'fixtures.json'), 'simulation_log_sha256': sha(folder/'simulation.log'),
              'compile_log_sha256': sha(folder/'compile.log'), 'elapsed_seconds': time.time()-started,
              'observations': observations, 'failure': failure,
              'ddr_service': {'read_ui_cycles':28,'write_ui_cycles':18,'spike_period_transactions':128,'spike_ui_cycles':100,'ui_mhz':125,'rx_mhz':148.5,'processing_mhz':92.8125,'output_mhz':74.25}}
    (folder/'verification.json').write_text(json.dumps(record, indent=2))
    print(json.dumps({k:record[k] for k in ['passed','qualifies_simulated_30fps','freshness','elapsed_seconds','failure','observations']},indent=2),flush=True)
    raise SystemExit(0 if passed else 1)


if __name__ == '__main__':
    main()
