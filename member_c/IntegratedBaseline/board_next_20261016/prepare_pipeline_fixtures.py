"""Build original RGB rasters and independent software expected pixels for HDL."""
from pathlib import Path
import importlib.util,json,hashlib
import numpy as np
from PIL import Image,ImageDraw
here=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('pixel_reference',here.parent/'stream_video_20261015/fixtures/generate.py')
ref=importlib.util.module_from_spec(spec);spec.loader.exec_module(ref)
out=Path('D:/FPGA/output/c_board_next_pipeline_fixtures_20261016');out.mkdir(exist_ok=True)
records=[]
for native,alternate in [(False,False),(False,True),(True,False),(True,True)]:
 if native:
  folder=here/('geometry/fixtures/right_side' if alternate else 'geometry/fixtures/canonical')
  image=np.asarray(Image.open(folder/'source_1920x1080.png').convert('RGB'))
  result=np.asarray(Image.open(folder/'expected_storage_768x1080.png').convert('RGB'))
  corners=json.loads((folder/'metadata.json').read_text())['corners']
  h=json.loads((folder/'metadata.json').read_text())['H_q24_signed']
 else:
  corners=[[24,7],[112,5],[107,38],[18,42]] if alternate else [[18,5],[108,9],[104,41],[22,37]]
  im=Image.new('RGB',(128,48),(176,176,176));d=ImageDraw.Draw(im)
  for x in range(30,100,10):d.line((x,15,x,32),fill=(96,96,96))
  for (x,y),color in zip(corners,[(224,32,32),(32,208,32),(224,208,32),(32,32,224)]):d.rectangle((x-2,y-2,x+2,y+2),fill=color)
  image=np.asarray(im)
  h=ref.solve_h(corners,61,48,128,48)
  result=ref.rectify(image,h,61,48,64,1,'bilinear')
 name=('native' if native else 'reduced')+('_alt' if alternate else '');p=out/name;p.mkdir(exist_ok=True)
 for stem,a in [('source',image),('expected',result)]:
  words=(a[...,0].astype(np.uint32)<<16)|(a[...,1].astype(np.uint32)<<8)|a[...,2]
  np.savetxt(p/f'{stem}.hex',words.ravel(),fmt='%06x')
  Image.fromarray(a).save(p/f'{stem}.png')
 np.savetxt(p/'H40.hex',np.array([v&((1<<40)-1) for v in h],dtype=np.uint64),fmt='%010x')
 records.append({'native':native,'alternate':alternate,'corners':corners,'corners96':''.join(f'{n:03x}' for xy in corners for n in xy),
 'source_dimensions':[image.shape[1],image.shape[0]],'result_dimensions':[result.shape[1],result.shape[0]],
 'files':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in p.iterdir()}})
(here/'integration/fixture_manifest.json').write_text(json.dumps(records,indent=2)+'\n')
print('Prepared independent software pixel references:',out)
