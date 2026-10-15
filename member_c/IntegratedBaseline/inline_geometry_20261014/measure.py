"""Compare identical black-marker scenes with DDR scan vs RX-side detection."""
import argparse, json, re
from pathlib import Path


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    candidate = a.root / 'diagnostics/ddr_camera_hires_prefetch_20261012/results'
    qualification = json.loads((candidate / 'reproduced_simulation_qualification.json').read_text(encoding='utf-8-sig'))
    if qualification.get('status') != 'passed':
        raise RuntimeError('Complete qualified regression required')
    results = []
    for case, inline in [(2, 0), (3, 1)]:
        name = f'tb_fullhd_pipeline_{case}'
        text = (candidate / (name + '.reproduction.log')).read_text(encoding='utf-8-sig')
        config = re.search(r'FULLHD_PIPELINE_CONFIG overlap=(\d+) prefetch=(\d+) late_percent=(\d+) inline=(\d+)', text)
        passed = re.search(r'FULLHD_PIPELINE_PASS .*frames=(\d+) corrected_pixels=(\d+) display_pixels=(\d+) average_start_interval_cycles=(\d+) max_ui_wait=(\d+) overlap_beats=(\d+) native_reads=(\d+)', text)
        if not config or tuple(map(int, config.groups())) != (1, 1, 95, inline):
            raise RuntimeError('Configuration mismatch')
        if not passed or 'VERIFIED_PASS_BIT=1' not in text:
            raise RuntimeError('Verified native result missing')
        frames, pixels, display, interval, wait, overlap, reads = map(int, passed.groups())
        begins = re.findall(r'FULLHD_FRAME_BEGIN .*frame=(\d+) source_bank=(\d+) kind=(\d+).*source_age_ns=(\d+)', text)
        ages = [int(row[3]) / 1e6 for row in begins]
        pubages = [int(v) / 1e6 for v in re.findall(r'FULLHD_FRAME_PUBLISH .*image_age_ns=(\d+)', text)]
        phases = []
        for row in re.findall(r'FULLHD_PHASE_PROFILE .*frame=(\d+) scan=(\d+) solve=(\d+) read=(\d+) interp=(\d+) write=(\d+) other=(\d+) processing_ns=(\d+)', text):
            f, scan, solve, read, interp, write, other, ns = map(int, row)
            phases.append(dict(frame=f, scan_cycles=scan, solve_cycles=solve,
                               neighborhood_read_cycles=read, interpolation_cycles=interp,
                               write_cycles=write, other_cycles=other, processing_ms=ns/1e6))
        if (frames, pixels, display) != (3, 1735680, 1735680) or len(phases) != 3 or len(pubages) != 3:
            raise RuntimeError('Incomplete pixel/display evidence')
        if [int(r[2]) for r in begins] != [0, 1, 2] or [int(r[1]) for r in begins] != [0, 1, 0]:
            raise RuntimeError('Distinct alternating-bank generations not verified')
        if inline and (any(row['scan_cycles'] for row in phases) or max(ages) > 50):
            raise RuntimeError('Scan bypass/freshness acceptance failed')
        results.append(dict(mode='capture_geometry' if inline else 'ddr_scan',
                            average_start_interval_ms=interval/27000,
                            three_frame_sample_rate_per_second=27000000/interval,
                            corrected_pixels=pixels, display_pixels=display,
                            source_age_ms=ages, image_age_at_publish_ms=pubages,
                            max_ui_wait_cycles=wait, overlap_beats=overlap,
                            native_reads=reads, phase_profiles=phases))
    old, new = results
    if new['average_start_interval_ms'] >= old['average_start_interval_ms']:
        raise RuntimeError('Native frame interval did not improve')
    if max(new['image_age_at_publish_ms']) >= max(old['image_age_at_publish_ms']):
        raise RuntimeError('Published image age did not improve')
    record = dict(evidence='three_distinct_native_fullhd_frames_with_exact_black_reference',
                  hardware_accepted=False, source_size=[1920,1080], result_size=[640,904],
                  display_size=[1920,1080], proc_clock_hz=27000000,
                  reduction_percent=100*(old['average_start_interval_ms']-new['average_start_interval_ms'])/old['average_start_interval_ms'],
                  target_corrections_per_second=60,
                  sample_interval_within_60fps_budget=new['average_start_interval_ms'] <= 1000/60,
                  sustained_60fps_qualified=False, results=results)
    a.output.write_text(json.dumps(record, indent=2)+'\n')
    print(json.dumps(record, indent=2))


if __name__ == '__main__':
    main()
