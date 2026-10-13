# A 高清候选版本机复现与 C 接续

日期：2026-10-13。A 提交 `6b0b2e257efcfbb379d3f447403beb5ad08e0086`；核对远端时 A、B 没有新增提交。直接复用 A 的完整 DDR 集成，不引入 C 独立三源槽，不替换 B 黑色角标版本。

## 已完成

- A 的 108 个 RTL/IP 文件与 1 份板约束逐字节保持一致。构建、测试和夹具共 141 个输入，只迁移测试与构建脚本的绝对路径。
- 12 项 ModelSim 仿真全部通过，零错误、零警告。包括完整 640×904 结果图的 578,560 像素比对、预取控制、采集/处理/显示共享内存压力与字命令引擎。
- PDS 2022.2-SP6.4 完整构建通过，最终 hold 修复后的时序报告为 `All Constraints Met`。PDS 综合有常量裁剪等警告，仿真的零警告不代表综合零警告；完整日志随包保存。
- 本机构建码流 SHA256：`4f0e91e09d5fc90d4873dfd220388522b3ee45a84d3ef52488bcb5086e360e81`。它是本机重新构建的产物，与 A 历史码流分开记录。
- 输出仍为 1080p60，源采样 960×540，校正结果 640×904。HDMI 输出帧率不能当作算法每秒更新次数；需要实测更新速度。

## 交付文件与复现

`release_hires_20261013/` 包含 `.sbit`、`.smsk`、12 项仿真日志、完整构建日志、最终时序报告、输入哈希和资格记录。`package_manifest.json` 使用相对路径绑定每个交付文件的 SHA256，明确 `hardware_accepted=false`。原始资格文件保留本机绝对路径，供追溯；跨机器校验使用包清单。

在仓库根目录运行，要求 Python、ModelSim `vsim.exe` 在 PATH，且本地已有上述 A 提交（需要时先 `git fetch origin main-A`）：

```powershell
$scripts='member_c/IntegratedBaseline/a_sync_20261013'
$output='D:/FPGA/output/a_hires_repro_new'
python "$scripts/prepare_hires_reproduction.py" --output $output
& "$scripts/run_hires_reproduction.ps1" -OutputRoot $output
& "$scripts/build_hires_reproduction.ps1" -OutputRoot $output -PdsExe 'D:/softwares/PDS/PDS_2022.2-SP6.4/bin/pds_shell.exe'
python "$scripts/package_hires_reproduction.py" --root $output --build "$output/build_实际生成时间" --output 'D:/FPGA/output/hires_package_new'
```

仿真前后验证输入哈希，资格绑定 manifest 摘要与 A 提交；构建要求资格匹配并在结束后再验输入，避免改了源码仍沿用旧通过记录。输入篡改及 manifest 不匹配两种拒绝路径已验证。

本轮第一次 12 项回归后即启动 PDS，随后审查补上证据绑定，并重新跑完整 12 项回归。已启动的构建使用旧脚本，故本次包明确记录为“构建完成后重新校验，并绑定重跑仿真”，不声称它使用了新脚本的前置门禁。源码没有变更，打包再次核对输入、日志、时序与码流哈希。

## 尚未完成的现场验收

本轮系统未识别到 FPGA 下载器和 VC-002Pro 采集卡，因此没有执行烧录，也没有声称高清画面已经通过验收。

设备恢复后按以下顺序继续：

1. 确认当前 JTAG 器件及可回退基础版，核对本包码流哈希，下载 CRAM 并回读校验。
2. 相机经 FPGA 接采集卡，拍完整四色角标目标页；保存原始输入和校正输出，检查完整页、文字清晰度、黑行及闪烁。
3. 实测首次出图、持续更新、相机 HDMI 断开重连及板复位恢复；记录错误计数和录像证据。
4. 依据算法更新时间和 DDR 争用数据决定下一步优化。暂不把三源槽、独立全高清采集或更换 B 角标算法列为既定修改。
