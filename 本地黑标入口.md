# B 队友最新黑标代码

本地 `main-B` 已同步到提交 `4106f3babb65096927d365bbab55f070b90325e2`（2026-10-12）。上游最新提交新增的是 `member_b_perspective_black.zip`，原 `final/` 仍是旧四色版，不能从旧 `final/README.md` 判断最新算法。

新版 ZIP 已独立解压到 `member_b_perspective_black/`；先读该目录的 README 和 `docs/black_markers.md`。ZIP SHA256：`b6a476ae2307a34455c21dd7c9a2f94ca583ca111d3e43cfbb1bbbbd7fa9aceb`。

它使用四个独立搜索区域内的黑像素质心，不包含完整板级顶层。接入 A/C 的独立工程位于：

`C:\D\FPGA\video_correct_integrated_20261008\diagnostics\ddr_camera_black_20261014`

现有 B 原始代码保持原样，FPGA 综合适配与系统接线变更保存在该独立工程内。
