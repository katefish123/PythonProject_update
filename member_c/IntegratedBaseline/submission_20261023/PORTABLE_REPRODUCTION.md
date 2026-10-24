# 从完整交付包的新目录复现

以下操作只编译或仿真，不连接下载器或采集卡。先解压ZIP，进入含`MANIFEST_SHA256.json`的包根目录。包内`tools/program_package.py --check-only`核对完整性，不烧录；不要省略`--check-only`。

## 当前显示器与writer的完整链路回归

```powershell
python tools/program_package.py --check-only
python tools/reproduce_display.py --package . --case late_mode_reset --output D:/FPGA/reproduce/fresh_late --modelsim D:/softwares/modelsim/win64
```

输出目录必须不存在。可选case为`shared_raw_sparse`、`native_corrected`、`continuous6`、`late_mode_reset`、`midblank_wrap`。前三项分别核对当前生产源码的共享RAW、完整校正和六幅变化内容；后两项核对相同显示器的迟到响应/模式/复位及中途发布/epoch回绕。加`--prepare-only`只准备快照，不运行仿真，不能算测试通过。工具绑定源码、测试激励和黄金图，仅重定位黄金图文件路径；必须看到`RELOCATED_DISPLAY_REGRESSION_PASS`才算该项实际通过。

`prepare_continuous_check.py`和其他历史生成器作为来源归档，依赖原工作树及旧父版资格，不能替代当前包的`reproduce_display.py`入口，也不能把父版回归算作新版writer回归。

## PDS工程与完整重建

```powershell
$packageRoot = (Get-Location).Path
$pdsExe = 'D:/softwares/PDS/PDS_2022.2-SP6.4/bin/pds_shell.exe'
$compileDir = 'D:/FPGA/reproduce/fresh_project_compile'
New-Item -ItemType Directory -Path $compileDir -ErrorAction Stop
Push-Location $compileDir
& $pdsExe -f (Join-Path $packageRoot 'tools/create_project.tcl')
Pop-Location
```

该入口重新创建并编译工程。完整综合、映射、布局布线及码流生成使用`tools/rebuild.tcl`，同样从另一个全新目录运行。重建后必须重新检查最终时序，不能因原包通过就给新生成码流沿用资格。包内原资格和哈希只对应原交付码流。打开包内现成PDS可查看工程；新目录编译用于确认解压后的相对路径与源码依赖有效。

## writer专项复跑

把`validation/writer_credit/registered`复制到全新目录，在该目录依次执行本机ModelSim的`vlib.exe work`、`vlog.exe -sv ddr_result_writer_burst64.v tb_writer_burst.sv`和`vsim.exe -c tb_writer_burst -do "run -all; quit -f"`。看到`PASS burst writer credit pipeline stress`且编译/运行均零错误警告才通过；这不替代上面的完整图像链路回归。

## 上板与回退

硬件仅由烧录窗口控制，按`四行预取复验步骤.md`执行。`fallback/rx_only`仅为已确认运动跟随的降采样接收诊断，不能作为完整校正成果；包内保留其bit/mask、原始资格、Program/Verify和运动观察记录。所有上板操作仅CRAM，不写Flash。

可对烧录窗口保存的原生1920×1080诊断PNG离线运行`python tools/decode_board_hud.py <截图目录> --glob "*.png" --output hud.json`，需要本机NumPy/OpenCV。默认按图像本身方向读取；旧DirectShow倒置采样另加`--capture-inverted`，它只改变采样方向、不修改图片，不能据此判断FPGA颠倒。无匹配文件会报错；`decoded_fields`为空或含无法识别的行时，应保留原图核查，不能计算帧率。row03的RAW/校正计数与实际PIX模式见验收步骤。OBS后台采集仅由烧录窗口操作，开发不连接采集卡。
