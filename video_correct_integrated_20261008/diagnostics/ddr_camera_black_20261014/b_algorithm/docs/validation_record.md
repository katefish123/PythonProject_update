# B 黑标记版本验证记录

只有真实运行日志可以填写`pass`。`not_run`表示没有实跑，`pending`表示值或方案未确定。电脑端算法仿真、脚本控制测试、原生ModelSim、PDS和整机分别记录，不能互相替代。本页保留历史证据；当前黑标记版本Icarus结果以当次 [verification.json](../results/verification.json) 和对应日志为准。历史文件已移入`backups/2026-10-11_before_black_detection/results/`。

## 当前黑标记版本：2026-10-11

<!-- CURRENT_RUN_BEGIN -->
本次完整Icarus检查通过，输出`ALL_CHECKS_PASS`。最终报告 [results/verification.json](../results/verification.json) 的生成时间为`2026-10-11T04:05:49.166581+00:00`（北京时间2026-10-11 12:05:49），版本为`black_markers_2026-10-11`。

| 检查 | 本次结果 | 证据 |
| --- | --- | --- |
| Python模型 | 17项通过 | `results/python_tests.log`，包括黑阈值/ROI及非法配置 |
| ModelSim脚本控制 | 11项通过 | `results/modelsim_script_tests.log`，真实Tcl+命令替身，未执行原生ModelSim |
| RTL完整清单 | 9项全部通过 | `results/verification.json`的`rtl_test_results`及9个testbench日志 |
| 黑配置专项 | 奇数默认ROI 2帧、局部ROI 1帧、非零下界32、低于下界31拒绝、22种非法配置、无黑像素2帧、6对共享边界拒绝 | `results/tb_marker_config.log` |
| RTL与Python实际导出对比 | 坐标4329、求解器37、RGB插值1000、wrapper像素2344，逐笔一致 | 报告`actual_rtl_comparison`及CSV/重建PNG |
| 端口透传示例 | Verilog-2001编译通过 | `results/example_syntax.log` |
| 黑标记大演示/静态CLI | 4个真黑81像素标记，TL/TR/BR/BL质心与演示四角一致 | `examples/demo_parameters.json`、`results/cli_smoke/parameters.json`及输出PNG |
| 完整原工程备份/原目录未改 | 245文件逐文件SHA256再次确认 | `results/backup_verification.json`和上一级`source_backup_manifest.json` |
| 独立复查 | 检查黑检测、ROI、角点顺序、配置校验及参数透传；结论见实跑复查记录 | `results/quality_review.md` |
| 原v3直接兼容实跑 | `not_requested` | 本次报告`v3_compatibility`；下方500组记录为历史证据 |

Icarus日志中的数组敏感项提示已单独保留，不把“通过”写成零警告。黑配置检查包含源尺寸、阈值、统计限值、ROI端点及重叠的非法情况。静态CLI使用`--thresholds examples/thresholds.json --rois examples/rois_demo.json`；大演示ROI将真实黑正文排除在角点统计之外。
<!-- CURRENT_RUN_END -->

原生ModelSim全套、PDS、真实摄像头、DDR/HDMI和开发板仍按下方独立记录。Icarus功能通过和Tcl命令替身检查均不能代替这些实跑。

## 保留的历史证据：2026-10-05

| 检查 | 历史结果 | 证据/范围 |
| --- | --- | --- |
| Python模型 | 10项通过 | [历史verification.json](../backups/2026-10-11_before_black_detection/results/history/2026-10-05/verification.json)，不是本版新增测试计数 |
| ModelSim脚本控制 | 8项通过 | [历史modelsim_script_tests.log](../backups/2026-10-11_before_black_detection/results/history/2026-10-05/modelsim_script_tests.log)；真实Tcl和命令替身，不能证明原生仿真 |
| Icarus原五个testbench | 5项通过 | 坐标/求解/插值/标记/wrapper功能日志；没有新增三项 |
| 实际RTL与Python对比 | 坐标4329、求解器37、插值1000、整体像素2344 | 当时报告及RTL输出CSV |
| 原v3插值兼容 | 500组通过 | 当时调用原v3函数；原v3文件未改 |
| 原生ModelSim SE-64 2020.4 | 九个RTL、五个tb编译零错误/警告；`COORD_PASS 4329` | [用户原生日志](../backups/2026-10-11_before_black_detection/results/modelsim_user_coord.log)、[原生证据摘要](../backups/2026-10-11_before_black_detection/results/modelsim_native_evidence.json) |
| 其余原四项原生ModelSim | 未在用户日志中观察到通过 | 成功标志读取错误中断了原脚本，不能补写成通过 |

旧报告生成时间为`2026-10-05T03:42:28.304828+00:00`，旧报告和日志本次归档在`backups/2026-10-11_before_black_detection/results/history/2026-10-05/`。重新执行会更新常规结果文件；后续运行者也须在更新前归档会覆盖的证据，再记录新版本的实际结果。上表数字仅属于历史五项测试，不因后续接口版扩展到八项或本次黑检测版扩展到九项而自动变成全套通过。

## 保留的历史证据：2026-10-06四色接口v1补充

