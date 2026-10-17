"""Copy the updated C checkout into an immutable integration reference."""
from pathlib import Path
import subprocess,hashlib,json,datetime
R=Path(__file__).resolve().parents[1]
C=Path(r'C:\D\FPGA\PythonProject_update_C')
sha=subprocess.check_output(['git','rev-parse','HEAD'],cwd=C,text=True).strip()
files=subprocess.check_output(['git','ls-files','-z','member_c/VideoTimingSim'],cwd=C).decode().split('\0')
dest=R/'vendor/c_current'
records=[]
for rel in filter(None,files):
    source=C/rel
    target=dest/source.relative_to(C/'member_c/VideoTimingSim')
    target.parent.mkdir(parents=True,exist_ok=True)
    data=source.read_bytes()
    target.write_bytes(data)
    records.append({'source':str(source),'copy':str(target.relative_to(R)),
                    'sha256':hashlib.sha256(data).hexdigest()})
(R/'docs/c_update.json').write_text(json.dumps({'commit':sha,'previous_commit':'651e2c7b573ac77ccb1a6bf687a0d72bb560500b',
    'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'records':records},ensure_ascii=False,indent=2),encoding='utf-8')
print(f'C snapshot: {sha}, {len(records)} files')
