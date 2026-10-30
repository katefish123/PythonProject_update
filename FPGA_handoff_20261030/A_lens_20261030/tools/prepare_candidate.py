from pathlib import Path
import shutil,json,hashlib,datetime
b=Path('C:/D/FPGA/A_lens_20261030');old=Path('C:/D/FPGA/A_board_20261029/candidate_de_frame_guard_v2');root=b/'candidate_host_angle_v1';assert not root.exists();shutil.copytree(old/'sources',root/'sources');(root/'project').mkdir(parents=True);(root/'build').mkdir()
shutil.copyfile(old/'project/build_full.tcl',root/'project/build_parent_reference.tcl')
for f in ['calibration/r50_18mm_hdmi_trial.json','examples/r50_18mm_viewport.json']:
 src=Path('C:/D/FPGA/A_software_20261024/reference/B_lens_v2')/f;shutil.copyfile(src,b/'calibration'/src.name)
print(str(root))