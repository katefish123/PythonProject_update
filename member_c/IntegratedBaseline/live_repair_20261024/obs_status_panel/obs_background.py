"""Local authenticated OBS WebSocket client. Never prints credentials."""
import sys,os,json,hashlib,base64,uuid,argparse
from pathlib import Path
sys.path.insert(0,r'D:/FPGA/tools/obs_control_deps')
import websocket

def request(kind,data=None):
 cfg=json.loads((Path(os.environ['APPDATA'])/'obs-studio/plugin_config/obs-websocket/config.json').read_text(encoding='utf-8-sig'))
 if not cfg.get('server_enabled'):raise RuntimeError('OBS WebSocket disabled')
 ws=websocket.create_connection('ws://127.0.0.1:'+str(cfg.get('server_port',4455)),timeout=15)
 try:
  hello=json.loads(ws.recv()); ident={'rpcVersion':1}
  auth=hello['d'].get('authentication')
  if auth:
   b64=lambda x:base64.b64encode(hashlib.sha256(x.encode()).digest()).decode()
   secret=b64(cfg['server_password']+auth['salt'])
   ident['authentication']=b64(secret+auth['challenge'])
  ws.send(json.dumps({'op':1,'d':ident}))
  if json.loads(ws.recv())['op']!=2:raise RuntimeError('OBS authentication failed')
  rid=uuid.uuid4().hex
  ws.send(json.dumps({'op':6,'d':{'requestType':kind,'requestId':rid,'requestData':data or {}}}))
  while True:
   reply=json.loads(ws.recv())
   if reply.get('op')==7 and reply['d']['requestId']==rid:
    if not reply['d']['requestStatus']['result']:raise RuntimeError(str(reply['d']['requestStatus']))
    return reply['d'].get('responseData',{})
 finally:ws.close()
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('request');ap.add_argument('--data',default='{}');ap.add_argument('--output');a=ap.parse_args()
 result=request(a.request,json.loads(a.data))
 if a.output:Path(a.output).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
 else:print(json.dumps(result,ensure_ascii=False))
