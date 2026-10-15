"""Publish a traceable board-test candidate only after fresh 33-case timing gates."""
import argparse
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path

HERE=Path(__file__).resolve().parent
CAND=Path('diagnostics/ddr_camera_hires_prefetch_20261012/results')
sys.path.insert(0,str(HERE.parent/'inline_geometry_20261014'))
from verify_sources import verify

PRODUCTION=[
 'rtl/video/ddr_snapshot_capture.v','rtl/memory/ddr_capture_writer.v','rtl/top/frame_session.v',
 'rtl/top/video_correct_ddr_core.v','rtl/algo/capture_geometry.v','rtl/algo/geometry_frame_join.v',
 'rtl/algo/c_corner_rectifier.v','rtl/video/rx_preview.v','rtl/video/status_overlay.v',
 'diagnostics/ddr_camera_hires_20261011/results/frame_processor.v',
 (CAND/'ddr_word_engine.v').as_posix(),(CAND/'ddr_result_display.v').as_posix(),(CAND/'video_correct_ddr_top.v').as_posix(),
]


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))


def main():
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--build',type=Path,required=True)
    p.add_argument('--held-display',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    root,build,held,out=[v.resolve() for v in [a.root,a.build,a.held_display,a.output]]
    if out.exists():raise RuntimeError('Use a new delivery directory')
    manifest=root/'reproduction_manifest.json';m=read(manifest);binding=sha(manifest)
    qfile=root/CAND/'reproduced_simulation_qualification.json';q=read(qfile)
    cases=read(root/CAND/'simulation_cases.json')
    assert q['status']=='passed' and len(q['tests'])==33 and set(q['tests'])==set(cases)
    assert q['source_manifest_sha256']==binding
    for name,item in m['files'].items():assert sha(root/name)==item['local_sha256'],name
    provenance=verify(root)
    bf=build/'build_qualification.json';b=read(bf)
    assert b['source_manifest_sha256']==binding and b['simulation_qualification_sha256']==sha(qfile)
    assert b['timing_passed'] and b['simulations_passed'] and not b['hardware_accepted']
    timing=Path(b['timing_report']);assert 'Design Summary : All Constraints Met.' in timing.read_text()
    hq=read(held/'qualification.json')
    assert hq['passed'] and hq['held_display_pixel_check'] and hq['source_manifest_sha256']==binding
    for path,digest in hq['inputs'].items():assert sha(Path(path))==digest,path
    hlog=held/'tb_core_recovery/simulation.log';ht=hlog.read_text()
    assert sha(hlog)==hq['tests']['tb_core_recovery']['log_sha256']
    match=re.search(r'RECOVERY_DISPLAY_CHECK_PASS old_pixels=(\d+) new_pixels=(\d+)',ht)
    assert match and int(match[1])>=768 and int(match[2])>=768
    files={'reproduction_manifest.json':manifest,'simulation_qualification.json':qfile,
           'build_qualification.json':bf,'timing_summary.txt':timing,'build.log':Path(b['build_log']),
           'performance.json':root/'performance.json','held_display/qualification.json':held/'qualification.json',
           'resource_map.log':build/'device_map/run.log',
           'held_display/simulation.log':hlog,'held_display/tb_core_recovery.sv':held/'tb_core_recovery.sv',
           'project/ddr_camera_hires_prefetch.pds':build/'ddr_camera_hires_prefetch.pds',
           'compile_preflight.log':root/'compile_preflight/compile_all.log'}
    preflight=files['compile_preflight.log'].read_text()
    assert 'COMPILE_PREFLIGHT_PASS' in preflight and not re.search(r'\*\* (Error|Warning|Fatal)',preflight)
    for name,item in q['tests'].items():
        log=Path(item['log']);content=log.read_text()
        assert item['passed'] and item['exit_code']==0 and sha(log)==item['log_sha256']
        assert 'VERIFIED_PASS_BIT=1' in content and cases[name] in content and not re.search(r'\*\* (Error|Warning|Fatal)',content)
        files['logs/'+name+'.log']=log
    for extension,item in b['artifacts'].items():
        artifact=Path(item['path']);assert sha(artifact)==item['sha256']
        files['bitstream/video_correct_ddr_top.'+extension]=artifact
    for name in PRODUCTION:files['sources/'+name]=root/name
    for src in (root/'fullhd_tests').glob('*.sv'):files['sources/fullhd_tests/'+src.name]=src
    for src in (root/CAND).glob('tb_*.do'):files['sources/'+(CAND/src.name).as_posix()]=src
    files['sources/'+(CAND/'simulation_cases.json').as_posix()]=root/CAND/'simulation_cases.json'
    out.mkdir(parents=True)
    for name,src in files.items():
        dst=out/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
    record=dict(configuration='fullhd_filtered_black_banked_burst_preview_recovery_board_test_candidate',
       origin_root=str(root),source_manifest_sha256=binding,simulations_passed=33,
       additional_held_display_check=True,held_old_pixels=int(match[1]),held_new_pixels=int(match[2]),
       timing_passed=True,hardware_accepted=False,board_replacement_allowed=False,
       sustained_60fps_qualified=False,lens_rtl_integrated=False,real_calibration_available=False,
       original_b_provenance=provenance,files={name:sha(src) for name,src in files.items()})
    (out/'manifest.json').write_text(json.dumps(record,indent=2)+'\n')
    (out/'README.md').write_text('''# 合并版板测候选

33项新仿真、额外错误期间旧/新显示逐像素检查，以及最终PDS时序通过。硬件验收=false；尚未烧录，不能声称实时或镜头模型已接入。

bitstream/ 提供本次输入绑定生成的sbit/smsk；manifest.json逐文件列SHA256。project/工程保留本机绝对源码路径，请在本机原输出目录使用；换机器应从仓库生成器及固定Git/IP依赖重建。

完整源1920×1080，透视结果640×904。三帧平均启动间隔约508.319ms，约1.97张不同结果/秒的模型样本，不满足用户60张/秒目标；镜头径向/切向硬件、真实标定、参数提交与画质量化仍待完成。B9个原始RTL保持。

板上既有540dd628版本未被更换。烧录专用聊天后续需核对本候选SHA、Program+Verify、相机目标与四黑标定位窗口、持续视频/重连、失败提示、旧图保持、新图变化及实际延迟/清晰度，再决定接受或回退。开发聊天未操作板子和OBS。
''',encoding='utf-8')
    print('MERGED_DELIVERY_VERIFIED simulations=33 timing=passed held_display=passed hardware_accepted=false')


if __name__=='__main__':main()
