"""Exact RTL affine/lens/sampling regression; no hardware or physical claims."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import math
import random
import re
import shutil
import subprocess
import sys

BASE = Path(__file__).resolve().parent.parent
BREF = Path('C:/D/FPGA/A_software_20261024/reference/B_lens_v2')
PARENT = Path('C:/D/FPGA/A_board_20261029/candidate_de_frame_guard_v2/sources')
TOOLS = Path('C:/modeltech64_2020.4/win64')
sys.path.insert(0, str(BREF / 'python'))
from brect.lens import _map_hardware

sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
S = 1 << 24


def q24(value):
    return int(math.copysign(math.floor(abs(value * S) + 0.5), value))


def rotation(degrees):
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    if degrees % 90 == 0:
        c, s = round(c), round(s)
    cx, cy = 959.5, 539.5
    return [q24(v) for v in [c, s, cx - c * cx - s * cy, -s, c, cy + s * cx - c * cy]]


def pixel(address):
    return (((address * 13 + (address >> 8) + 17) & 255) << 16
            | ((address * 7 + (address >> 3) + 43) & 255) << 8
            | ((address * 3 + (address >> 11) + 97) & 255))


def golden(hw, h, x, y, nearest):
    # Python integers are independent of the RTL's split multipliers/widths.
    nx, ny = h[0] * x + h[1] * y + h[2], h[3] * x + h[4] * y + h[5]
    affine_ok = 0 <= nx < (1 << 36) and 0 <= ny < (1 << 36)
    u, v = (nx >> 16, ny >> 16) if affine_ok else (0, 0)
    sx, sy, lens_ok = _map_hardware(hw, u, v)
    if nearest:
        bx, by = (sx + 128) >> 8, (sy + 128) >> 8
        inside = affine_ok and lens_ok and 0 <= bx < 1920 and 0 <= by < 1080
        ex, ey = bx, by
    else:
        bx, by = sx >> 8, sy >> 8
        inside = affine_ok and lens_ok and 0 <= sx <= 1919 * 256 and 0 <= sy <= 1079 * 256
        ex, ey = min(bx + 1, 1919), min(by + 1, 1079)
    addresses = [by * 1920 + bx, by * 1920 + ex, ey * 1920 + bx, ey * 1920 + ex] if inside else [0] * 4
    fx, fy = (sx & 255, sy & 255) if inside and not nearest else (0, 0)
    tag = (y << 12) | x
    packed = (int(not lens_ok) << 1) | int(inside)
    packed = (packed << 24) | tag
    for address in addresses:
        packed = (packed << 24) | address
    packed = (packed << 16) | (fx << 8) | fy
    values = [pixel(a) for a in addresses]
    rgb = 0
    if inside:
        for channel in range(3):
            p00, p10, p01, p11 = [(p >> (channel * 8)) & 255 for p in values]
            value = ((p00 * (256 - fx) + p10 * fx) * (256 - fy)
                     + (p01 * (256 - fx) + p11 * fx) * fy) >> 16
            rgb |= value << (channel * 8)
    return packed, rgb, {'inside': bool(inside), 'affine_ok': affine_ok, 'lens_ok': bool(lens_ok),
                         'sx_q8': sx, 'sy_q8': sy, 'nx_q24': nx, 'ny_q24': ny}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--candidate', type=Path, default=BASE / 'candidate_host_angle_v1')
    args = ap.parse_args()
    source_dir = args.candidate.resolve() / 'sources'
    out = BASE / 'verification' / ('affine_lens_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir(parents=True)
    print('AFFINE_LENS_CHECK ' + str(out), flush=True)
    binding = BREF / 'examples/r50_18mm_viewport.json'
    profile = json.loads(binding.read_text())
    hw = profile['hardware_parameters']
    safe = profile['H_q24'][:6]
    names = ['lens_affine_instance.v', 'lens_distort_coord.v', 'bilinear_interp.v',
             'perspective_core.v', 'perspective_coord.v', 'scaled_div_pipe.v']
    source_files = [source_dir / n for n in names] + [PARENT / 'lens_autocrop_instance.v']
    # The legacy binding must use the exact frozen underlying datapath sources.
    for name in names[1:]:
        if name=='lens_distort_coord.v':continue  # Exact retiming checked against frozen leaf below.
        assert sha(source_dir / name) == sha(PARENT / name), name
    locked_hashes = {str(p): sha(p) for p in source_files}
    for p in source_files:
        shutil.copyfile(p, out / p.name)
    # Keep the original10-stage leaf and original perspective wrapper independent
    # of a candidate's retimed lens. Compare requests/RGB across their own queues.
    frozen_leaf=out/'lens_distort_coord_frozen.v'
    frozen_leaf.write_text((PARENT/'lens_distort_coord.v').read_text().replace('module lens_distort_coord #(','module lens_distort_coord_frozen #(',1))
    frozen_core=out/'perspective_core_frozen.v'
    frozen_core.write_text((PARENT/'perspective_core.v').read_text().replace('module perspective_core #(','module perspective_core_frozen #(',1).replace('lens_distort_coord #(','lens_distort_coord_frozen #(',1))
    legacy=out/'lens_autocrop_instance.v';legacy.write_text(legacy.read_text().replace('perspective_core #(','perspective_core_frozen #(',1))
    checker = Path(__file__).resolve()
    shutil.copyfile(checker, out / 'checker_snapshot.py')
    rng = random.Random(20261030)
    native = [(x, y) for y in [0, 1, 2, 538, 539, 540, 1077, 1078, 1079]
              for x in [0, 1, 2, 958, 959, 960, 1917, 1918, 1919]]
    native += [(rng.randrange(1920), rng.randrange(1080)) for _ in range(239)]
    wide = [(x, y) for x in [0, 1, 1919, 1920, 2047, 2048, 4094, 4095]
            for y in [0, 1, 1079, 1080, 2047, 4095]]
    wide += [(rng.randrange(4096), rng.randrange(4096)) for _ in range(80)]
    cases = [('safe_crop', safe, native, True)]
    cases += [(f'rotation_{angle}_allow_outside', rotation(angle), native + wide, False)
              for angle in [0, 15, 45, 90, 180, 270]]
    cases += [
        ('negative_translation', [S, 0, -16 * S, 0, S, -8 * S], native + wide, False),
        ('signed40_extremes', [(1 << 39) - 1, -(1 << 39), (1 << 39) - 1,
                              -(1 << 39), (1 << 39) - 1, -(1 << 39)], wide, False),
        ('negative_sub_q8', [0, 0, -1, 0, 0, 500 * S], wide[:32], False),
        ('just_below_4096', [0, 0, (1 << 36) - 1, 0, 0, 500 * S], wide[:32], False),
        ('at_4096_rejected', [0, 0, 1 << 36, 0, 0, 500 * S], wide[:32], False),
        ('lens_normalization_error', [0, 0, 4000 * S, 0, 0, 4095 * S], wide[:32], False),
    ]
    # Invert only to locate stimuli near actual observed-image sampling borders.
    # Golden results still use the independent forward B model for every point.
    border_stimuli = []
    for target_x, target_y in [(0, 500 * 256), (-1, 500 * 256), (-128, 500 * 256),
                               (1919 * 256, 500 * 256), (1919 * 256 + 127, 500 * 256),
                               (500 * 256, 0), (500 * 256, 1079 * 256), (500 * 256, 1079 * 256 + 127)]:
        u, v = max(target_x, 0), max(target_y, 0)
        for _ in range(16):
            sx, sy, valid = _map_hardware(hw, u, v)
            assert valid
            u += target_x - sx
            v += target_y - sy
        choices = []
        for du in range(-3, 4):
            for dv in range(-3, 4):
                if 0 <= u + du < (1 << 20) and 0 <= v + dv < (1 << 20):
                    sx, sy, valid = _map_hardware(hw, u + du, v + dv)
                    if valid:
                        choices.append((abs(sx - target_x) + abs(sy - target_y), u + du, v + dv, sx, sy))
        best = min(choices)
        border_stimuli.append({'target_q8': [target_x, target_y], 'ideal_q8': list(best[1:3]),
                               'mapped_q8': list(best[3:5]), 'l1_error_q8': best[0]})
        cases.append((f'border_{target_x}_{target_y}', [0, 0, best[1] << 16, 0, 0, best[2] << 16], native[:32], False))

    entries, frames, stats = [], [], []
    # Two initial batches will be interrupted by reset at different pipeline ages.
    for i in range(32):
        x, y = 1400 + i, 700 + i
        request, rgb, info = golden(hw, safe, x, y, False)
        entries.append((x | (y << 12), request, rgb))
    for name, h, points, legacy in cases:
        assert all(-(1 << 39) <= q < (1 << 39) for q in h)
        for nearest in [False, True]:
            start = len(entries)
            coverage = {'inside': 0, 'outside': 0, 'affine_rejected': 0, 'lens_errors': 0}
            for x, y in points:
                request, rgb, info = golden(hw, h, x, y, nearest)
                entries.append((x | (y << 12), request, rgb))
                coverage['inside' if info['inside'] else 'outside'] += 1
                coverage['affine_rejected'] += not info['affine_ok']
                coverage['lens_errors'] += not info['lens_ok']
            frames.append({'name': name, 'nearest': nearest, 'affine_q24': h, 'start': start,
                           'count': len(points), 'legacy_crosscheck': legacy, 'coverage': coverage})
    assert len(entries) > 3000
    for name, field, digits in [('input_tags.hex', 0, 6), ('expected_requests.hex', 1, 35), ('expected_rgb.hex', 2, 6)]:
        (out / name).write_text(''.join(f'{entry[field]:0{digits}x}\n' for entry in entries))
    matrix_setup = '\n'.join(f"  matrices[{i}]=240'h{sum((v & ((1 << 40) - 1)) << (j * 40) for j, v in enumerate(f['affine_q24'])):060x};"
                             for i, f in enumerate(frames))
    dispatch = '\n'.join(f"  run_frame({i},{f['start']},{f['count']},{int(f['nearest'])},{int(f['legacy_crosscheck'])});" for i, f in enumerate(frames))
    safe_packed = sum((v & ((1 << 40) - 1)) << (j * 40) for j, v in enumerate(safe))
    bench = r'''`timescale 1ns/1ps
module tb_affine_lens;
 reg clk=0,rst_n=0,in_valid=0,nearest=0,cross_enable=0;
 always #6.734 clk=~clk;
 reg[239:0]affine;reg[11:0]dst_x=0,dst_y=0;
 wire req_valid,req_inside,req_error,out_valid;wire[23:0]req_tag,addr00,addr10,addr01,addr11,out_rgb,out_tag;wire[7:0]req_fx,req_fy;
 wire l_req_valid,l_req_inside,l_req_error,l_out_valid;wire[23:0]l_req_tag,l_addr00,l_addr10,l_addr01,l_addr11,l_out_rgb,l_out_tag;wire[7:0]l_req_fx,l_req_fy;
 reg rsp_valid=0,rsp_inside=0,l_rsp_valid=0,l_rsp_inside=0;
 reg[23:0]rsp_tag=0,p00=0,p10=0,p01=0,p11=0,l_rsp_tag=0,l_p00=0,l_p10=0,l_p01=0,l_p11=0;
 reg[7:0]rsp_fx=0,rsp_fy=0,l_rsp_fx=0,l_rsp_fy=0;
 lens_affine_instance dut(.*);
 lens_autocrop_instance legacy(.clk(clk),.rst_n(rst_n),.in_valid(in_valid&&cross_enable),.nearest(nearest),.dst_x(dst_x),.dst_y(dst_y),
 .req_valid(l_req_valid),.req_inside(l_req_inside),.req_error(l_req_error),.req_tag(l_req_tag),
 .addr00(l_addr00),.addr10(l_addr10),.addr01(l_addr01),.addr11(l_addr11),.req_fx(l_req_fx),.req_fy(l_req_fy),
 .rsp_valid(l_rsp_valid),.rsp_inside(l_rsp_inside),.rsp_tag(l_rsp_tag),.p00(l_p00),.p10(l_p10),.p01(l_p01),.p11(l_p11),.rsp_fx(l_rsp_fx),.rsp_fy(l_rsp_fy),
 .out_valid(l_out_valid),.out_rgb(l_out_rgb),.out_tag(l_out_tag));
 reg[23:0]tags[0:@LAST@],expected_rgb[0:@LAST@];reg[137:0]expected_request[0:@LAST@];reg[239:0]matrices[0:@FRAME_LAST@];
 integer request_queue[$],output_queue[$],legacy_request_queue[$],legacy_output_queue[$];
 integer drive_index=0,sent=0,requests=0,outputs=0,legacy_requests=0,legacy_outputs=0,cancel_req=0,cancel_out=0;
 integer accepted=0,rejected=0,numerical_errors=0,bubbles=0,resets=0;reg[31:0]rng=32'h5e97ad34;
 function[23:0]pixel(input[23:0]a);reg[7:0]r,g,b;begin
  r=a*13+(a>>8)+17;g=a*7+(a>>3)+43;b=a*3+(a>>11)+97;pixel={r,g,b};end endfunction
 integer index,ignored;
 always @(posedge clk)begin
  if(!rst_n)begin
   cancel_req=cancel_req+request_queue.size();cancel_out=cancel_out+output_queue.size();
   request_queue.delete();output_queue.delete();legacy_request_queue.delete();legacy_output_queue.delete();
   rsp_valid<=0;rsp_inside<=0;l_rsp_valid<=0;l_rsp_inside<=0;
  end else begin
   if(in_valid)begin request_queue.push_back(drive_index);sent=sent+1;if(cross_enable)legacy_request_queue.push_back(drive_index);end
   else bubbles=bubbles+1;
   if(req_valid)begin
    if(request_queue.size()==0)$fatal(1,"AFFINE_UNEXPECTED_REQUEST");index=request_queue.pop_front();
    if({req_error,req_inside,req_tag,addr00,addr10,addr01,addr11,req_fx,req_fy}!==expected_request[index])
     $fatal(1,"AFFINE_REQUEST_MISMATCH index=%0d actual=%h expected=%h",index,{req_error,req_inside,req_tag,addr00,addr10,addr01,addr11,req_fx,req_fy},expected_request[index]);
    requests=requests+1;output_queue.push_back(index);
    if(req_inside)accepted=accepted+1;else rejected=rejected+1;
    if(req_error)numerical_errors=numerical_errors+1;
   end
   if(out_valid)begin
    if(output_queue.size()==0)$fatal(1,"AFFINE_UNEXPECTED_RGB");index=output_queue.pop_front();
    if(out_tag!==tags[index]||out_rgb!==expected_rgb[index])$fatal(1,"AFFINE_RGB_MISMATCH index=%0d tag=%h rgb=%h expectedtag=%h expectedrgb=%h",index,out_tag,out_rgb,tags[index],expected_rgb[index]);
    outputs=outputs+1;
   end
   if(l_req_valid)begin
    if(legacy_request_queue.size()==0)$fatal(1,"LEGACY_UNEXPECTED_REQUEST");index=legacy_request_queue.pop_front();
    if({l_req_error,l_req_inside,l_req_tag,l_addr00,l_addr10,l_addr01,l_addr11,l_req_fx,l_req_fy}!==expected_request[index])$fatal(1,"LEGACY_REQUEST_MISMATCH index=%0d",index);
    legacy_requests=legacy_requests+1;legacy_output_queue.push_back(index);
   end
   if(l_out_valid)begin
    if(legacy_output_queue.size()==0)$fatal(1,"LEGACY_UNEXPECTED_RGB");index=legacy_output_queue.pop_front();
    if(l_out_tag!==tags[index]||l_out_rgb!==expected_rgb[index])$fatal(1,"LEGACY_RGB_MISMATCH index=%0d",index);
    legacy_outputs=legacy_outputs+1;
   end
   rsp_valid<=req_valid;rsp_inside<=req_inside;rsp_tag<=req_tag;rsp_fx<=req_fx;rsp_fy<=req_fy;
   p00<=pixel(addr00);p10<=pixel(addr10);p01<=pixel(addr01);p11<=pixel(addr11);
   l_rsp_valid<=l_req_valid;l_rsp_inside<=l_req_inside;l_rsp_tag<=l_req_tag;l_rsp_fx<=l_req_fx;l_rsp_fy<=l_req_fy;
   l_p00<=pixel(l_addr00);l_p10<=pixel(l_addr10);l_p01<=pixel(l_addr01);l_p11<=pixel(l_addr11);
  end
 end
 task reset;begin
  @(negedge clk);in_valid=0;rst_n=0;cross_enable=0;repeat(3)@(negedge clk);rst_n=1;resets=resets+1;
  repeat(80)begin @(negedge clk);if(req_valid||out_valid||l_req_valid||l_out_valid)$fatal(1,"AFFINE_RESET_LEAK");end
 end endtask
 task send(input integer n);begin
  @(negedge clk);drive_index=n;dst_x=tags[n][11:0];dst_y=tags[n][23:12];in_valid=1;
 end endtask
 task drain;begin
  @(negedge clk);in_valid=0;repeat(100)@(negedge clk);
  if(request_queue.size()||output_queue.size()||legacy_request_queue.size()||legacy_output_queue.size())$fatal(1,"AFFINE_MISSING_TRANSACTION");
 end endtask
 task run_frame(input integer c,start,count,mode,legacy_mode);begin
  affine=matrices[c];nearest=mode;cross_enable=legacy_mode;
  for(integer n=start;n<start+count;n=n+1)begin
   rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
   if(rng[1:0]==0)begin @(negedge clk);in_valid=0;dst_x=rng[11:0];dst_y=rng[23:12];repeat(rng[3:2])@(negedge clk);end
   send(n);
  end
  drain();$display("AFFINE_FRAME_PASS case=%0d requests=%0d mode=%0d legacy=%0d",c,count,mode,legacy_mode);
 end endtask
 initial begin
  $readmemh("input_tags.hex",tags);$readmemh("expected_requests.hex",expected_request);$readmemh("expected_rgb.hex",expected_rgb);
 @MATRICES@
  affine=240'h@SAFE@;reset();for(integer n=0;n<8;n=n+1)send(n);reset();
  for(integer n=8;n<32;n=n+1)send(n);reset();
 @DISPATCH@
  if(sent!=@POINTS@||requests+cancel_req!=sent||outputs+cancel_out!=requests||requests<3000||outputs<3000||accepted<1000||rejected<100||numerical_errors<20||cancel_req<8||cancel_out<1||legacy_requests<500||legacy_requests!=legacy_outputs||bubbles<100)
   $fatal(1,"AFFINE_COVERAGE sent=%0d req=%0d out=%0d cancelled=%0d/%0d inside=%0d outside=%0d numerical=%0d legacy=%0d bubbles=%0d",sent,requests,outputs,cancel_req,cancel_out,accepted,rejected,numerical_errors,legacy_requests,bubbles);
  $display("AFFINE_LENS_PASS sent=%0d requests=%0d rgb=%0d inside=%0d outside=%0d numerical_errors=%0d reset_cancelled_requests=%0d reset_cancelled_rgb=%0d legacy_requests=%0d legacy_rgb=%0d bubbles=%0d resets=%0d",sent,requests,outputs,accepted,rejected,numerical_errors,cancel_req,cancel_out,legacy_requests,legacy_outputs,bubbles,resets);$finish;
 end
 initial begin #2000000;$fatal(1,"AFFINE_TIMEOUT");end
endmodule
'''.replace('@LAST@', str(len(entries) - 1)).replace('@FRAME_LAST@', str(len(frames) - 1)).replace('@MATRICES@', matrix_setup).replace('@SAFE@', f'{safe_packed:060x}').replace('@DISPATCH@', dispatch).replace('@POINTS@', str(len(entries)))
    test = out / 'tb_affine_lens.sv'
    test.write_text(bench)
    inputs = {'source_candidate': str(args.candidate.resolve()), 'target_rtl_sha256': sha(source_dir / names[0]),
              'input_sha256': locked_hashes | {str(p): sha(p) for p in [binding, *sorted((BREF / 'python/brect').glob('*.py'))]},
              'snapshot_sha256': {str(out / p.name): sha(out / p.name) for p in source_files},
              'frozen_comparator_inputs_sha256': {str(p):sha(p) for p in [PARENT/'lens_distort_coord.v',PARENT/'perspective_core.v']},
              'frozen_comparator_generated_sha256': {str(p):sha(p) for p in [frozen_leaf,frozen_core]},
              'checker_sha256': sha(checker), 'testbench_sha256': sha(test),
              'vector_sha256': {str(out / name): sha(out / name) for name in ['input_tags.hex', 'expected_requests.hex', 'expected_rgb.hex']},
              'point_count': len(entries), 'frames': frames, 'border_stimuli': border_stimuli,
              'reference': 'B brect.lens._map_hardware with exact Python integer affine multiply/add/shift and RGB UQ0.8 bilinear arithmetic',
              'affine_outside_contract': 'Geometric affine rejection carries invalid tag -> req_inside false and black. req_error reflects lens numerical error only, exactly as current RTL.',
              'hardware_accessed': False}
    (out / 'inputs.json').write_text(json.dumps(inputs, indent=2))
    ini = out / 'modelsim.ini'
    shutil.copyfile(TOOLS.parent / 'modelsim.ini', ini)
    def run(argv, name):
        with (out / name).open('w') as log:
            result = subprocess.run([p.as_posix() if isinstance(p, Path) else str(p) for p in argv], cwd=out,
                                    stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        if result.returncode:
            raise RuntimeError(str(out / name))
    run([TOOLS / 'vlib.exe', out / 'work'], 'library.log')
    run([TOOLS / 'vmap.exe', '-modelsimini', ini, 'work', out / 'work'], 'mapping.log')
    run([TOOLS / 'vlog.exe', '-sv', '-modelsimini', ini, *[out / p.name for p in source_files], frozen_leaf, frozen_core, test], 'compile.log')
    (out / 'run.do').write_text('onerror {quit -code 2 -f}\nonbreak {resume}\nonfinish stop\nrun -all\nquit -f\n')
    try:
        run([TOOLS / 'vsim.exe', '-modelsimini', ini, '-c', 'work.tb_affine_lens', '-do', out / 'run.do'], 'simulation.log')
    except RuntimeError:
        pass
    log = (out / 'simulation.log').read_text(errors='replace')
    compiled = (out / 'compile.log').read_text(errors='replace')
    passed = 'AFFINE_LENS_PASS' in log and not re.search(r'\*\* (?:Fatal|Error|Warning)(?:\s|:)', log + compiled)
    for p, h in inputs['input_sha256'].items():
        assert sha(p) == h
    result = {'passed': passed, 'hardware_accessed': False, 'input_manifest_sha256': sha(out / 'inputs.json'),
              'simulation_log_sha256': sha(out / 'simulation.log'), 'compile_log_sha256': sha(out / 'compile.log'),
              'observations': [line for line in log.splitlines() if '_PASS' in line or '** Fatal' in line or '** Error' in line or '** Warning' in line]}
    (out / 'verification.json').write_text(json.dumps(result, indent=2))
    print(json.dumps({'directory': str(out), **result}, indent=2))
    raise SystemExit(0 if passed else 1)


if __name__ == '__main__':
    main()
