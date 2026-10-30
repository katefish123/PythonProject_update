# V5 PDS 构建结果（2026-10-05）

PDS 2022.2-SP6.4 build146967，目标PG2L100H/-6/FBG676，顶层hdmi_colorbar_top。Compile、ADS综合、器件映射、布局布线、时序报告和生成码流全部成功，完整流程退出码0；清除工程缓存引用后，`.pds`重新打开并Compile成功。

- `build_console.log`：完整流程日志；有警告，不称为0警告。
- `synthesis.snr`、`device_map.dmr`、`place_route.prr`：各阶段报告。
- `mapped_pins.pcf`：映射后的34个管脚，与FDC和布线后IO表一致。
- `timing.rtr`：内部时序通过；视频建立WNS4.475ns、配置96.173ns，快角保持0.252ns/0.131ns。
- `bitstream.bgr`：码流生成报告。
- `hdmi_colorbar_top.sbit`：本轮生成的3791112字节下载文件，尚未实板验证。
- `verification.json`：版本、管脚核对、码流大小与SHA256。
- `portable_open_check.log`：可分享工程重新打开和编译检查。

警告包括：未施加MS7210外部I/O延迟、复位输入延迟；驱动中的冗余寄存器被优化、命名冲突自动重命名和constant probe循环提示。后者未阻止流程，但不能据此证明I²C电气行为正确。许可证剩余时间提示来自本机环境。

外部I/O时序未闭合、异步复位释放/I²C应答及电气行为待复核、显示器彩条未验收。不能把“内部时序通过＋码流生成”记录成“HDMI已经出图”。
