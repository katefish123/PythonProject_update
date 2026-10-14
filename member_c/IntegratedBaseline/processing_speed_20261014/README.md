# 全高清校正处理调度提速

本轮接续 `fullhd_source_20261013`，改善逐帧校正等待时间。完整保留1920×1080源像素、640×904竖向结果与原双线性插值算法。HDMI输出仍为1920×1080、60 Hz。

## 实现

新增覆盖文件只有 `diagnostics/ddr_camera_hires_20261011/results/frame_processor.v`。复用上一版两个全高清覆盖文件，以及A固定提交 `6b0b2e257efcfbb379d3f447403beb5ad08e0086` 的DDR、采集、缓存、显示和B算法。

- 预先计算最多8个后续像素坐标，队列记录标签、四邻域地址、权重和有效性。信用同时包含管线中的请求及已返回队列项，在取出描述符时释放。
- 上一笔像素读取返回时，允许下一笔读取同时握手，减少源图扫描及四邻域读取之间的等待。
- 内存仍最多一笔未完成读取；结果仍逐像素有序写入，整帧写完才发布。写等待不会改变输出内容。

缓存响应必须是对应已接受请求的注册响应，不支持组合零周期返回。异常后由现有帧会话复位处理器与缓存；不改变原工程对于旧内存响应隔离的约定。

## 复现

在仓库根目录运行，ModelSim需要在PATH中。准备脚本先重建上一版完整闭包，再应用本轮覆盖及性能验收条件。

```powershell
$speed='member_c/IntegratedBaseline/processing_speed_20261014'
$shared='member_c/IntegratedBaseline/a_sync_20261013'
$out='D:/FPGA/output/c_processing_speed_new'
python "$speed/prepare.py" --output $out
& "$shared/run_hires_reproduction.ps1" -OutputRoot $out -RequiredChecks 17
& "$shared/build_hires_reproduction.ps1" -OutputRoot $out -RequiredChecks 17 -PdsExe 'D:/softwares/PDS/PDS_2022.2-SP6.4/bin/pds_shell.exe'
python "$shared/package_hires_reproduction.py" --root $out --build "$out/build_实际生成时间" --output 'D:/FPGA/output/processing_speed_package_new' --expected-tests 17
```

原16项回归继续执行。全高清校正测试增加24,000,000周期上限；新增随机内存等待、长写停顿、越界黑像素、处理中复位恢复及最近邻/双线性模式测试。测试先在旧调度器上确认性能门槛失败，再验证新实现。

## 仿真结果

17项回归全部通过，零错误、零警告。实际生产配置检查通过；源像素2,073,600个完整采集，578,560个校正像素逐一匹配固定版本B的定点参考模型。

| 同一全高清测试 | 旧版 | 本版 |
| --- | ---: | ---: |
| 处理周期 | 29,972,848 | 12,864,714 |
| 按27 MHz换算的模型处理时间 | 1.110秒 | 0.476秒 |
| 结果像素 | 578,560 | 578,560 |
| 源缓存读取次数 | 643,285 | 643,285 |

周期减少57.08%，相同工作量的模型处理速度约为原来2.33倍。采集、等待帧边界及显示发布开销不包含在处理周期内，因此不能直接当成板上更新频率。详细数字和前后日志哈希见 [performance.json](performance.json)。

随机等待测试中，双线性模式46,922→22,301周期，最近邻模式33,693→11,514周期。测试包含处理中复位后重新完成整帧，结果地址连续，受阻输出稳定，越界结果为黑色。

## 码流交付

2026-10-14：PDS完整编译成功，最终保持时间修复后的时序报告为 `All Constraints Met`。构建目录为 `D:/FPGA/output/c_processing_speed_20261014/build_20261014_082942`。

[release](release/) 包含码流、掩码、17项仿真日志、最终时序、构建日志、原生测试图及来源清单。`package_manifest.json` 绑定27个文件；准备、仿真、构建和打包均校验同一源码清单。PDS综合与布线诊断保留在构建日志中，仿真零警告不表示PDS零警告。

码流SHA256：`0cd20e384d5f9ad2098f38c66f59ead141dafeda5f0bfdaf0a1637e13176db29`。

`hardware_accepted=false`，该交付尚未烧录到板子。上一版码流继续保留，可用于现场对照。

## 未完成的工作

本次减少单帧处理时间，尚未实现连续采集与校正的多源帧缓冲并行。仍是采集完整快照、处理并发布后，再采集下一帧；不能据此宣称流畅实时视频或每秒60次校正。

本轮未烧录、未进行相机到屏幕的板级验收。实际更新频率、长期运行、相机重连及真实图像清晰度仍须接回硬件验证。仿真周期换算时间不等于实际板上帧率。