在当时接口补充副本中完成Icarus全套验证，最终输出`ALL_CHECKS_PASS`。报告时间（UTC）为`2026-10-06T14:42:24.564265+00:00`，操作系统为macOS；原生ModelSim和PDS未执行。

| 检查 | 历史结果 | 证据 |
| --- | --- | --- |
| Python模型 | 10项通过 | `backups/2026-10-11_before_black_detection/results/python_tests.log` |
| ModelSim脚本控制 | 11项通过 | `backups/2026-10-11_before_black_detection/results/modelsim_script_tests.log`，仅Tcl替身控制验证 |
| RTL完整清单 | 八项全部通过 | `backups/2026-10-11_before_black_detection/results/verification.json` 的 `rtl_test_results` |
| 可选实例化示例 | Verilog-2001编译通过 | `backups/2026-10-11_before_black_detection/results/example_syntax.log` |
| 缓存协议 | 48笔主请求通过；复位取消10笔队列请求；4笔复位后黑响应 | `backups/2026-10-11_before_black_detection/results/tb_cache_contract.log` |
| 完整wrapper联调 | 3427笔输入、3405笔请求、3330笔响应、3328笔输出；复位取消99笔，计数一致 | `backups/2026-10-11_before_black_detection/results/tb_b_integration.log`，其中22笔坐标/75笔缓存/2笔插值在途取消 |
| 同拍换帧 | 旧pending H1提交，新H0继续pending，通过 | 同一wrapper日志，真实solver完成脉冲 |
| 尺寸/数值边界 | 640x480、1920x1080、4096x4096，共43笔请求及输出通过 | `backups/2026-10-11_before_black_detection/results/tb_request_boundaries.log`，HD/最大尺寸是代表性回归，最终A/C模式仍待定 |
| 原v3兼容 | 500组通过 | 当时报告的 `v3_compatibility`，v3未修改 |

这是软件/RTL功能证据，不能替代DDR吞吐、视频帧率、PDS资源及时序或上板结果。新脚本曾在清单扩展后发现旧ModelSim入口只运行五项；改用共享清单后，八项全运行及失败停止控制均通过回归。

## 本版功能测试清单

Python和ModelSim运行器共同读取 [sim/tests.list](../sim/tests.list)。九项必须全部运行，不允许把五项或三项局部通过计为全套。每个testbench还必须在完整自检查后置`test_passed=1`。

本版ModelSim脚本控制回归共11项，使用Tcl命令替身检查清单、逐文件编译、示例编译和严格通过位读取等行为。当前结果与上方历史版本记录分开；控制回归通过也不能替代原生ModelSim。

| 顶层 | 成功标志 | 验收内容 |
| --- | --- | --- |
| `tb_perspective_coord` | `COORD_PASS` | 定点坐标、有效/错误、标签与流水行为 |
| `tb_homography_solver` | `SOLVER_PASS` | H系数、四边形拒绝与失败保持 |
| `tb_bilinear_interp` | `INTERP_PASS` | RGB插值、黑像素、标签和有效位 |
| `tb_marker_detector` | `MARKER_PASS` | 黑色质心、ROI身份、面积/跨度/越界拒绝、快照丢弃与复位 |
| `tb_marker_config` | `MARKER_CONFIG_PASS` | 奇数尺寸/局部ROI、非零黑阈值下界、非法源/阈值/统计/ROI配置、6对共享边界拒绝 |
| `tb_b_rectifier` | `VIDEO_PASS` | 原整体向量、换帧提交、失检保持和输出对比 |
| `tb_cache_contract` | `CACHE_CONTRACT_PASS` | 按序可变缓存延迟、响应空拍、逐笔模式切换、有效/黑色请求和元数据 |
| `tb_b_integration` | `B_INTEGRATION_PASS` | 采集与目的请求并行、帧内H保持、提交与solve_done同拍、在途事务复位 |
| `tb_request_boundaries` | `BOUNDARIES_PASS` | 640x480、1920x1080和4096x4096代表性源尺寸、首末行列/地址、错误分类及320x452合法贴边量化 |

每个复位代次分别检查请求、响应和输出计数；复位前已取消的在途请求不计入复位后的批次。黑色请求仍占一次响应和输出，元数据必须逐笔一致。A的真实队列实现也必须满足 [接口合同](interfaces.md) 的清空和晚到结果丢弃要求。

```text
python -B scripts/run_checks.py
```

只有全部九项、Python检查和实际RTL输出对比通过，才打印`ALL_CHECKS_PASS`。`--python-only`只能打印`PYTHON_ONLY_PASS RTL_NOT_RUN`。记录运行日期、工具版本、完整报告和日志；本版新增测试的通过状态不能从历史报告推断。

## 原生 ModelSim 全套记录：not_run

在包根目录执行`do run_modelsim.do`。脚本保存完整transcript到`results/modelsim_full.log`；九项的通过位都须严格读到单值二进制1，并出现最终`ALL_MODELSIM_CHECKS_PASS`。保存真实日志后才将下面状态改成`pass`；失败记`fail`并附失败顶层和原始报错。

