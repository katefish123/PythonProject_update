"""Fast source/evidence handoff snapshot; no build or hardware operations."""
from pathlib import Path
import datetime,hashlib,json,os,zipfile

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT.parent/('FPGA_handoff_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S')+'.zip')
SKIP_DIRS={'work','__pycache__','.git','.venv','node_modules'}
TEXT={'.py','.md','.json','.v','.vp','.vh','.sv','.svh','.vhd','.tcl','.fdc','.sdc','.cst','.prj','.pds','.ini','.cmd','.bat','.ps1','.txt','.log','.rtr','.prr','.prt','.csv','.mem','.hex','.bin','.png','.jpg','.jpeg','.pdf'}

def digest_file(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
    return h.hexdigest()

def main():
    entries=[];excluded=[];total=0
    with zipfile.ZipFile(OUT,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=1,allowZip64=True) as z:
        def add(p,name):
            nonlocal total
            data=p.read_bytes();z.writestr(name,data)
            entries.append({'entry':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()});total+=len(data)
        for folder,dirs,files in os.walk(ROOT):
            rel_dir=Path(folder).relative_to(ROOT)
            dirs[:]=sorted(d for d in dirs if d not in SKIP_DIRS and not d.startswith('work_')
                           and not ('verification' in rel_dir.parts and d in {'actual_trial','synthetic_rebinding_fixture'}))
            for name in sorted(files):
                p=Path(folder)/name;rel=p.relative_to(ROOT);suffix=p.suffix.lower();size=p.stat().st_size
                source_file=any(d in rel.parts for d in ['sources','project']) and 'verification' not in rel.parts
                keep=source_file or suffix in TEXT or (suffix=='.vm' and 'verification' in rel.parts and size<8*1024*1024)
                if suffix in {'.zip','.sbit','.smsk','.db','.adf','.sdf','.wlf','.pyc','.dll','.exe','.lib','.obj'}:keep=False
                if suffix=='.hex' and size>1024*1024:keep=False
                if suffix=='.bin' and size>65536:keep=False
                if suffix in {'.log','.txt'} and size>16*1024*1024:keep=False
                if keep:add(p,'A_lens_20261030/'+rel.as_posix())
                else:excluded.append(rel.as_posix())
        bref=Path('C:/D/FPGA/A_software_20261024/reference/B_lens_v2')
        for p in sorted((bref/'python').rglob('*.py')):
            if '__pycache__' not in p.parts:add(p,'external_reference/B_lens_v2/'+p.relative_to(bref).as_posix())
        for name in ['real_18mm_input.png','r50_18mm_viewport.json']:
            p=bref/'examples'/name
            if p.exists():add(p,'external_reference/B_lens_v2/examples/'+name)
        readme='''# 现有工程交接快照

这是用户要求暂停后的现有工程打包，不是已经通过验收的上板发布版。

先读 A_lens_20261030/交接说明_20261030_暂停.md。
V2是软件功能基线，完整视频回归通过，但物理时序未通过。
V3是未完成实验，90度帧率未通过，专用地址桥测试台仍有编译错误。

包含三个候选的源码/工程脚本、工具、文档、标定资料、验证记录和关键报告。
为便于快速交接，未包含EDA/ModelSim生成缓存、大型全帧HEX、完整物理数据库、SDK和未合格下载文件。
大型测试向量可由包内脚本重新生成；逐项省略清单见 package_manifest.json。
没有重新构建、修改RTL或操作硬件。

部分工具使用原机器绝对路径。换电脑时需要按交接说明调整Python、ModelSim、PDS及B参考/依赖路径。
external_reference 附有B的Python参考和实际输入样例；不包含软件安装包。
'''
        z.writestr('先读我_工程状态.md',readme)
        manifest={'created':datetime.datetime.now().astimezone().isoformat(),'status':'paused_handoff_unqualified',
                  'hardware_accessed':False,'files':entries,'excluded_generated_or_large_files':excluded,
                  'file_count':len(entries),'uncompressed_bytes':total}
        z.writestr('package_manifest.json',json.dumps(manifest,indent=2,ensure_ascii=False))
    with zipfile.ZipFile(OUT) as z:
        bad=z.testzip()
        if bad:raise RuntimeError('Archive integrity error: '+bad)
    h=digest_file(OUT);OUT.with_suffix('.sha256.txt').write_text(h+'  '+OUT.name+'\n',encoding='utf-8')
    print(json.dumps({'archive':str(OUT),'size_mb':round(OUT.stat().st_size/1024/1024,2),'files':len(entries),
                      'crc_verified':True,'sha256':h},ensure_ascii=True),flush=True)

if __name__=='__main__':main()
