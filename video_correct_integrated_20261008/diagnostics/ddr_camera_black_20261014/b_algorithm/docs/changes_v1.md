# 历史记录：B 接口 v1 补充（2026-10-06）

本页描述2026-10-06四色版接口补充的历史状态和当时八项测试，保留原有效缓存/数值决策。本次2026-10-11已修改黑标记检测与ROI，当前变更见 [changes_black_detection.md](changes_black_detection.md)，当前配置见 [black_markers.md](black_markers.md)。下文`behavior_changed=false`只指当时接口补充，不能套用到本次检测改动。

日期：2026-10-06。依据：A的v1接口约定及`member_b_perspective_final 对照接口 v1 的补充清单`。本版统一缓存合同，补联调测试、配置记录、接线示例和硬件验收表。`behavior_changed=false`：九个算法RTL及Python数值算法保持原有行为。

## 接口与配置

- [interfaces.md](interfaces.md)将“推荐按序响应”改为强制合同：每笔请求必须且只能响应一次，所有响应在进入B前按请求顺序；A负责重排，黑色响应也占原队列位置。
- 明确`req_error`的负分子、分母、48位输入及比值≥4096包络；可表示的正向图像越界只清`req_inside`。两类都按序响应黑色，错误标志不能用来跳过响应。
- 明确复位时A清空外部请求/响应/重排/输出队列，并丢弃晚到的旧DDR结果。B内部复位不能识别外部旧响应。
- 补H提交、采集帧、源缓存帧锁定和目的帧显示关系，记录提交与新求解完成同拍的现有行为。
- 新增 [integration_v1.md](integration_v1.md) 和 [integration_config.json](../examples/integration_config.json)。记录全部RTL默认参数、待确认最终值、负责人和下一步；640×480源、320×452纸面与C的1920×1080扫描区分别配置。
- 颜色阈值及统计限值明确为编译/综合时参数。实际处理时钟、摄像头标定和A/C缓存/窗口方案继续为`pending`；50MHz只属于示例约束。

## 测试与示例

保留原五个testbench，新增以下三项。两个运行器共用 [sim/tests.list](../sim/tests.list)，共八项；`ALL_CHECKS_PASS`和`ALL_MODELSIM_CHECKS_PASS`继续只表示对应全套检查成功，不能在局部测试后打印。

| 新文件 | 成功标志 | 主要覆盖 |
| --- | --- | --- |
| [tb_cache_contract.sv](../sim/tb_cache_contract.sv) | `CACHE_CONTRACT_PASS` | 按序可变缓存延迟、空拍、有效/黑色响应、逐笔模式、元数据和像素 |
| [tb_b_integration.sv](../sim/tb_b_integration.sv) | `B_INTEGRATION_PASS` | 源/目的并行、H帧内保持与帧边界提交、同拍完成、在途复位 |
| [tb_request_boundaries.sv](../sim/tb_request_boundaries.sv) | `BOUNDARIES_PASS` | 默认算法尺寸、首末行列、地址步长、错误分类和合法贴边量化 |

新增 [b_rectifier_instance.v](../examples/b_rectifier_instance.v) 和 [integration_files.f](../examples/integration_files.f)作为可综合的具名端口透传参考。它转发B原参数和端口；没有DDR、HDMI、CDC或可下载板级顶层。默认编译及参数覆写方法见 [集成记录](integration_v1.md)。

## 保留的边缘规则

仍采用严格越界填黑，不统一钳位。源640×480、目的320×452，合法四角`[(20,20),(639,50),(639,440),(20,440)]`的定点H可把最右列推到`639+1/256`，双线性输出黑列；该行为纳入边界回归，属于现有量化与采样合同。贴底角点也可能出现黑行。

如果演示要求消除这些黑边，由A/B明确有限容差和边界处理范围，再一起修改Python参考、RTL、接口合同和回归。当前补充没有做这项算法改动。数值定义及最近邻差异见 [接口说明](interfaces.md)。

## 证据与尚未运行的项目

[validation_record.md](validation_record.md)保留2026-10-05的五项RTL、Python和原生ModelSim坐标测试历史证据，旧报告和日志本次归档于`backups/2026-10-11_before_black_detection/results/history/2026-10-05/`。验证记录另列八项功能验收及原生全套、PDS、摄像头、开发板的记录表。ModelSim全套日志预定为`results/modelsim_full.log`；当时Icarus结果归档于`backups/2026-10-11_before_black_detection/results/verification.json`；当前黑标记结果以新的`results/verification.json`为准。

PDS综合/布局布线/时序、LUT/FF/DRM/APM、Fmax、真实摄像头、DDR、HDMI和开发板仍无实跑凭据，状态为`not_run`，未知值为`pending`。历史Tcl命令替身检查不属于原生ModelSim全套，算法缓存模型不属于DDR或整机吞吐验证。本版未编造硬件日志、资源数、Fmax或原生全套通过结论。