| 字段 | 当前记录 | 负责人/填写依据 |
| --- | --- | --- |
| 状态 | `not_run`，未持有本版九项原生全套凭据 | A/B |
| 日期、操作者 | `pending` | 实际运行者 |
| ModelSim/Questa版本、操作系统 | `pending` | 工具版本输出 |
| 包版本/源文件校验 | `pending` | 实际运行目录与报告 |
| 清单 | `sim/tests.list`，9项 | 核对所有顶层均运行 |
| 完整原生日志 | 预定`results/modelsim_full.log`；运行前没有该凭据 | 保存完整transcript |
| 每项通过位 | `pending` | 9个`test_passed(binary)=<1>` |
| 最终标志 | `pending` | `ALL_MODELSIM_CHECKS_PASS` |
| 失败项/异常 | `pending` | 未运行时不填“无错误” |

## PDS 资源与时序记录：not_run

用实际器件、真实顶层和已确认处理时钟运行综合、布局布线及静态时序。操作步骤见 [board_pds.md](board_pds.md)。50MHz示例SDC不是最终时钟或测得Fmax。未知数字保留`pending`，不得填0或估算为实测值。

| 字段 | 当前记录 | 负责人/填写依据 |
| --- | --- | --- |
| 综合/布局布线/静态时序状态 | 三项均`not_run` | A/B |
| 日期、操作者、PDS版本 | `pending` | 实际运行记录 |
| 实际选定器件/封装/速度等级 | `pending`；手册候选PG2L100H-6IFBG676 | PDS器件设置与实板核对 |
| 顶层与工程路径 | `pending` | 独立B检查或A/C完整顶层分别标明 |
| 实际SRC/OUT、阈值与节拍参数 | `pending` | [配置JSON](../examples/integration_config.json) 的最终值及工程覆写 |
| 实际处理时钟来源/目标频率/周期 | `pending` | PLL、实际约束和时序报告 |
| 约束文件与输入/输出/生成时钟 | `pending` | 保存实际SDC路径；勿用示例代替系统约束 |
| LUT使用/可用 | `pending` | 综合/布局布线资源报告 |
| FF使用/可用 | `pending` | 同上 |
| DRM使用/可用 | `pending` | 同上 |
| APM使用/可用 | `pending` | 实际器件库；不能用手册疑似740项当100H预算 |
| 最差setup/hold slack、未约束路径 | `pending` | 真实静态时序报告 |
| 目标时钟时序结果 | `pending` | `pass/fail`及关键路径；未实跑不得填通过 |
| Fmax（仅工具实际报告时填写） | `pending` | 附计算条件和真实报告；不从50MHz示例推断 |
| CDC检查、警告和锁存器 | `pending` | 真实工程结果 |
| 综合/布局布线/时序报告路径 | `pending` | 保存原始报告，便于复查 |

## 真实摄像头记录：not_run

| 字段 | 当前记录 | 负责人/填写依据 |
| --- | --- | --- |
| 状态/日期/操作者 | `not_run` / `pending` | B，A协助采集 |
| 摄像头/输入链路、分辨率/帧率 | `pending` | 真实设备和有效区模式 |
| 曝光、白平衡、灯光/背景 | `pending` | 可复现采集条件 |
| 原始RGB图片/视频路径 | `pending` | 保留转换前后色序说明 |
| 最终黑阈值、4 ROI、MIN/MAX_PIXELS、MAX_SPAN | `pending` | 样本统计与RTL参数覆写 |
| 逐ROI黑像素计数、跨度、角点及H | `pending` | 实际日志 |
| 缺标记/ROI内黑字黑物阴影/遮挡/反光/倾斜结果 | `pending` | 每种情况记录误检、失检和参数保持 |
| 贴边黑线及纸页完整性 | `pending` | 对照严格越界规则，记录演示接受条件 |

## 开发板与整机记录：not_run

| 字段 | 当前记录 | 负责人/填写依据 |
| --- | --- | --- |
| 下载/整机状态、日期、操作者 | `not_run` / `pending` | A/C，B协助算法检查 |
| 板型号/硬件版本、实际器件 | `pending` | 实板、官方例程和管脚核对 |
| 位流/工程/管脚约束路径 | `pending` | 真实下载文件 |
| 输入/DDR/B处理/显示时钟 | `pending` | 实际PLL与各域测量 |
| 源/目的/显示尺寸、窗口、RGB色序 | `pending` | 按最终配置记录 |
| DDR读延迟/吞吐/FIFO峰值/溢出 | `pending` | A真实供数测试 |
| 源帧锁定、按序响应、复位旧结果丢弃 | `pending` | A帧管理和队列检查 |
| HDMI初始化、HS/VS/DE与显示连续性 | `pending` | C/A整机检查 |
| 实际帧率、撕裂/黑帧/稳定运行时长 | `pending` | 实测，不从每拍一请求结构推断 |
| 日志/照片/视频路径 | `pending` | 可复查的真实证据 |

验证通过后，运行者同步更新本页和配置JSON中的状态、最终值及证据路径。保留历史结果与本次结果的日期和工具版本，避免将单模块通过写成整机通过。
