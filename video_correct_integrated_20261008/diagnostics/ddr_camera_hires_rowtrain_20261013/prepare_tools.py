from pathlib import Path
D=Path(__file__).resolve().parent
R=D.parents[1]
for relative in ['pds/program_ddr_camera_hires_prefetch.tcl','scripts/program_ddr_camera_hires_prefetch.ps1']:
    p=R/relative
    s=p.read_text(encoding='utf-8-sig').replace('ddr_camera_hires_prefetch','ddr_camera_hires_rowtrain').replace('20261012','20261013')
    p.with_name(p.name.replace('prefetch','rowtrain')).write_text(s,encoding='utf-8')
entry=(R/'下载高清校正_连续读取版.cmd').read_bytes()
assert entry.count(b'program_ddr_camera_hires_prefetch.ps1')==1
(R/'下载高清校正_行读取修复版.cmd').write_bytes(entry.replace(b'program_ddr_camera_hires_prefetch.ps1',b'program_ddr_camera_hires_rowtrain.ps1'))
print('Separate qualified-only row-train download entry prepared.')
