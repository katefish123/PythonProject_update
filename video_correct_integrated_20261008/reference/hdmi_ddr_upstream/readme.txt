HDMI 车牌框选系统（Pango PG2L200H / FBB676 / -6）

工程入口：HDMI_IN_DDR3_YCbCr.pds
顶层模块：HDMI_IN_DDR3_ROI_top
视频模式：1920x1080 @ 60 Hz，RGB888 输入，RGB888 输出

快速验证：
  powershell -ExecutionPolicy Bypass -File .\test.ps1

PDS 编译：
  powershell -ExecutionPolicy Bypass -File .\build.ps1 -Run compile

完整时序：
  powershell -ExecutionPolicy Bypass -File .\build.ps1 -Run report_timing

生成配置文件：
  powershell -ExecutionPolicy Bypass -File .\build.ps1 -Run gen_bit_stream

输出文件：
  generate_bitstream\HDMI_IN_DDR3_ROI_top.sbit

上板前确认 HDMI 输入源固定为 1080p60。实际环境中的颜色阈值、最小车牌尺寸和
跟踪保持帧数仍应使用比赛现场摄像头样本标定。
