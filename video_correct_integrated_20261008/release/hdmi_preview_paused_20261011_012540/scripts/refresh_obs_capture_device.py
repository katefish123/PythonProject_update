"""Refresh only the capture-card identifier in an offline, backed-up OBS scene."""
from pathlib import Path
from datetime import datetime,timezone
import json,shutil
R=Path(__file__).resolve().parents[1]
device_state=json.loads((R/'results/hardware_20261009/dshow_current_device_resume_20261010.json').read_text(encoding='utf-8-sig'))
assert device_state['found'] and device_state['read_only']
devices=[d for d in device_state['devices'] if d['friendly_name'].strip()=='VC-002Pro']
assert len(devices)==1
device=devices[0]
assert device['device_path'].lower().startswith('\\\\?\\usb#vid_345f&pid_2132&mi_00#')
encode=lambda s:s.replace('#','#22').replace(':','#3A')
identifier=encode(device['friendly_name'])+':'+encode(device['device_path'])
scene=R/'tools/obs-studio/portable/config/obs-studio/basic/scenes/FPGA.json'
data=json.loads(scene.read_text(encoding='utf-8-sig'))
sources=[s for s in data['sources'] if s.get('id')=='dshow_input' or s.get('versioned_id')=='dshow_input']
assert len(sources)==1
source=sources[0]
previous=source['settings']['video_device_id']
stamp=datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')
backup=R/f'results/hardware_20261009/obs_scene_before_device_refresh_{stamp}.json'
shutil.copy2(scene,backup)
source['settings']['video_device_id']=identifier
scene.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
verify=json.loads(scene.read_text(encoding='utf-8'))
assert next(s for s in verify['sources'] if s.get('id')=='dshow_input')['settings']['video_device_id']==identifier
report={'updated_at_utc':datetime.now(timezone.utc).isoformat(),'backup':str(backup),
        'previous_device_id':previous,'current_device_id':identifier,
        'changed_settings':['video_device_id'],'source_name':source['name']}
(R/'results/hardware_20261009/obs_device_refresh_20261010.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(report,ensure_ascii=False,indent=2))
