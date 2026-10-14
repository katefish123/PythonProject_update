from pathlib import Path
D=Path(__file__).resolve().parent
R=D.parents[1]
for relative in ['pds/program_ddr_camera_hires_rowtrain.tcl','scripts/program_ddr_camera_hires_rowtrain.ps1']:
    p=R/relative
    s=p.read_text(encoding='utf-8-sig').replace('ddr_camera_hires_rowtrain','ddr_camera_coordqueue')
    p.with_name(p.name.replace('ddr_camera_hires_rowtrain','ddr_camera_coordqueue')).write_text(s,encoding='utf-8')
entry=(R/'下载高清校正_行读取修复版.cmd').read_bytes()
assert entry.count(b'program_ddr_camera_hires_rowtrain.ps1')==1
(R/'下载高清校正_坐标预计算版.cmd').write_bytes(entry.replace(b'program_ddr_camera_hires_rowtrain.ps1',b'program_ddr_camera_coordqueue.ps1'))
print('Separate qualified-only coordinate lookahead download entry prepared; not executed.')
