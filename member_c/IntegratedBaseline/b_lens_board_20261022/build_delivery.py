"""Create a local, relocatable source/PDS/CRAM candidate only after qualification."""
from pathlib import Path
import argparse,hashlib,json,re,shutil,subprocess,zipfile

def require(ok,msg):
    if not ok:raise RuntimeError(msg)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--candidate',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);args=ap.parse_args()
    source=args.candidate.resolve();out=args.output.resolve();helpers=Path(__file__).parent
    q=json.loads((source/'release/qualification.json').read_text())
    require(q['timing_qualified'] and q['ready_for_authorized_cram_experiment'],'Candidate not qualified')
    for n,h in q['candidate_source_sha256'].items():require(sha(source/'sources'/n)==h,'Source drift '+n)
    for name,key in [('bitstream','bitstream_sha256'),('mask','mask_sha256'),('final_timing_report','final_timing_sha256')]:require(sha(Path(q[name]))==q[key],'Qualified artifact drift '+name)
    require(not out.exists(),'Preserve existing delivery');out.mkdir(parents=True)
    shutil.copytree(source/'sources',out/'sources')
    for name in ['project','release','validation','tools']:(out/name).mkdir()
    for ext in ['sbit','smsk']:shutil.copy2(source/f'release/video_correct_ddr_top.{ext}',out/'release')
    shutil.copy2(source/'release/qualification.json',out/'release')
    shutil.copy2(Path(q['final_timing_report']),out/'validation/final_timing.rtr')
    shutil.copy2(source/'interface_audit.json',out/'validation')
    shutil.copy2(source/'source_manifest.json',out/'validation')
    shutil.copy2(source/'pds_console.log',out/'validation')
    if q.get('implementation')=='performance':
        d=out/'validation/performance';d.mkdir()
        for n in ['pds_console.log','route.tcl','input_binding.json','performance.pds']:shutil.copy2(source/'performance'/n,d/n)
    shutil.copy2(Path('D:/FPGA/output/b_lens_board_fixtures_20261022/manifest.json'),out/'validation/fixture_manifest.json')
    shutil.copy2(Path('D:/FPGA/team_downloads/20261022_B_lens_v2/member_b_lens_pipeline_v2/calibration/r50_18mm_hdmi_trial.json'),out/'validation/trial_calibration.json')
    for rate in [30,60]:
        t=Path(f'D:/FPGA/output/b_lens_rxretime_input{rate}_20261023')
        d=out/f'validation/input{rate}';d.mkdir()
        for n in ['compile.log','simulation.log','compiled_hashes.json','candidate_binding.json']:shutil.copy2(t/n,d/n)
    d=out/'validation/frontend_vs_recovery';d.mkdir()
    for n in ['compile.log','simulation.log','simulation_raw.log','compiled_hashes.json','candidate_binding.json']:shutil.copy2(Path('D:/FPGA/output/b_lens_rxretime_frontsync_20261023')/n,d/n)
    phase=out/'validation/frontend_phase';phase.mkdir()
    for mode in ['red','green']:
        d=phase/mode;d.mkdir()
        for n in ['compile.log','simulation.log','binding.json','rx_frontend.v','tb.sv']:shutil.copy2(Path('D:/FPGA/output/rx_frontend_phase_test_20261023_valid')/mode/n,d/n)
    config=out/'validation/hdmi_configuration';config.mkdir()
    for n in ['compile.log','simulation.log','source_binding.json']:shutil.copy2(Path('D:/FPGA/output/b_lens_rxretime_config_clean_20261023')/n,config/n)
    shutil.copy2(helpers/'program_package.py',out/'tools')
    shutil.copy2(helpers/'ACCEPTANCE_20261023.md',out/'验收步骤.md')
    shutil.copy2(helpers/'INTERFACES_20261023.md',out/'接口核对.md')
    (out/'program.ps1').write_text("$ErrorActionPreference='Stop'\n& python (Join-Path $PSScriptRoot 'tools/program_package.py')\nif($LASTEXITCODE -ne 0){throw 'Programming or verification failed; inspect program_logs'}\n")
    text=(source/'build.tcl').read_text();cut=text.index('compile -top_module')
    setup=text[:cut].replace((source/'sources').as_posix(),(out/'sources').as_posix())
    script=out/'tools/create_project.tcl';script.write_text(setup)
    with (out/'validation/project_creation.log').open('wb') as f:
        result=subprocess.run(['D:/softwares/PDS/PDS_2022.2-SP6.4/bin/pds_shell.exe','-file',str(script),'-project_name','FullHD_Lens_RXRetimed'],cwd=out/'project',stdout=f,stderr=subprocess.STDOUT)
    require(result.returncode==0,'PDS source project creation failed')
    project=out/'project/FullHD_Lens_RXRetimed.pds';require(project.is_file(),'Missing PDS')
    p=project.read_text();source_paths=re.findall(r'_file "(\.\./sources/[^"]+)"',p)
    require(len(source_paths)==148 and all((project.parent/n).is_file() for n in source_paths),'PDS source resolution failed')
    require(not re.search(r'_file "[A-Za-z]:',p),'PDS contains absolute source paths')
    # The regeneration script derives its paths from its own location.
    local_setup='set root [file normalize [file join [file dirname [info script]] ..]]\n'
    for line in setup.splitlines():
        match=re.match(r'(add_design|add_constraint)\s+\{([^}]+)\}',line)
        local_setup+=f'{match[1]} [file join $root sources {Path(match[2]).name}]\n' if match else line+'\n'
    script.write_text(local_setup)
    (out/'tools/rebuild.tcl').write_text(local_setup+text[cut:])
    (out/'README.md').write_text('# 全高清镜头校正集成候选\n\n入口：`project/FullHD_Lens_RXRetimed.pds`；直接临时烧录：`program.ps1`。\n\n已通过源码/接口/仿真及最终时序检查，尚未完成这份完整码流的实板验收。不是最终比赛成品。请先读 `验收步骤.md`。\n\n保留 1920×1080 和 16:9，B 镜头数学模块不变。临时 CRAM，未写 Flash。包内验证记录绑定本码流；修改源文件后不能沿用。当前诊断曾见偏绿，颜色、清晰度、刷新率及稳定性均须现场验收。\n\n本地私有交付含已有厂商依赖，不自动上传公开仓库。\n',encoding='utf-8')
    files={p.relative_to(out).as_posix():sha(p) for p in out.rglob('*') if p.is_file()}
    (out/'MANIFEST_SHA256.json').write_text(json.dumps(files,indent=2)+'\n')
    for n,h in files.items():require(sha(out/n)==h,'Delivery copy drift '+n)
    archive=out.with_suffix('.zip');require(not archive.exists(),'Preserve existing zip')
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
        for p in out.rglob('*'):
            if p.is_file():z.write(p,out.name+'/'+p.relative_to(out).as_posix())
    with zipfile.ZipFile(archive) as z:require(z.testzip() is None,'Archive CRC failed')
    print('DELIVERY_VERIFIED',out,'ZIP_SHA256',sha(archive))
if __name__=='__main__':main()
