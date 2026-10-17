# 镜头数值基线：精确除法调度与时序优化

**仍未达到实时视频或企业镜头验收。** 本轮不改原 lens_model_next 数值基线、B或V5C，不烧板。优化保持同一请求的坐标、像素、tag、版本、错误语义不变，不降低图像分辨率。

## 实际改善

|相同1024组合成向量|原顺序基线|本轮v2|
|---|---:|---:|
|Brown最长等待，周期/点|350|158|
|理想H＋Brown最长等待，周期/点|652|288|

2573笔新旧RTL算术逐笔等价，包含符号、舍入、溢出、除零、最小负数、最高商位和运行中复位。Brown、H＋Brown各1024个坐标及原B双线性采样像素精确一致，零errors/warnings；背压和执行期间切换参数的原测试保留。旧128轮除法作为故意失败对照，未通过有效周期门禁。[功能证据](verification.json) · [实际编译源/向量/日志包](evidence/exact_schedule_tests.zip)。

优化通过只处理有效商位、保留精确余数与最近偶数舍入实现。第一次物理探测发现比较→减法→末位舍入关键路径余量仅0.023ns，随后将余数路径按已证明范围收窄至94位，借位复用为比较，舍入独立一拍。四次除法合计多4拍，组合等待由首版284变为288，但关键路径得到改善。

## 隔离模块PDS检查（不是整板时序资格）

输入/输出加寄存器的相同包装，PG2L100H-6 FBG676，内部时钟17.508ns，相同布局布线种子。外部IO时延与板级引脚没有定义；日志中的未约束IO警告是探测边界，不能当作整板全部约束通过。没有生成sbit。

|综合资源/内部慢角建立余量|原单元包装|首版fast包装|v2 fast包装|
|---|---:|---:|---:|
|LUT|1834|2517|2183|
|寄存器|691|721|591|
|APM/DSP块|12|12|12|
|慢角setup余量，ns|1.746|0.023|3.723|

快慢角内部setup/hold均无失败端点；具体源SHA、资源报告、约束和时序见 [隔离PDS记录](probe_results.json) 与 [工程输入/报告包](evidence/isolated_registered_PDS.zip)。上述包装的资源不是整板总资源，内部余量不是整板频率或实际帧率。

## 当前边界与后续

288周期/点仍是顺序处理，尚不满足完整1920×1080实时吞吐。全流水线/并行调度、生产DDR采样和显示集成、真实新图率/端到端延迟、资源及整板最终时序仍需完成；真实镜头验收继续blocked_by_missing_calibration。

最新用户的局部画面要求记录在 [display_contract.json](../compliance_20261015/gates_20261017/display_contract.json)：输入输出同尺寸，只校正实际纸/pad外框内内容，空余填背景，框外保留，完整清除旧定位点是明确例外。H、边框、目标矩形、背景和mask需绑定同一源帧/bank。**该画面合成尚未实现，本轮不把单图文字/网格拟合算作通用镜头模型或企业验收。**

## 复现

```powershell
python -B member_c/IntegratedBaseline/lens_throughput_20261017/build_fast.py
& member_c/IntegratedBaseline/lens_throughput_20261017/run_tests.ps1 -Suffix fresh_equivalence
& member_c/IntegratedBaseline/lens_throughput_20261017/run_tests.ps1 -Suffix fresh_brown -Map
& member_c/IntegratedBaseline/lens_throughput_20261017/run_tests.ps1 -Suffix fresh_composed -Map -Composed
```

向量来自已验证的lens_model_next/prepare_vectors.py及原有float/fixed/B参考，原向量未改。每次用新后缀，保存实际编译副本及向量快照。prepare_probes.py仅生成隔离PDS探测项目，默认目录如已存在会拒绝覆盖，需传入新的输出根目录。工具不连接板子。
