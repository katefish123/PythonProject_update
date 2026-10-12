# 构建摘要

没有重新运行构建。以下均为最新已有日志中的正式 done 标记。

| 阶段 | 正式 done | 证据 |
|---|---|---|
| Compile | 是 | `after/logs/run.log:3903`，`Process "Compile" done.` |
| Synthesis | 是 | `after/logs/run.log:8566`，`Process "Synthesize" done.` |
| Device Map | 是 | `after/logs/run.log:9420`，`Process "Device Map" done.` |
| PNR | 是 | `after/logs/run.log:10305`，`Process "Place & Route" done.`；PNR 另有 `placed and routed successfully` |
| Report Timing | 是 | `after/logs/run.log:10452`，`Process "Report Timing" done.` |
| Bitstream | 是 | `after/logs/run.log:10541`，`Process "Generate Bitstream" done.` |

最新阶段日志：

- Compile：`after/logs/compile/run.log`
- Synthesis：`after/logs/synthesize/run.log`
- Device Map：`after/logs/device_map/run.log`
- PNR：`after/logs/place_route/run.log`
- Report Timing：`after/logs/report_timing/run.log`
- Bitstream：`after/logs/generate_bitstream/run.log`
- 总 flow：`after/logs/run.log`、`after/logs/flow.log`

补充：PNR 日志有 `hs_in` dangling 的单条 failed constraint 命令；它没有阻止 PNR 完成，但必须作为接口/约束风险处理。
