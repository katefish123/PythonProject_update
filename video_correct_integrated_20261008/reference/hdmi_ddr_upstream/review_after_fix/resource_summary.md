# 资源与布线摘要

来源：当前 `after/reports/synthesize/HDMI_IN_DDR3_ROI_top.snr`（2026-07-12 18:57:09）与 July-10 baseline `codex_backups/20260710_stage1_baseline/reports/HDMI_IN_DDR3_ROI_top.snr`。baseline 是可用的较早前快照，不是 S02F1 的精确前快照。

| 资源 | 修改前 baseline | 修改后 | 变化 |
|---|---:|---:|---:|
| LUT | 8266 | 8184 | -82 |
| LUT as Distributed RAM | 39 | 39 | 0 |
| LUT as logic | 8227 | 8145 | -82 |
| FF/Register | 7288 | 7294 | +6 |
| Distributed RAM | 39 | 39 | 0 |
| BRAM/DRM | 10.0 | 10.0 | 0 |
| DSP/APM | 0 | 7 | +7 |

当前综合报告的 Cell Usage 还显示：`GTP_DRM18K_E1=12`、`GTP_DRM36K_E1=4`、`GTP_APM_E2=7`、`GTP_DFF*` 合计由实现映射统计为 7294 个寄存器。DSP/APM 增加来自 RGB2YCbCr 算术映射，不是 BRAM 增长。

## 路由网络

| 指标 | S02F1 PNR | 当前 PNR |
|---|---:|---:|
| Total nets for routing | 12481 | 12474 |
| Total subnets | 12479 | 12472 |
| Total route nets size | 12446 | 12439 |
| 最终 Unrouted nets | 0 | 0 |
| PNR 状态 | placed and routed successfully | placed and routed successfully |

注意：工程中的 `place_route/fail_route_nets.txt` 时间为 2026-05-02，属于旧产物，未作为当前未布通网络计数。
