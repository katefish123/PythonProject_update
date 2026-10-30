"""Collect retained A learning/integration material; no hardware operations."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import re
import shutil
import zipfile

ROOT = Path('C:/D/FPGA/video_correct_integrated_20261008')
FORMAL = Path('C:/D/FPGA/video_correct_fpga')
DEMO = Path('C:/D/FPGA/demo')
TASK_ROOT = Path('C:/D/FPGA/个人任务')
OUT = ROOT / 'A_tasks_20261014'
RELEASE = ROOT / 'release/ddr_camera_black_20261014'
TMP = ROOT / 'tmp/a_tasks_20261014'
SHA = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
catalog = json.loads((TMP / 'baseline_catalog.json').read_text(encoding='utf-8'))
qualification = json.loads((RELEASE / 'build_qualification.json').read_text(encoding='utf-8-sig'))
tasks = []
for name in ('foundation', 'architecture', 'integration'):
    tasks += json.loads((ROOT / f'tools/A_tasks_{name}_20261014.json').read_text(encoding='utf-8'))
assert len(tasks) == 30 and len({t['id'] for t in tasks}) == 30
source_docs = json.loads((TMP / 'task_sources.json').read_text(encoding='utf-8'))
checklist = next(s for s in source_docs if s['kind'] == 'docx')
original_main = []
for block in checklist['blocks']:
    if block['kind'] == 'table' and block['rows'][0][0] == '勾选与任务':
        original_main += [row[0].replace('□', '').strip().replace('\n', ' / ') for row in block['rows'][1:]]
original_extra = [b['text'].split('\n')[0].replace('□', '').strip()
                  for b in checklist['blocks'] if b['kind'] == 'paragraph' and b['text'].startswith('□ 补')]
assert len(original_main) == 25 and len(original_extra) == 5
for task, name in zip(tasks, original_main + original_extra):
    task['original_task'] = name

def link(path, label=None, line=None):
    target = Path(path).as_posix() + (f':{line}' if line else '')
    return f'[{label or Path(path).name}](<{target}>)'

def locate(suffix):
    matches = [e for e in catalog if e['archive_path'].endswith(suffix)]
    assert len(matches) == 1, (suffix, len(matches))
    return matches[0]

def original(entry):
    if entry['source_paths']:
        assert len(entry['source_paths']) == 1
        return Path(entry['source_paths'][0])
    return ROOT / entry['archive_path']

def module_line(data):
    text = data.decode('utf-8-sig', errors='replace')
    for i, line in enumerate(text.splitlines(), 1):
        if re.match(r'\s*module\s+', line):
            return i
    return None

files = []
keyed = {}

def add(key, src, rel, role, archive_entry=None):
    src = Path(src)
    assert src.is_file(), src
    dst = OUT / rel
    assert dst.resolve().is_relative_to(OUT.resolve()), dst
    dst.parent.mkdir(parents=True, exist_ok=True)
    if archive_entry:
        with zipfile.ZipFile(RELEASE / 'source_snapshot.zip') as z:
            data = z.read(archive_entry['archive_path'])
        assert hashlib.sha256(data).hexdigest() == archive_entry['sha256']
        assert SHA(src) == archive_entry['sha256'], f'Baseline workspace changed: {src}'
        dst.write_bytes(data)
    else:
        shutil.copyfile(src, dst)
        data = dst.read_bytes()
    record = {'key': key, 'source': str(src), 'copy': str(dst), 'relative_copy': rel,
              'sha256': SHA(dst), 'size_bytes': dst.stat().st_size, 'role': role,
              'module_start_line': module_line(data),
              'compiled_baseline_source': bool(archive_entry and archive_entry['source_paths'])}
    if archive_entry:
        record['baseline_archive_path'] = archive_entry['archive_path']
    files.append(record)
    if key:
        assert key not in keyed, key
        keyed[key] = record
    return record

def frozen(key, suffix, folder, role):
    entry = locate(suffix)
    return add(key, original(entry), folder + '/' + Path(suffix).name, role, entry)

def prepare():
    sentinel = OUT / '.created_by_collect_A_tasks_20261014'
    if OUT.exists() and any(OUT.iterdir()):
        assert sentinel.is_file(), 'Output folder already contains unrelated files'
    OUT.mkdir(exist_ok=True)
    sentinel.write_text('Local A study and task mapping bundle; retained baseline only.\n', encoding='utf-8')
    assert SHA(RELEASE / 'source_snapshot.zip') == qualification['files']['source_snapshot.zip']
    for path in sorted(TASK_ROOT.glob('*')):
        if path.suffix.lower() in ('.pdf', '.docx'):
            add(None, path, '00_requirements/' + path.name, '用户原始任务文件')

    system = {
        'top': '/results/video_correct_ddr_top.v',
        'core': '/rtl/top/video_correct_ddr_core.v',
        'session': '/rtl/top/frame_session.v',
        'processor': '/results/frame_processor.v',
        'reset': '/rtl/common/reset_sync.v',
        'fifo_async': '/rtl/memory/async_packet_fifo.v',
        'capture': '/rtl/video/ddr_snapshot_capture.v',
        'capture_writer': '/rtl/memory/ddr_capture_writer.v',
        'cache': '/rtl/memory/ddr_pixel_cache.v',
        'result_writer': '/rtl/memory/ddr_result_writer.v',
        'arbiter': '/rtl/memory/ddr_arbiter3.v',
        'bridge': '/rtl/memory/ddr_command_bridge.v',
        'engine': '/results/ddr_word_engine.v',
        'display': '/results/ddr_result_display.v',
        'selftest': '/rtl/memory/ddr_self_test.v',
        'constraints': '/src/constr/board_ddr.fdc',
    }
    for key, suffix in system.items():
        frozen(key, suffix, '02_system', 'A维护的系统集成和上层存储封装')
    for key, suffix in {
        'b_wrapper': '/b_algorithm/rtl/b_rectifier.v',
        'b_core': '/b_algorithm/rtl/perspective_core.v',
        'b_coord': '/b_algorithm/rtl/perspective_coord.v',
        'b_interp': '/b_algorithm/rtl/bilinear_interp.v',
        'b_marker': '/b_algorithm/rtl/marker_detector.v',
        'b_solver': '/b_algorithm/rtl/homography_solver.v',
        'b_interface': '/b_algorithm/docs/interfaces.md',
        'provenance': '/b_algorithm/docs/provenance.json',
    }.items():
        frozen(key, suffix, '03_partner_reference/B', 'B交付，A核对接口和集成')
    for key, suffix in {
        'vtc': '/src/vendor/c_current/01_design_code/video_timing_vtc.v',
        'vs_recover': '/src/vendor/c_current/01_design_code/hdmi_vs_recover.v',
        'hdmi_config': '/src/rtl/hdmi/hdmi_config.v',
        'pll_video': '/ip/video_pll_27m_148m5/video_pll_27m_148m5.v',
        'pll_config': '/ip/config_pll_27m_10m/config_pll_27m_10m.v',
        'ddr_ip': '/ddr3_ip/ddr3_ip.v',
    }.items():
        frozen(key, suffix, '03_partner_reference/C_and_vendor', 'C或厂商底座，A配置与连接')

    learning_keys = {
        'sync_fifo_demo/rtl/sync_fifo.v': 'fifo_model',
        'fifo_ip_demo/rtl/fifo_ip_top.v': 'fifo_ip_top',
        'single_port_ram_demo/rtl/single_port_ram.v': 'ram_single',
        'dual_port_ram_demo/rtl/dual_port_ram.v': 'ram_dual',
        'ram_image_demo/ipcore/image_ram/image_ram.v': 'ram_image_ip',
        'led_on/top_led_on.v': 'led_on',
        'led_blink/source/top_led_blink.v': 'led_blink',
        'key_led/source/top_key_led.v': 'key_led',
        'mux_demo/rtl/mux2.v': 'mux',
        'comparator_demo/rtl/comparator.v': 'comparator',
        'counter_en_rst_demo/rtl/counter_en_rst.v': 'counter',
    }
    projects = ('sync_fifo_demo', 'fifo_ip_demo', 'single_port_ram_demo', 'dual_port_ram_demo', 'ram_image_demo', 'counter_en_rst_demo', 'led_on', 'led_blink', 'key_led', 'mux_demo', 'comparator_demo')
    allowed = {'.v', '.sv', '.do', '.ps1', '.md', '.idf', '.log'}
    for project in projects:
        project_root = DEMO / 'Projects' / project
        for src in sorted(project_root.rglob('*')):
            if not src.is_file() or src.suffix.lower() not in allowed:
                continue
            rel = src.relative_to(DEMO / 'Projects').as_posix()
            if any(part.lower() in ('backup', 'synthesize', 'place_route', 'work', 'work_basic', 'work_boundary') for part in src.relative_to(project_root).parts):
                continue
            if 'fifo_sync_8x64' in rel:
                continue
            if src.suffix.lower() == '.log' and 'modelsim' not in src.name.lower():
                continue
            add(learning_keys.get(rel), src, '01_basics/' + rel, 'A基础学习与模块级验证')
    add(None, DEMO / 'Documents/模块验收/模块验收表_v1.md', '01_basics/基础模块验收记录.md', '基础学习历史验收记录')
    for src in sorted((DEMO / 'Documents/模块验收/images').glob('*.png')):
        add(None, src, '01_basics/images/' + src.name, '用户学习波形和结果截图')

    docs = {
        'interface_v1': FORMAL / 'docs/接口约定/接口约定_v1.md',
        'formal_top': FORMAL / 'rtl/top/video_correct_top.v',
        'source_manifest': ROOT / 'docs/source_manifest.json',
        'ddr_notes': ROOT / 'docs/ddr_ip_notes.md',
        'preview_doc': ROOT / 'docs/实时预览联调_20261010.md',
        'preview_program': ROOT / 'scripts/program_camera_bram_overlay.ps1',
    }
    for key, src in docs.items():
        add(key, src, '04_reference_docs/' + src.name, '工程来源或历史接口，阅读时以当前说明为准')
    for key, suffix in {
        'verify': '/ddr_camera_black_20261014/verify.py',
        'build_script': '/ddr_camera_black_20261014/build.py',
        'archive_script': '/ddr_camera_black_20261014/archive.py',
        'build_tcl': '/ddr_camera_black_20261014/results/build.tcl',
        'pds_project': '/ddr_camera_black_20261014/results/ddr_camera_black.pds',
        'tb_frame': '/results/tb_ddr_full_frame.sv',
        'tb_core': '/results/tb_core_word_engine.sv',
        'tb_control': '/results/tb_coord_queue_control.sv',
        'tb_engine': '/results/tb_ddr_word_engine.sv',
        'tb_display': '/results/tb_ddr_display.sv',
    }.items():
        frozen(key, suffix, '05_verification/scripts_and_tests', '旧版集成测试及构建管理')
    evidence = {
        'baseline_qual': 'build_qualification.json', 'simulation': 'simulation_qualification.json',
        'source_hashes': 'source_hashes.json', 'snapshot': 'source_snapshot.zip',
        'timing': 'video_correct_ddr_top_timing_summary_after_hold_fix.txt',
        'resource': 'video_correct_ddr_top.prr',
    }
    for key, name in evidence.items():
        if name in qualification['files']:
            assert SHA(RELEASE / name) == qualification['files'][name]
        add(key, RELEASE / name, '05_verification/frozen_evidence/' + name, '不可改写的旧版封存证据')
    for src in sorted(RELEASE.glob('*.run.log')):
        assert SHA(src) == qualification['files'][src.name]
        add(None, src, '05_verification/frozen_evidence/logs/' + src.name, '旧版系统测试通过日志')
    for name in ('b_native_checks.log', 'b_python_checks.log', 'b_qualification.json'):
        assert SHA(RELEASE / name) == qualification['files'][name]
        add(None, RELEASE / name, '05_verification/frozen_evidence/' + name, 'B算法验证证据')
    add('hardware_evidence', ROOT / 'results/hardware_20261014_black/black_camera_verified_20261014_011446.json', '05_verification/hardware/旧黑标实拍记录.json', '旧版实际出图与验收范围')
    add(None, ROOT / 'results/hardware_20261014_black/black_program_20261014_010734.json', '05_verification/hardware/旧黑标下载回读记录.json', '历史CRAM下载记录')
    add('program_baseline', ROOT / 'diagnostics/ddr_camera_black_20261014/program.ps1', '06_handoff/program_baseline_REFERENCE.ps1.txt', '队友恢复旧版的原入口文本参考')
    add(None, ROOT / 'docs/版本弃用_黑标提速_20261014.md', '06_handoff/提速版撤下说明.md', '用户版本选择与板卡交接状态')
    for task in tasks:
        for key in task['files']:
            assert key in keyed, (task['id'], key)

def file_link(key):
    r = keyed[key]
    return link(r['copy'], Path(r['copy']).name, r['module_start_line'])

def write_documents():
    intro = '''# A 个人任务整理

你的主责是把 C 的视频底座、B 的算法和帧缓存组织成一个可验证的系统，并维护接口、时钟复位、工程与版本。这里按原清单整理了25项主任务和5项补充任务，每项都有对应代码或明确的待补内容。

本资料以旧黑标版873cb996为准。提速39574d43版已经被用户弃用，不进入本包。板卡已交给队友，本轮没有上板操作。代码存在或测试通过，不等于你本人已经理解；讲解里的自检用于学习，不能代替工程验收。

## 从这里开始

'''
    index_items = [
        ('01_A任务与工程对应表.md', '先看30项任务分别对应哪些文件'),
        ('02_三十项逐项讲解.md', '每项是什么 已有什么 还要补什么'),
        ('03_当前系统接口与数据流程.md', '完整数据流 时钟 地址 请求响应和状态机'),
        ('04_不用板卡的学习顺序.md', '先基础实验 再读整机 六步学习路线'),
        ('05_A与队友交接清单.md', 'A B C边界 当前缺口和版本交接'),
        ('06_代码入口索引.md', '点击跳到复制代码及实际编译源文件'),
        ('07_按原计划的A交付节点.md', '对照原PDF查看各阶段A要交付什么'),
    ]
    intro += '\n'.join(f'- {link(OUT / name, label)}' for name, label in index_items)
    intro += '''

## 文件夹用途

| 文件夹 | 内容 |
|---|---|
| 00_requirements | 原PDF分工文件和原A任务清单 原件未修改 |
| 01_basics | 已有FIFO RAM和计数器练习 真实IP配置 TB 日志和截图 |
| 02_system | 从旧版冻结源码提取的A集成模块 不是按同名文件猜选 |
| 03_partner_reference | B算法合同和关键模块 C及厂商底座接口 |
| 04_reference_docs | 历史接口 DDR参数和来源材料 |
| 05_verification | 旧版TB 构建脚本 封存源快照和验证证据 |
| 06_handoff | 旧版恢复入口文本和提速版撤下说明 |

## 阅读与运行边界

本包是阅读和交接资料，未配置为新的独立PDS工作目录。需要运行仿真或构建时，使用索引中列出的原工程入口；学习副本不替代原工程依赖和源清单。没有加入任何自动上板操作。

正式目录video_correct_fpga保留早期骨架和接口资料。实际旧黑标工程在video_correct_integrated_20261008/diagnostics/ddr_camera_black_20261014。多个同名.v文件是不同阶段的实现，务必按build.tcl和source_hashes确定实际编译源。

旧版已有完整RGB仿真对照、最终时序、下载回读和短时实拍出图记录；底部灰边、轻微歪斜、真实算法更新率、长期稳定性和任意角度仍不能称为完成。
'''
    (OUT / 'README.md').write_text(intro, encoding='utf-8')

    table = '# A 任务与工程对应表\n\n工程状态与个人理解分开核对。原清单的25项主任务用A01到A25，5项补充任务用S01到S05。每个条目都可在逐项讲解中找到详细说明。\n\n'
    table += '| 编号 | 工作 | 工程现状 | 先读的入口 |\n|---|---|---|---|\n'
    for task in tasks:
        first = ', '.join(file_link(k) for k in task['files'][:2])
        table += f'| {task["id"]} | {task["title"]}<br>原项 {task["original_task"]} | {task["current"]} | {first} |\n'
    table += '\n## 你的自评记录\n\n不要因文件存在而直接勾选“我看懂了”。每项学习后分别记录：我能解释什么、我核对了哪些信号或证据、还有哪一点要向B或C确认。\n'
    (OUT / '01_A任务与工程对应表.md').write_text(table, encoding='utf-8')

    lesson = '# A 的三十项任务逐项讲解\n\n每项按同一顺序说明含义、已有实现、后续缺口、A的交付和理解检查。基础组件优先复用，系统选择与集成结果由A负责。\n\n'
    group = None
    for task in tasks:
        if group != task['group']:
            group = task['group']
            lesson += f'## {group}\n\n'
        lesson += f'### {task["id"]} {task["title"]}\n\n'
        lesson += f'原清单项目：{task["original_task"]}。\n\n'
        lesson += task['explain'] + '\n\n'
        lesson += f'复用方式：{task["reuse"]}。\n\n'
        lesson += '代码入口：' + '、'.join(file_link(k) for k in task['files']) + '。\n\n'
        lesson += f'工程已有：{task["current"]}\n\n后续要补：{task["remaining"]}\n\n'
        lesson += f'A应交付：{task["delivery"]}\n\n理解自检：{task["check"]}\n\n'
    (OUT / '02_三十项逐项讲解.md').write_text(lesson, encoding='utf-8')

    interface = '''# 当前系统接口与数据流程

本页依据旧黑标873cb996的实际编译源码，补充早期接口v1的尺寸与颜色差异，供A与B C核对。它不是已经共同签认的新版本规格。

## 真实数据流

```mermaid
flowchart TD
  C_RX[C HDMI接收 RGB888 同步和有效信号] --> A_CAP[A 完整帧检查与960乘540采样]
  A_CAP --> A_FIFO[A 异步包FIFO]
  A_FIFO --> SRC[DDR 完整源帧]
  SRC --> DET[B 黑标检测与H求解]
  DET --> COORD[B 目的坐标到源坐标 四邻域地址]
  SRC --> FETCH[A 两个缓存行与像素取回]
  COORD --> FETCH
  FETCH --> INT[B 双线性或最近邻插值]
  INT --> WRITE[A 打包写入非显示结果区]
  WRITE --> DST[DDR 两个结果区]
  DST --> LINE[A 双行缓冲与显示预取]
  LINE --> C_TX[C 输出时序与HDMI发送]
  FSM[A 帧状态机 所有权 发布和确认] -.控制.-> SRC
  FSM -.控制.-> DST
```

## 当前参数

| 项目 | 旧黑标工程中的值 | A需要理解的含义 |
|---|---|---|
| 输入承载 | 1920×1080 RGB888 | C提供真实有效区和同步 |
| 算法源图 | 960×540 | 从输入每2个水平和垂直像素采一个 |
| 结果图 | 640×904 RGB888 | 完整结果578560像素 |
| HDMI扫描 | 1920×1080 | 结果窗口位于x640 y88 SCALE为1 |
| 算法时钟 | 27MHz | B接口和frame_processor均在此域 |
| 显示时钟 | 148.5MHz | 固定扫描节奏 不能等待算法 |
| 配置时钟 | 10MHz | HDMI芯片配置 |
| DDR参考及UI | 125MHz | 按现有IP和约束配置 与显示域分开 |
| 接收像素时钟 | 外部hd_rx_pclk | 实际视频模式由C核对 |
| 黑阈值 | RGB各0到64 | 不是全画面连通域跟踪 |
| 角标身份 | 四个固定ROI TL TR BR BL | 同样的黑块靠所在窗口决定身份 |
| 坐标请求额度 | 16 | 在发出目的请求时预留空间 |
| 输入FIFO | 285位×1024项 | 1位采集token 28位字地址 256位像素包 |

## 从像素地址到DDR

源像素按行排列，逻辑地址为addr=y×960+x。B已经给出四邻域的24位像素索引，A将其转换为28位DDR字地址。当前每像素占32位，格式为8位0加24位RGB，8像素组成256位beat。

举例：源坐标为123.5和217.25时，四邻域整数地址为208443、208444、209403、209404；fx为128、fy为64。第一个地址的8字对齐地址是208440，lane是3。缓存用lane×32选出其中24位RGB。

容量计算可用字节，但此引擎的cmd_addr和axi地址端口使用32位字地址，不能再次乘4。也不能沿用RGB888三字节紧密排列的偏移。

| 区域 | 基址 单位为32位字 | 用途 |
|---|---|---|
| 源帧 | 0x0000000 | 一张处理期间保持不变的源图 |
| 结果0 | 0x0100000 | 一张完整结果 |
| 结果1 | 0x0200000 | 另一张完整结果 |
| 启动自检 | 0x03f0000 | 默认256个beat的已知图案测试 |

## 一笔算法请求的生命期

1. A发出dst_valid及目的x/y，并预留一个额度。
2. B在坐标流水线完成后产生req_valid，给出inside、tag、fx/fy和四个地址。
3. A保存全部元数据。inside为1才读内存；inside为0也按序产生一次黑色响应。
4. A把同一请求的四邻域与原tag、原权重一起交回B。
5. B输出out_valid、out_rgb和out_tag，A检查位置并写入目的区。
6. 只有结果写入真正被接受才归还该像素额度；整帧完成还要等最后DDR写响应排空。

B没有ready，A不能临时丢掉已发出的请求。DDR命令有valid/ready握手；被接受前地址和负载必须保持。两种接口的节拍不同。

## 源帧与结果帧如何切换

```mermaid
stateDiagram-v2
  [*] --> WAIT_ENABLE
  WAIT_ENABLE --> REQUEST: HDMI和DDR自检准备好
  REQUEST --> CAP_WAIT: 请求一张源帧
  CAP_WAIT --> CAP_SETTLE: 完整采集确认
  CAP_SETTLE --> PROCESS: capture_ok
  CAP_SETTLE --> RETRY: 坏采集帧
  PROCESS --> PUBLISH: 算法完成且写响应排空
  PROCESS --> CLEAR: 处理失败
  PUBLISH --> DISPLAY_WAIT: 发送新结果bank
  DISPLAY_WAIT --> REQUEST: 显示帧边界切换并确认
  CLEAR --> RETRY
  RETRY --> REQUEST
```

当前只有一块源帧区，采集和处理按帧顺序进行；结果区双缓冲让显示不受处理节拍直接影响。它能保护完整帧，但不意味着每一张相机输入都被处理。角标失败后旧结果继续显示，因此静止旧图不证明算法仍在运行。

## 时钟与复位要一起核对

连续输入跨到UI使用异步FIFO；27MHz处理命令跨到UI使用请求响应邮箱；显示行缓冲用完成确认保护写域和读域。多个bit不能各自随便打两拍就当成整包安全。

reset_sync负责各域同步释放。启动还要满足PLL锁定、DDR初始化、自检及HDMI配置完成。严重内存异常和晚到响应要核对复位范围，不能只复位B的数学模块。

## 已确认与仍待确认

RGB顺序、地址布局、尺寸、算法tag、请求顺序和结果发布条件可从冻结源码确认。HDMI外部延迟仍是初步板级模型，真实更新率、端到端延迟、角标几何校准和长期稳定性仍需队友提供现场证据。
'''
    interface += '\n主要依据：' + '、'.join(file_link(k) for k in ('top','core','session','processor','cache','result_writer','b_interface','constraints')) + '。\n'
    (OUT / '03_当前系统接口与数据流程.md').write_text(interface, encoding='utf-8')

    study = '''# 不用板卡的学习顺序

板卡已经交给队友，A仍可以读代码、看已有波形、核对接口、运行离线仿真及准备答辩材料。建议每一步只追清一条因果关系，并写下你能解释的内容。

## PDF中要求的共同基础和 Verilog 语法

资料包也收集了已有LED点灯、闪烁、按键、mux、比较器和带使能复位计数器，用来复习module、input、output、wire、reg、parameter、assign、always、if和case。看懂模块端口、组合逻辑与时序逻辑、例化和TB，是读后续整机的基础。

PDF路线还提到UART。当前个人练习目录未找到独立UART学习顶层及TB；厂商DDR例程里的UART控制代码不能直接当作个人学习验收。可把它留作后续补课，不必为此中断当前接口与缓存理解。

## 第一步 回看已经做过的基础实验

先读单口RAM、简单双口RAM和sync_fifo，再看Pango FIFO IP顶层。学习RAM是16字节、单时钟；Pango FIFO实验是8位512项、当前验收到综合，不能套用旧64项码流的验收。

自检：写11、22、33、44后能按序读回；能解释full和empty；能解释地址变化为何不立刻改变dout；能区分FIFO请求与新数据有效。原实验README和TB有完整路径和运行方法。

## 第二步 只看core连接了哪些模块

先不用钻进加密DDR IP。读video_correct_ddr_core，标出capture、FIFO、capture_writer、processor、cache、destination_writer、bridge、display和仲裁。再从板顶看27MHz、RX、UI、显示时钟如何传进core。

自检：每一个实例都说出输入、输出、使用的时钟和复位，至少能认出哪几条线是像素、哪几条是命令和响应。

## 第三步 走一帧成功和一帧失败

读frame_session并对照状态图。成功帧要经过完整采集、处理、写响应排空、发布和显示确认；角标失败或坏帧不能发布。源区在处理期间保持，结果区等显示确认再换。

自检：用纸画一块源区和两块结果区，逐步写出当前谁读谁写。能解释为什么旧画面看起来稳定，却可能没有继续更新。

## 第四步 追一笔四邻域读取

用接口页中的123.5和217.25例子，核对B给出的4个逻辑地址和权重。在frame_processor中找a[0..3]、p[0..3]、tag_saved、fx_saved、fy_saved和sample，再在cache中找对齐地址及lane。

自检：四个像素必须同一帧、同一请求。inside=0也要回应一次，不能读零地址，不能把黑色响应插到前一笔未完成请求前面。

## 第五步 读测试如何证明这些规则

优先读tb_ddr_word_engine、tb_coord_queue_control、tb_core_word_engine和tb_ddr_full_frame。找清楚TB给了什么输入、独立参考是什么、何时算失败；再对照封存的通过日志。

需要复验时，在原工程使用diagnostics/ddr_camera_black_20261014/verify.py的--system-only和--cases选择项。先选对应小测试，不必第一次就跑完整大帧。此脚本运行软件与ModelSim，不会烧录板卡；修改测试或源码后不得把旧日志继续当新版本资格。

## 第六步 整理接口与自己的讲解

核对早期接口v1与当前黑标参数差异，读board_ddr.fdc和时序汇总。写一页说明：A维护哪些上层模块，B交付什么，C提供什么，何时发布完整结果，哪些故障会保留旧帧，哪些指标尚未实测。

你现在最值得补的是理解与交接证据：一张实际数据流图、一张帧状态图、一份当前接口表和一页验收边界。无需为完成清单而从零重写FIFO、DDR控制器或B的算法。

## 每次学习的记录

| 记录项 | 填写内容 |
|---|---|
| 今天我讲清楚了 | 哪个模块 哪条路径 哪个状态 |
| 今天我核对了 | 代码行 波形 日志或参考结果 |
| 还需确认 | 向B或C确认哪个具体参数或行为 |
| 下一步 | 只选择下一条需要追清的链路 |
'''
    study += '\n阅读入口：' + '、'.join(file_link(k) for k in ('led_blink','mux','counter','ram_single','ram_dual','fifo_model','fifo_ip_top','core','session','processor','tb_core')) + '。\n'
    (OUT / '04_不用板卡的学习顺序.md').write_text(study, encoding='utf-8')

    handoff = '''# A 与队友的交接清单

## 责任边界

| 人员 | 主责 | 需要交给其他人的内容 |
|---|---|---|
| A | 接口 工程集成 上层帧缓存 取像素 调度 时钟复位 验证 版本 | 实际源清单 数据流和状态图 当前接口 合格代码与未完成项 |
| B | 角标检测 变换矩阵 定点坐标 插值 算法硬件化 | 黑标身份与范围 位宽和数值合同 正确参考图 失败标志和参数 |
| C | HDMI视频底座 时序 板卡 接线 DDR低层配置 现场测试 | 输入输出模式 时钟及引脚 DDR准备状态 真实取景和板级证据 |

A负责编排DDR上层读写和帧所有权；C协作核对板卡与低层控制器。既不能把缓存相关工作全部推给C，也不需要A重新造厂商DDR控制器。复制到本包的B/C文件是协作接口参考，不代表A逐行独立编写。

## 向 B 核对

- 当前使用黑块四ROI，黑阈值和窗口是综合时参数；固定ROI不能等同于任意角度全局跟踪。
- 矩阵H为signed40位Q16.24，源坐标为20位UQ12.8；tag为目的y/x拼接，四个地址单位是像素。
- 请求没有ready，响应必须按序且每笔恰好一次，错误/越界也按合同输出有效黑像素。
- 需要B继续校准灰边与歪斜，定义角度范围和最终矫正模型；输出参数与参考结果应与A使用的尺寸一致。

## 向 C 核对

- 确认实际输入1920×1080、色序、同步、像素时钟和稳定性，保留原始取景证据。
- 确认DDR初始化、自检、显示欠载及输入断开后的状态；A需要读取成功和拒绝帧计数等状态。
- 检查HDMI外部时序模型、接线、散热和持续运行，由持板队友完成现场验证。
- 测真实更新率与延迟时提供源与输出的可对应变化，不能只报告OBS录制30fps。

## 当前版本事实

旧黑标873cb996是本包的保留基准：17项Python、9项原生算法、14项系统检查和578560像素对照通过，最终时序通过；有历史下载回读和短时完整纸页显示。实际更新率、端到端延迟、精确几何、任意角度和长时稳定仍未验收。

提速39574d43被用户弃用，不推荐用于交付，相关当前入口已撤下。板卡交给队友后没有回退操作：助手最后一次下载仍是该弃用提速版。当前板内程序由持板队友确认，不能认为选回旧版资料就自动恢复了板卡。

## A 的离线待办优先级

1. 把历史四色接口v1补成当前黑标系统接口说明，与B C共同确认。
2. 讲清源区保护、双结果区切换、tag与权重对齐、显示不能停等4项核心规则。
3. 整理已有测试的输入、参考、覆盖和通过证据，明确模型验证与实拍验证的差别。
4. 补齐资源、时序、源码来源与许可/使用说明台账，冻结真正通过团队验收的版本。
5. 与队友核对画面保持旧帧时的状态标识、当前几何问题和后续性能目标，再决定下一次改动。

## 基准工程入口

'''
    handoff += '- 原PDS工程：' + link(keyed['pds_project']['source']) + '\n'
    handoff += '- 原构建源清单：' + link(keyed['build_tcl']['source']) + '\n'
    handoff += '- 原离线验证脚本：' + link(keyed['verify']['source']) + '\n'
    handoff += '- 持板队友恢复旧黑标入口：' + link(ROOT / '下载黑色角标校正.cmd') + '\n'
    handoff += '\n恢复入口仅供持板队友操作；本次整理没有运行它。sbit与smsk必须配套，临时CRAM下载断电会丢失。\n'
    (OUT / '05_A与队友交接清单.md').write_text(handoff, encoding='utf-8')

    code_index = '# 代码与证据入口索引\n\n复制文件保留原始字节；模块行号指向实际module声明，来源栏指向原工程文件。冻结源码与原文件哈希已核对。\n\n'
    code_index += '| 文件 | 用途与责任 | 原工程位置 |\n|---|---|---|\n'
    for key, rec in keyed.items():
        code_index += f'| {file_link(key)} | {rec["role"]} | {link(rec["source"], Path(rec["source"]).name, rec["module_start_line"])} |\n'
    code_index += '\n## 来源核对\n\n任务来源为00_requirements中的原PDF和DOCX。代码读取依据是旧版真实编译清单及封存source_snapshot.zip，未加入弃用提速版。原清单勾选状态未改写；工程证据和个人理解需分开记录。\n'
    (OUT / '06_代码入口索引.md').write_text(code_index, encoding='utf-8')

    timeline = '''# 按原计划的 A 交付节点

下面保留原PDF的9月20日至11月20日节点，并对照现有工程标出依据与待补内容。它是原计划的任务对照，不是新增日历、提醒或对队友的承诺。

| 原计划阶段 | A 的交付 | 工程中已找到与仍需补的内容 |
|---|---|---|
| 9月20日至26日 | 环境 Verilog 仿真 RAM 点灯或串口 | PDS和ModelSim环境资料及LED练习已有 独立UART学习顶层与TB未找到 |
| 9月27日至10月3日 | 双口RAM写读仿真 | 16字节简单双口RAM和正确波形已有 同地址冲突及双时钟尚未验收 |
| 10月4日至10日 | 小图行列地址与像素读出 基础接口 | 初版接口和整机地址读取已有 image_ram独立小图顶层尚未接入 |
| 10月11日至17日 | 验证帧或行缓存 RAM FIFO及valid接口 | 这是10月14日所在周 旧黑标整帧与显示测试已有 需把历史四色接口补成当前黑标接口并讲清节拍 |
| 10月18日至24日 | 静态图顶层连接 缓存 坐标 插值 输出 | 旧版578560像素完整RGB对照已有 仍需你理解模块连接和每笔请求的生命周期 |
| 10月25日至31日 | 真实视频帧缓存 取像素 输出与顶层时序 | 旧版有短时完整纸页实拍 真实更新率 精确几何及输入变化验收还欠证据 |
| 11月1日至7日 | 地址 缓存 时序 边界 资源优化 | 与C完成原计划要求的30分钟连续运行 与B提供的至少3组参数配合切换 当前参数为编译期值 运行时切换尚未实现 |
| 11月8日至14日 | 固化工程 硬件结构图 资源时序材料 | 本包的数据流 状态图及旧版报告可作素材 报告和PPT成稿需另行完成 |
| 11月15日至19日 | 最终冻结 备份 硬件实现和问题处理讲解 | 旧版本地封存已有 最终实机认可版本需与队友确认 原计划至少两次完整彩排需现场记录 |
| 11月20日 | 提交工程 本地和云端双备份 | 本地资料已整理 未进行云端上传或对外提交 |

## 当前优先做的事情

先完成本周接口和缓存理解：核对当前960×540源、640×904结果、黑标ROI、请求顺序、地址单位和数据有效规则。接着补小图RAM读取的独立学习验证，读懂源帧保护与双结果区切换，再整理自己的硬件实现讲解。

每个计划节点都区分工程已有证据和本人理解。原计划中的三组参数、30分钟稳定、报告、PPT和最终提交，不能因某次编译或短录像通过而自动标成完成。
'''
    (OUT / '07_按原计划的A交付节点.md').write_text(timeline, encoding='utf-8')

    (OUT / '任务清单.json').write_text(json.dumps(tasks, ensure_ascii=False, indent=2), encoding='utf-8')
    manifest = {'created_utc': datetime.now(timezone.utc).isoformat(),
                'baseline_release': 'ddr_camera_black_20261014',
                'baseline_bitstream_sha256': qualification['files']['video_correct_ddr_top.sbit'],
                'fast_artifacts_included': False, 'hardware_operated': False,
                'original_task_files_modified': False, 'main_task_count': 25, 'supplement_count': 5,
                'compiled_baseline_source_count': len(json.loads((RELEASE / 'source_hashes.json').read_text(encoding='utf-8-sig'))),
                'files': files}
    (OUT / '来源与校验.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')

def check_bundle():
    for record in files:
        assert SHA(Path(record['copy'])) == record['sha256']
        assert SHA(Path(record['source'])) == record['sha256']
    missing = []
    for path in OUT.glob('*.md'):
        for target in re.findall(r'\]\(<([^>]+)>\)', path.read_text(encoding='utf-8')):
            target = re.sub(r':\d+$', '', target)
            if not Path(target).exists():
                missing.append(target)
    assert not missing, missing
    assert not any('ddr_camera_black_fast_20261014' in f['source'] for f in files)
    result = {'checked_utc': datetime.now(timezone.utc).isoformat(), 'copied_files': len(files),
              'all_copies_match_original_sha256': True, 'all_markdown_file_links_exist': True,
              'main_tasks': 25, 'supplement_tasks': 5, 'retained_version': '873cb996',
              'rejected_fast_source_or_bitstream_included': False, 'hardware_commands_executed': False}
    (OUT / '整理校验结果.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    archive_path = ROOT / 'A_tasks_20261014.zip'
    with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED) as z:
        for path in sorted(OUT.rglob('*')):
            if path.is_file():
                z.write(path, path.relative_to(ROOT).as_posix())
    with zipfile.ZipFile(archive_path) as z:
        assert z.testzip() is None
    digest = SHA(archive_path)
    archive_path.with_suffix('.zip.sha256').write_text(f'{digest}  {archive_path.name}\n', encoding='ascii')
    print(json.dumps({'folder': str(OUT), 'guide': str(OUT / 'README.md'),
                      'archive': str(archive_path), 'copied_files': len(files),
                      'tasks': len(tasks), 'archive_bytes': archive_path.stat().st_size,
                      'sha256': digest}, ensure_ascii=False))

if __name__ == '__main__':
    prepare()
    write_documents()
    check_bundle()
