"""OBS-only Chinese status card. Raw source screenshots remain unobscured."""
import argparse, importlib.util, json, os, sys, time
from pathlib import Path
sys.path.insert(0,r'D:/FPGA/tools')
from obs_background import request
from status_model import summarize

ROOT=Path(__file__).resolve().parent
NAME='板上中文诊断'
DECODER=Path(r'D:/FPGA/worktrees/c_pipeline_next/member_c/IntegratedBaseline/submission_20261023/decode_board_hud.py')

def load_decoder():
    spec=importlib.util.spec_from_file_location('hud_decoder',DECODER)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module

def install():
    scene=request('GetCurrentProgramScene')['currentProgramSceneName']
    inputs=request('GetInputList')['inputs']
    cameras=[i for i in inputs if i['inputKind']=='dshow_input']
    if len(cameras)!=1:raise RuntimeError('Expected one video capture source')
    text_file=ROOT/'status.txt'
    text_file.write_text('板上检测\n正在连接后台诊断\n未据此判断验收通过',encoding='utf-8-sig')
    settings=dict(read_from_file=True,file=str(text_file),
                  font={'face':'Microsoft YaHei','size':28,'flags':0,'style':'Regular'},
                  color=0xFFFFFF,opacity=100,bk_color=0x181818,bk_opacity=0,
                  extents=True,extents_cx=430,extents_cy=1010,wrap=True,vertical=False,
                  outline=True,outline_size=2,outline_color=0x000000,outline_opacity=100,
                  align='left',valign='top')
    found=next((i for i in inputs if i['inputName']==NAME),None)
    if found:
        request('SetInputSettings',{'inputName':NAME,'inputSettings':settings,'overlay':True})
        item=request('GetSceneItemId',{'sceneName':scene,'sourceName':NAME})['sceneItemId']
    else:
        item=request('CreateInput',{'sceneName':scene,'inputName':NAME,
                     'inputKind':'text_gdiplus_v3','inputSettings':settings,
                     'sceneItemEnabled':True})['sceneItemId']
    request('SetSceneItemTransform',{'sceneName':scene,'sceneItemId':item,
            'sceneItemTransform':{'positionX':0,'positionY':0,'scaleX':1,'scaleY':1,'rotation':0}})
    request('SetSceneItemEnabled',{'sceneName':scene,'sceneItemId':item,'sceneItemEnabled':True})
    request('SetSceneItemLocked',{'sceneName':scene,'sceneItemId':item,'sceneItemLocked':True})
    items=request('GetSceneItemList',{'sceneName':scene})['sceneItems']
    request('SetSceneItemIndex',{'sceneName':scene,'sceneItemId':item,'sceneItemIndex':len(items)-1})
    return scene,cameras[0]['inputName']

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--live',action='store_true');args=ap.parse_args()
    scene,camera=install();decoder=load_decoder();previous=None;errors=0
    while True:
        try:
            start=time.monotonic()
            request('SaveSourceScreenshot',{'sourceName':camera,'imageFormat':'png',
                    'imageFilePath':str(ROOT/'source_latest.png'),'imageWidth':1920,'imageHeight':1080})
            end=time.monotonic()
            decoded=decoder.decode(ROOT/'source_latest.png',False)
            # RXPROBE magic and absent/partly decoded HUD must not masquerade as a complete board.
            rows=decoded['rows']
            if rows.get('00')=='525850524f4245000001':
                result=summarize({},None,end)
                result['text']='接收预览诊断版\n当前未运行完整校正\n\n这是降采样预览\n细字清晰度不作验收\n\n动作跟随：请观察实景\n帧率 / 延迟：未测量\n\n原始数字已留作后台\n完整工程待上板验收'
            else:
                result=summarize(decoded['decoded_fields'],previous,(start+end)/2)
            result['screenshot_request_duration_s']=end-start
            result['capture_wall_time']=time.time()
            result['source_name']=camera
            result['text']+='\n更新 '+time.strftime('%H:%M:%S')
            (ROOT/'status.txt').write_text(result['text'],encoding='utf-8-sig')
            (ROOT/'latest.json').write_text(json.dumps({'summary':result,'raw':decoded},ensure_ascii=False,indent=2),encoding='utf-8')
            with (ROOT/'samples.jsonl').open('a',encoding='utf-8') as f:
                f.write(json.dumps(result,ensure_ascii=False)+'\n')
            previous=result;errors=0
            if not args.live:
                print(json.dumps({'panel_installed':True,'scene':scene,'text':result['text']},ensure_ascii=False));break
        except Exception as exc:
            errors+=1
            (ROOT/'status.txt').write_text('板上检测\n后台数据暂不可用\n请勿据此判定正常\n\n检查 OBS 或采集连接',encoding='utf-8-sig')
            with (ROOT/'errors.log').open('a',encoding='utf-8') as f:f.write(f'{time.time()}: {type(exc).__name__}: {exc}\n')
            previous=None
            if not args.live or errors>=20:raise
        if args.live:time.sleep(3)

if __name__=='__main__':main()
