"""Resume the verified official OBS package in modest parallel HTTP ranges."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import hashlib
import re
import urllib.request
import zipfile

R=Path(__file__).resolve().parents[1]
D=R/'tools/obs-studio'
P=D/'OBS-Studio-32.2.2-Windows-x64.zip'
URL='https://cdn-fastly.obsproject.com/downloads/OBS-Studio-32.2.2-Windows-x64.zip'
EXPECTED='4d6e40e3ab155f56b30de517380566a206d74b63cdf5ad49aa596924768f97e1'
parts=D/'download_parts'
parts.mkdir(exist_ok=True)

def request_range(start,end):
    req=urllib.request.Request(URL,headers={'Range':f'bytes={start}-{end}','User-Agent':'OBS-local-download'})
    response=urllib.request.urlopen(req,timeout=45)
    match=re.fullmatch(r'bytes (\d+)-(\d+)/(\d+)',response.headers.get('Content-Range',''))
    if response.status!=206 or not match or int(match[1])!=start or int(match[2])!=end:
        response.close()
        raise RuntimeError('Server did not return the requested range')
    return response,int(match[3])

response,total=request_range(0,0)
response.read();response.close()
have=P.stat().st_size if P.exists() else 0
if have>total:raise RuntimeError('Local partial file exceeds remote total')
chunk=4*1024*1024
ranges=[(start,min(total-1,start+chunk-1)) for start in range(have,total,chunk)]
print(f'Official package: {total} bytes; existing {have}; remaining {total-have}',flush=True)

def fetch(bounds):
    start,end=bounds
    path=parts/f'{start}-{end}.part'
    need=end-start+1
    if path.exists() and path.stat().st_size==need:return path
    for attempt in range(3):
        try:
            response,size=request_range(start,end)
            if size!=total:raise RuntimeError('Remote file changed')
            with response, path.open('wb') as dest:
                while block:=response.read(256*1024):dest.write(block)
            if path.stat().st_size!=need:raise RuntimeError('Incomplete part')
            print(f'Part {start}-{end} complete',flush=True)
            return path
        except Exception:
            if attempt==2:raise

with ThreadPoolExecutor(max_workers=8) as pool:
    futures={pool.submit(fetch,bounds):bounds for bounds in ranges}
    for future in as_completed(futures):future.result()
with P.open('ab') as dest:
    for start,end in ranges:
        with (parts/f'{start}-{end}.part').open('rb') as src:
            while block:=src.read(1024*1024):dest.write(block)
digest=hashlib.sha256(P.read_bytes()).hexdigest()
if digest!=EXPECTED:raise RuntimeError(f'Official checksum mismatch: {digest}')
with zipfile.ZipFile(P) as archive:
    bad=archive.testzip()
    if bad:raise RuntimeError(f'Package CRC failed: {bad}')
    archive.extractall(D/'portable')
print('OBS official checksum and ZIP CRC passed; portable files ready',flush=True)
