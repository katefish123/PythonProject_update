"""Board-only native payload specialization; generic engine is untouched."""
from pathlib import Path
import argparse
import difflib
import hashlib
import json
import re


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('Unexpected source anchor: '+old)
    return text.replace(old, new)


def transform_core(text):
    text = replace_once(text, 'parameter CAPTURE_BURST_BEATS=8,',
                        'parameter CAPTURE_BURST_BEATS=8,BIST_ONLY_NATIVE_WDATA=0,')
    return replace_once(text, ' assign cmd_wdata=selftest_passed?app_data:test_data;', ''' // Video writes use the independent eight-beat capture/result payload buses.
 // The opt-in board contract reserves native single-beat WDATA for BIST.
 // synthesis translate_off
 initial if(BIST_ONLY_NATIVE_WDATA&&CAPTURE_BURST_BEATS!=8)
  $fatal(1,"BIST_ONLY_NATIVE_WDATA requires CAPTURE_BURST_BEATS=8");
 // synthesis translate_on
 assign cmd_wdata=(BIST_ONLY_NATIVE_WDATA&&CAPTURE_BURST_BEATS==8)?test_data:(selftest_passed?app_data:test_data);''')


def instance_parameters(text, module, instance):
    matches = list(re.finditer(r'\b'+re.escape(module)+r'\s*#\((.*?)\)\s*'+re.escape(instance)+r'\s*\(', text, re.S))
    if len(matches) != 1 or len(re.findall(r'\b'+re.escape(module)+r'\s*#\(', text)) != 1:
        raise ValueError('Expected one '+module+' '+instance+' instance')
    return matches[0].group(1)


def require_capture8(parameters, allow_default=False):
    values = re.findall(r'\.CAPTURE_BURST_BEATS\s*\(([^)]*)\)', parameters)
    if not values and allow_default:
        return
    if len(values) != 1 or values[0].strip() != '8':
        raise ValueError('Expected CAPTURE_BURST_BEATS(8)')


def transform_top(text):
    parameters = instance_parameters(text, 'video_correct_ddr_continuous_core', 'core')
    require_capture8(parameters)
    require_capture8(instance_parameters(text, 'ddr_word_engine_result_burst', 'engine'))
    if 'BIST_ONLY_NATIVE_WDATA' in text:
        raise ValueError('Already specialized top')
    return replace_once(text, 'video_correct_ddr_continuous_core #(',
                        'video_correct_ddr_continuous_core #(.BIST_ONLY_NATIVE_WDATA(1),')


def enable_bench(text):
    # tb_lens_board.sv's actual module is tb_raw_pipeline; only its unique
    # production core parameter list changes. No stimulus/scoreboard edits.
    if len(re.findall(r'\bmodule\s+tb_raw_pipeline\b', text)) != 1:
        raise ValueError('Unexpected lens-board testbench')
    parameters = instance_parameters(text, 'video_correct_ddr_continuous_core', 'dut')
    require_capture8(parameters, allow_default=True)
    require_capture8(instance_parameters(text, 'ddr_word_engine_result_burst', 'engine'))
    if 'BIST_ONLY_NATIVE_WDATA' in text:
        raise ValueError('Already enabled testbench')
    return replace_once(text, 'video_correct_ddr_continuous_core #(',
                        'video_correct_ddr_continuous_core #(.BIST_ONLY_NATIVE_WDATA(1),')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--candidate', type=Path, required=True)
    ap.add_argument('--bench', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    a = ap.parse_args()
    jobs = [(a.candidate/'sources/video_correct_ddr_continuous_core.v', transform_core),
            (a.candidate/'sources/video_correct_ddr_top.v', transform_top),
            (a.bench, enable_bench)]
    # Validate every transformation before creating an output directory.
    transformed = [(p, fn, p.read_text(), fn(p.read_text())) for p, fn in jobs]
    a.output.mkdir(parents=True, exist_ok=False)
    record = {'generator_sha256': sha(Path(__file__)), 'files': {},
              'physical_timing_qualified': False, 'hardware_acceptance': False}
    for p, fn, before, after in transformed:
        target = a.output/p.name
        target.write_text(after)
        (a.output/(p.name+'.diff')).write_text(''.join(difflib.unified_diff(
            before.splitlines(keepends=True), after.splitlines(keepends=True),
            fromfile=str(p), tofile=str(target))))
        record['files'][p.name] = {'source':str(p.resolve()), 'source_sha256':sha(p),
                                   'generated_sha256':sha(target), 'transform':fn.__name__}
    (a.output/'source_binding.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps(record,indent=2))


if __name__ == '__main__':
    main()
