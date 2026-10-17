# HDMI 实时预览

在工程根目录启动本机预览和 HDMI 采集：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/start_hdmi_preview.ps1
```

浏览器打开 <http://127.0.0.1:8766/>。页面每 500 毫秒刷新一次画面；图像超过 5 秒未更新时会提示“采集已暂停，下面是最后一帧”。预览服务只监听本机地址。

停止本脚本启动的采集和预览服务：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/stop_hdmi_preview.ps1
```

启动脚本会从 `tools/python_packages/imageio_ffmpeg/binaries/` 选择 FFmpeg，并用本机捆绑的 Python 启动预览服务；采集日志按时间保存到 `results/hardware_20261009/`，不会覆盖已有日志。采集使用采集卡原生 MJPEG 并直接复制 JPEG 帧，避免经 NV12 解码后再次编码。若采集已运行，脚本会检查并在需要时恢复预览服务；重写 PID 记录前会验证并保留仍由本脚本管理的服务进程。脚本只管理 PID 记录中路径和命令行均匹配的进程，不操作 JTAG 或其他桌面窗口。

2026-10-09 的内部测试图对照显示，原生 MJPEG 直拷贝路径在零偏移下 ROI MAE 为 1.0624、p99 误差为 3，99.731% 像素的 RGB 最大通道差不超过 4，未发现黑行；最大差异集中在小型彩色角标边缘。目标灰度 152、200 和黑色分别采得 152、199 和 0。相同图案走 YUY2 转 PNG 时对应值为 155、211 和 0；走 NV12 转 MJPEG 时对应 RGB 值约为 204、255 和 28（原始 Y 值约为 193、241 和 42）。DirectShow ProcAmp 查询中支持的亮度、对比度、色调和饱和度均为手动 50，范围 0–100、默认 50；伽马和锐度等属性不受支持。当前测量显示 NV12 路径有明显亮度偏差，其具体成因尚未确认，不能据此归因于采集卡芯片或驱动固件。
