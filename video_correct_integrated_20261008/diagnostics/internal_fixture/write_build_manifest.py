import hashlib,json
from pathlib import Path
root=Path(r'C:\D\FPGA\video_correct_integrated_20261008')
d=root/'diagnostics/internal_fixture'
bit=d/'results/internal_fixture_ddr/generate_bitstream/video_correct_ddr_internal_fixture_top.sbit'
expected=d/'fixture/expected_320x452.hex'
source=d/'fixture/source_640x480.hex'
rtr=d/'results/internal_fixture_ddr/report_timing/video_correct_ddr_internal_fixture_top.rtr'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
manifest={
 'top':'video_correct_ddr_internal_fixture_top',
 'build_directory':'diagnostics/internal_fixture/results/internal_fixture_ddr',
 'model_sim':'PASS: 691200 active input sample points, all 480 source rows',
 'independent_oracle':'vendor/b/python/brect.fixed.rectify_fixed; marker check vendor/b/python/brect.golden.detect_markers',
 'ddr_bist_enabled':True,
 'hdmi_mode':'TX_FIRST=1; fixture hdmi_ready waits for tx_done only; RX path intentionally unused',
 'pds':'Pango PDS 2022.2-SP6.4; compile/synthesize/map/place-route/report_timing/gen_bit_stream succeeded',
 'timing_summary_slow_corner_ns':{'pixel_clock_setup_wns':2.216,'pixel_clock_tns':0.0,'pixel_clock_hold_whs':0.346,'pixel_clock_ths':0.0,'all_constraints_met':True},
 'bitstream':{'path':str(bit.relative_to(root)).replace('\\','/'),'bytes':bit.stat().st_size,'sha256':sha(bit)},
 'source_fixture_sha256':sha(source),'expected_output_sha256':sha(expected),
 'post_pnr_timing_report':str(rtr.relative_to(root)).replace('\\','/')}
(d/'results/internal_fixture_ddr/build_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
print(json.dumps(manifest,indent=2))
