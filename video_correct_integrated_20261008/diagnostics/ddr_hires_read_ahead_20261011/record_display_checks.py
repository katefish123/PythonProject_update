"""Preserve the model-controlled improvement without granting board acceptance."""
from datetime import datetime,timezone
from pathlib import Path
import hashlib
import json
import re

D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/"results"
qualification=json.loads((O/"unit_qualification.json").read_text(encoding="utf-8-sig"))
assert qualification["display_engine_integration_passed"] and len(qualification["tests"])==4
assert not qualification["qualified_for_board"] and not qualification["programmed"]
for test in qualification["tests"].values():
    assert hashlib.sha256(Path(test["log"]).read_bytes()).hexdigest()==test["log_sha256"]
def values(name):
    text=(O/(name+".run.log")).read_text(encoding="utf-8-sig")
    line=re.search(r"HIRES_ENGINE_DISPLAY_PASS[^\r\n]+",text).group(0)
    return {k:int(v) for k,v in re.findall(r"(\w+)=(\d+)",line)}
enabled=values("tb_hires_read_ahead_display")
control=values("tb_hires_read_ahead_control")
assert enabled["correct_pixels"]==2*640*904 and enabled["black_pixels"]==0
assert enabled["physical_reads"]==18080 and enabled["logical_reads"]==144640
assert control["black_pixels"]>0 and control["expected_underflow"]==1
paths=[O/"ddr_word_engine.v",O/"tb_ddr_word_engine.sv",O/"tb_ddr_read_ahead.sv",O/"tb_hires_read_ahead_display.sv",
    R/"diagnostics/ddr_camera_hires_status_20261011/results/ddr_result_display.v",R/"rtl/memory/ddr_arbiter3.v",
    R/"vendor/c_current/01_design_code/video_timing_vtc.v"]
record={"recorded_at_utc":datetime.now(timezone.utc).isoformat(),"all_four_checks_passed":True,
    "read_ahead_enabled":enabled,"single_beat_control":control,
    "model":"28 UI clocks until first data, sequential beats, occasional additional100-clock refresh delay; 125MHz UI and148.5MHz pixel.",
    "checks":"Two complete640x904 encoded frames checked pixel-by-pixel; midscan pending bank publication cannot mix banks. Default single-beat mode under same model reproduces missing rows.",
    "hardware_latency_measured":False,"PDS_and_board_qualified":False,"programmed":False,
    "source_hashes":{str(p.relative_to(R)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},
    "limit":"This isolates display/arbiter/engine under an assumed physical response. It does not prove real DDR performance, camera image clarity, simultaneous capture/processor contention, or HDMI recovery."}
(O/"display_engine_comparison.json").write_text(json.dumps(record,indent=2)+"\n",encoding="utf-8")
note=f'''\n\n2026-10-12补充：连续读取副本新增显示器/仲裁器/DDR适配器联合检查，在假定28周期首拍延迟及偶发100周期刷新等待的同一模型下，新版逐像素通过两帧640×904（共{enabled['correct_pixels']}像素），无黑行，完整行最高耗时{enabled['max_row_cycles']}UI周期，物理读事务18080次对应144640次逻辑单拍读。关闭预读的对照版仍产生黑行。四项检查均通过；假设延迟不是实测数据，捕获/处理同时争用、PDS/时序与实板资格仍未通过，修复副本未下载。记录：`diagnostics/ddr_hires_read_ahead_20261011/results/display_engine_comparison.json`。当前板子保持刚恢复的基础a4版，等待HDMI输出连接恢复确认。\n'''
p=R/"docs/高清显示排查_20261011.md"
old=p.read_text(encoding="utf-8-sig")
if "2026-10-12补充：连续读取副本新增" not in old:p.write_text(old+note,encoding="utf-8")
p=R/"docs/当前工程入口_20261011.md"
old=p.read_text(encoding="utf-8-sig")
old=old.replace("两项单元检查通过，未完成整屏/时序资格，未上板", "四项检查（含完整两帧显示与换帧）通过，未完成PDS/时序及实板资格，未上板")
p.write_text(old,encoding="utf-8")
print(json.dumps({"display_comparison":str((O/"display_engine_comparison.json").relative_to(R)),"enabled":enabled,"control":control,"hardware_accepted":False},indent=2))
