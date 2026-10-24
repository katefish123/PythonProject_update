# 当前合格待实景验收包（2026-10-24）

完整包：`D:/FPGA/deliveries/FullHD_Lens_IntegratedRepair_20261023`。
ZIP SHA256：`fe9e9e76a9c01ec1daa3d4b9a092bf9adfffbabfee54c101e8686b32a6562ae8`。
bit SHA256：`c12913626e11352f5fbeefe468c63bfd52718209212561d4ca727ad741f65c22`。
mask SHA256：`66ce304dd10cac45be1f5538116c2ce738b5d267e924384a20300144cfcf5ddc`。

本次完整PDS成功退出，同一DB独立最终报告10节100行通过，最小+0.015ns。源码、实际回归、物理端口及码流资格绑定通过。866项manifest和ZIP CRC核验通过；包已在新目录实际Compile、完整RAW4147200像素及迟到模式仿真通过，连续六帧搬迁仅prepare-only，原候选六帧通过记录保留。独立审查无P0/P1/P2交付阻断项。四坐标扇出属性试验未选入本包。

已交“明确烧录专用需求”聊天（01a138e8-582f-7090-8ece-6119c3df7598）。开发聊天未操作下载器、OBS或采集卡。仅该窗口按用户授权做CRAM Program/Verify并执行包内四行预取复验步骤，不写Flash。

待确认：完整链路的实景白灰问题、RAW/校正画质、实际新图率、延迟与长期稳定。正式标定、光学与质量指标、局部纸框/框外保持等赛题缺项尚未完成；不得据离线资格宣称可交赛或实板已修复。

独立审查：`D:/FPGA/output/integrated_repair_handoff_review_20261024.json`。
新目录复验：`D:/FPGA/output/integrated_repair_portable_checks_20261024.json`。

烧录窗口已实际再次通过新包check-only，并尝试CRAM。下载器USB Cable II识别，但未扫描到FPGA，尚未写入新bit；当前需恢复板电源/JTAG后由该窗口继续。这是上板连接阻塞，不撤销离线资格。日志：`D:/FPGA/deliveries/FullHD_Lens_IntegratedRepair_20261023/program_logs/20261024_002253_846474/program.log`。
