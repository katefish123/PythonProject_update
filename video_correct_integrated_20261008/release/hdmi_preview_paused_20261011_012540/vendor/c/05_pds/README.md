# V5 HDMI OUT PDS 工程

器件：PG2L100H / -6 / FBG676（板卡完整型号 PG2L100H-6IFBG676），工具：PDS 2022.2-SP6.4，顶层：`hdmi_colorbar_top`。

## 打开与重建

用 PDS 打开本目录 `VideoTimingSim_V5.pds`，从 Compile 依次运行 Synthesize、Device Map、Place & Route、Report Timing、Generate Bitstream。提交的工程保留相对路径、源文件时间戳与选项，清除历史成功状态及缓存引用；新电脑打开后需要重新构建。9 个正式源文件包含两个真实 GPLL，不加入 Testbench 或 GPLL 仿真模型。芯片原语由 PDS 库提供。

命令行构建（PowerShell，在本目录执行）：

```powershell
& 'D:\softwares\PDS\PDS_2022.2-SP6.4\bin\pds_shell.exe' -file build_v5.tcl -work_dir "$PWD" -project_name VideoTimingSim_V5
```

也可从已有工程重建：

```powershell
& 'D:\softwares\PDS\PDS_2022.2-SP6.4\bin\pds_shell.exe' -project VideoTimingSim_V5.pds -run gen_bit_stream
```

更换电脑时只改 PDS 安装路径。构建会更新 `.pds`，中间文件已排除出 Git。

## 管脚与时钟

`mes2l676_hdmi_out.fdc` 覆盖 34 个端口，全部 LVCMOS33 / 3.3V。HD_TX_D[23:16]=R、[15:8]=G、[7:0]=B；27MHz=D18，输出PCLK=T24，SCL=K22，SDA=K23，HDMI芯片共同复位=G25。KEY0=C22，按下使 `rst_n=0`；LED2=C19 显示初始化标志，不代表显示器连接或出图。

来源：本地官方《教程1_硬件实验指导手册_盘古676_100ProPlus》，PDF 第23、47～51页（正文第19、43～47页）。已逐项对照 Device Map PCF 和布线后 IO 表，34 个位置一致。HDMI芯片与相关外设共享 I²C 引脚，本工程只主动配置 MS7210。

27MHz输入约束周期37.037037ns；工具从真实PLL自动推导148.5MHz视频时钟和10MHz配置时钟。未填入未经验证的MS7210外部setup/hold、板上走线偏差或I²C输入延迟，因此会保留端口时序警告。

## 已生成的成果与上板边界

完整流程返回0，下载文件与原始报告归档在 `../04_results/pds_v5`；下载文件为 `hdmi_colorbar_top.sbit`。内部慢角建立余量：视频4.475ns，配置96.173ns；快角保持余量：视频0.252ns，配置0.131ns。报告的“All Constraints Met”仅对已施加约束成立，不代表外部HDMI接口时序已收敛。

本码流尚未上板。上板前需复核异步复位释放、SDA驱动与I²C应答/异常处理、RGB寄存器配置以及输出采样关系。先用JTAG临时下载，按住再松开KEY0，观察LED2、采集卡/显示器识别分辨率及彩条颜色；记录板卡、码流SHA256、初始化和连续运行情况。现场核对上述问题后再决定是否写入启动Flash。
