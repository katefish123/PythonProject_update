后续连续采集、全高清源图和刷新优化见 [stream_video_20261015](../stream_video_20261015/README.md)。本目录保留原候选的独立验证记录。

# 全源图黑标、采集突发与恢复整合（2026-10-15）

开发分支 `c-pipeline-next`。完整源图仍1920×1080，透视结果仍640×904；B原始9个RTL保持。未执行烧录或OBS操作。

已闭环的独立时钟修改：仅转发可能贡献黑标统计的ROI像素和始末/异常事件，经小FIFO送入27MHz原B检测器；完整源图照常写DDR。22项回归和最终PDS通过，RX setup WNS −1.812→+1.597ns。见[绑定证据](clock_validation/manifest.json)。这份时钟候选未合并板上burst/preview，不作为板上替换包。

`merge_board.py` 在此基础上整合原子8拍采集、两源bank范围和缓存失效、原始预览/状态提示、失败原因及帧恢复；保留C源预取和A行读取。原生DDR仿真按AWLEN和每次WREADY逐拍更新内存，包含同拍AW/W和停顿。

最终合并候选 `D:/FPGA/output/c_black_burst_merge_v3_20261015`：33项统一回归、额外旧/新显示逐像素检查、PDS构建及最终时序全部通过。RX setup=+1.449ns、pixel=+0.585ns、UI=+1.097ns；核对错误期间旧显示16896像素、恢复后新显示768像素。见[交接包](delivery/README.md)和[逐文件证据](delivery/manifest.json)。sbit SHA256=`8b1b07ad67043c27cd4c47ec297afb8b5f92906fcce51dd7ee6e38afa84ec855`。尚未烧录或硬件验收。

归档依赖后重新生成的13个C生产源码、9个B原始源码及全部14个hex数据文件逐字节一致，27个测试源码仅输出目录不同。见[复现检查](frozen_dependency_reproduction.json)，该检查不继承或替代新仿真资格。Map资源：LUT19087/66600、FF25688/133200、APM53/240、DRM66/155；原始报告在交接包中。

```powershell
python ./merge_board.py --output D:/FPGA/output/NEW_UNIQUE_OUTPUT
../inline_geometry_20261014/compile_preflight.ps1 -OutputRoot D:/FPGA/output/NEW_UNIQUE_OUTPUT
../fullhd_pipeline_20261014/run_verified.ps1 -OutputRoot D:/FPGA/output/NEW_UNIQUE_OUTPUT -RequiredChecks 33
../a_sync_20261013/build_hires_reproduction.ps1 -OutputRoot D:/FPGA/output/NEW_UNIQUE_OUTPUT -PdsExe D:/softwares/PDS/PDS_2022.2-SP6.4/bin/pds_shell.exe -RequiredChecks 33
```

先配置ModelSim可执行文件路径；输出目录必须新建。原子writer、preview/overlay及7项测试的必要来源已逐文件冻结到 `board_snapshot/`，附SHA256、板上基线来源与测试复制差异，生成器会核验，不再依赖本机旧输出目录。其余依赖为仓库内前序生成器、固定Git提交6b0b2e2、Python/NumPy/Pillow、ModelSim和指定PDS/IP；不是脱离这些工具的一键构建。

尚未完成：实际板测、60张不同校正图/秒、真实相机镜头标定、径向/切向硬件映射与完整参数提交、MTF/SFR/直线度等画质量化。最终v3三帧平均启动间隔508.319ms，约1.97张/s的模型样本，不能称为实时成果。镜头浮点/定点软件参考17项测试通过，尚未接入RTL。[赛题差距](../compliance_20261015/README.md)、[镜头参考](../lens_model_20261015/README.md)及[后续实现顺序](NEXT_STEPS.md)分别留档。
