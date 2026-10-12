"""Create an isolated portable OBS scene containing only the real capture card."""
from pathlib import Path
import json
import uuid

R=Path(__file__).resolve().parents[1]
O=R/'tools/obs-studio/portable'
C=O/'config/obs-studio'
device=json.loads((R/'results/hardware_20261009/obs_device_query.json').read_text(encoding='utf-8-sig'))['devices'][0]
if device['friendly_name']!='VC-002Pro ' or not device['device_path']:
    raise RuntimeError('Expected capture card not identified')
def enc(value):return value.replace('#','#22').replace(':','#3A')
device_id=enc(device['friendly_name'])+':'+enc(device['device_path'])
profile=C/'basic/profiles/FPGA'
scenes=C/'basic/scenes'
profile.mkdir(parents=True,exist_ok=True)
scenes.mkdir(parents=True,exist_ok=True)
(O/'portable_mode.txt').write_text('',encoding='utf-8')
(C/'global.ini').write_text('''[General]
Language=zh-CN
FirstRun=false
LastVersion=537002496

[Basic]
Profile=FPGA
ProfileDir=FPGA
SceneCollection=FPGA
SceneCollectionFile=FPGA

[BasicWindow]
FirstRun=false
PreviewEnabled=true
StudioMode=false
''',encoding='utf-8')
(profile/'basic.ini').write_text('''[General]
Name=FPGA

[Video]
BaseCX=1920
BaseCY=1080
OutputCX=1920
OutputCY=1080
FPSType=0
FPSCommon=30
ColorFormat=NV12
ColorSpace=709
ColorRange=Partial

[Audio]
SampleRate=48000
ChannelSetup=Stereo
DesktopDevice1=disabled
DesktopDevice2=disabled
AuxDevice1=disabled
AuxDevice2=disabled

[Output]
Mode=Simple
''',encoding='utf-8')
source_name='FPGA HDMI 输出（采集卡）'
scene_name='板卡实时画面'
source_uuid=str(uuid.uuid4())
scene_uuid=str(uuid.uuid4())
source={'name':source_name,'uuid':source_uuid,'id':'dshow_input','versioned_id':'dshow_input',
        'settings':{'video_device_id':device_id,'last_video_device_id':device_id,
                    'res_type':1,'resolution':'1920x1080','last_resolution':'1920x1080',
                    'frame_interval':333333,'video_format':400,'color_space':'601','color_range':2,
                    'buffering':0,'deactivate_when_not_showing':False,'use_custom_audio_device':False,
                    'audio_output_mode':0,'hw_decode':False},
        'mixers':0,'sync':0,'flags':0,'volume':1.0,'balance':0.5,'enabled':True,'muted':True,
        'hotkeys':{},'private_settings':{}}
item={'name':source_name,'source_uuid':source_uuid,'visible':True,'locked':False,'id':1,
      'pos':{'x':0.0,'y':0.0},'scale':{'x':1.0,'y':1.0},'rot':0.0,'align':5,
      'bounds_type':2,'bounds_align':0,'bounds':{'x':1920.0,'y':1080.0},
      'crop_left':0,'crop_right':0,'crop_top':0,'crop_bottom':0,'private_settings':{}}
scene={'name':scene_name,'uuid':scene_uuid,'id':'scene','versioned_id':'scene',
       'settings':{'id_counter':2,'items':[item]},'mixers':0,'sync':0,'flags':0,
       'volume':1.0,'balance':0.5,'enabled':True,'muted':False,'hotkeys':{},'private_settings':{}}
collection={'name':'FPGA','current_scene':scene_name,'current_program_scene':scene_name,
            'scene_order':[{'name':scene_name,'uuid':scene_uuid}], 'sources':[source,scene],
            'transitions':[],'current_transition':'Fade','transition_duration':300,
            'saved_projectors':[],'quick_transitions':[],'modules':{},'preview_locked':False,
            'scaling_enabled':False,'scaling_level':0,'scaling_off_x':0,'scaling_off_y':0}
(scenes/'FPGA.json').write_text(json.dumps(collection,ensure_ascii=False,indent=2),encoding='utf-8')
print('Prepared portable OBS profile and actual HDMI capture source (1920x1080 MJPEG/30fps)')
