# A 完整工程同步：后续集成基线

本目录同步自 A 的固定提交 `6b0b2e257efcfbb379d3f447403beb5ad08e0086`。后续先复用 A 的完整集成流程，C 前两轮新增的三源槽模块保留为候选扩展，不替代已实测基线。

## 同步内容

- `accepted/`：A 的 `release/ddr_camera_reconnect_20261011/source_snapshot.zip` 原样展开，包含完整编译源闭包、DDR IP、板约束、B 算法与 C 时序依赖。对应 109 个源码文件逐字节通过 A 原始 `source_hashes.json` 核对。归档还含构建入口，原绝对路径需要迁移后才能在新目录构建；不能直接运行原下载脚本。
- `hires_candidate/`：按 A 的 `diagnostics/ddr_camera_hires_prefetch_20261012/results/source_hashes.json` 重建完整 109 个编译源码文件，全部哈希匹配。保留 A 的高清采样和连续读取修复；仅同步，不代表重新构建或上板验收。
- 每个目录中的 `sync_manifest.json` 使用相对路径，记录各编译源码的 SHA256。`upstream_*` 为 A 原始资格记录。
- `upstream_records/`：A 最新接续、基础版恢复证据、暂停状态与 HDMI 来源许可证。记录中的“当前板上”仅指 A 当时的现场状态，本轮没有检查硬件状态。
- `accepted/sim/` 六个 testbench 和 `accepted/vendor/b/vectors/` 为同一个 A 提交提供的附加验证文件，不在 109 项编译源码清单内。

原始 A 编译源码未改；B 的新黑色角标压缩包未替换 A 的四色角标算法。大型录像、历史编译数据库及码流保留在 A 原分支，本目录同步开发所需的源闭包与资格记录，没有合并整个 A 分支。

## A 已完成，直接复用

| 功能 | A 模块 | 当前处理 |
| --- | --- | --- |
| 源采样及 RGB32 打包 | `ddr_snapshot_capture` | 复用，不重写采样器 |
| RX → DDR UI 异步数据通道 | `async_packet_fifo` | 复用；A 已有溢出作废测试 |
| 源帧写入和排空确认 | `ddr_capture_writer` | 复用；确认完整源、FIFO 排空及写应答 |
| 跨时钟内存命令 | `ddr_command_bridge` | 复用 |
| 三路争用与 DDR 控制接口 | `ddr_arbiter3`、`ddr_word_engine` | 复用 |
| B 算法调度、像素读取 | `frame_processor`、`ddr_pixel_cache` | 复用；单像素信用控制已有实现 |
| 结果打包写入和双缓冲 | `ddr_result_writer` | 复用 |
| 完整结果发布及显示确认 | `frame_session` | 复用；源快照在处理期间保持不变 |
| 结果读出和 HDMI 时序 | `ddr_result_display`、C VTC/PLL | 复用 |
| DDR 读写自检 | `ddr_self_test` | 复用 |

## 更正前两轮的推进范围

A 当前基础版采用一个不可变源快照和两个结果银行，源为 640×480，结果为 320×452，现有内存分区没有本轮指出的重叠问题。冲突只发生在将 C 新增的三个全高清源槽直接套用到 A 固定结果基址时。

因此三源槽、全高清地址表、独立 `ddr_capture_session` 都属于另一路扩展方案，不能作为 A 当前缺项，也不应先强行迁移 A 已验收结构。相关独立仿真仍有价值，后续需要更高采集并发时再评估是否采用。

## 本轮重新验证

在本目录运行 `vsim -c -do run_accepted_checks.do -l verification/accepted_checks.log`，使用 ModelSim 2020.4：

| A 原测试 | 本轮结果 |
| --- | --- |
| DDR 字命令引擎 | `DDR_WORD_ENGINE_PASS` |
| 像素缓存 | `DDR_PIXEL_CACHE_PASS`，11 次内存读取 |
| 异步命令、仲裁、结果打包、自检 | `DDR_HELPERS_PASS` |
| RX 异步采集、短行/短帧/溢出拒绝及复位恢复 | `DDR_CAPTURE_PASS` |
| 两结果银行显示、行预取超时及 VTC 对齐 | `DDR_DISPLAY_PASS` |
| 完整 DDR 校正核心 | `DDR_CORE_PASS`，5425 条命令、1536 次采集写、288 次结果写、1152 次显示读、3 次发布 |

六项均通过。前五项零错误、零警告；完整核心零错误、12 条警告，来自 A 原 `frame_processor` 未连接 B 的 11 个观测输出，未修改原源码或隐藏警告。该核心测试包含多阶段复位，末尾的 good/rejected 计数不是全程累计帧率指标。

这是同步后的小尺寸功能回归，不等于本轮重新验证基础版现场稳定性，也不证明高清候选版实际清晰度或更新帧率。原始日志在 `verification/accepted_checks.log`。

## 接下来实际要做的事

1. 从 `hires_candidate/` 继续 A 的连续读取修复，核对其完整构建与时序资格，迁移本机路径，复现候选版检查及构建。
2. 保留基础版回退后，再做高清版真实相机完整页、黑行、闪烁、清晰度与重连验收。当前仅有 A 保存的基础版约 52 秒稳定记录，未继承为高清资格。
3. 测量算法实际更新速度和 DDR 争用，依据数据决定是否需要三源槽、突发写或其他吞吐优化。
4. B 新黑色角标版属于独立算法配置变更，若采用需配套目标图、ROI 和阈值验证，不能只换算法文件。
