from pathlib import Path
R=Path(__file__).resolve().parents[1]
old=(R/'显示相机测试图_大角标.cmd').read_bytes()
assert old.count(b'show_camera_target_large.py')==1
(R/'显示相机测试图_更新速度.cmd').write_bytes(old.replace(b'show_camera_target_large.py',b'show_camera_target_update.py'))
print('Separate counter launcher prepared; original bytes and existing targets preserved.')
