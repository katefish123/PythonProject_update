# 黑标记检测修改记录（2026-10-11）

本次把红/绿/黄/蓝四色四角检测改为统一黑色检测，使用4个ROI确定TL/TR/BR/BL身份。Python与RTL同步修改，端口、RGB输入输出、逆透视求解、坐标数值和缓存合同保留。

## 修改范围

- `python/brect/golden.py`：统一`black`阈值、默认四象限或自定义ROI、闭区间/整数/不重叠验证、逐ROI统计与质心。非法配置抛`ValueError`。
- `python/brect/cli.py`：新增`--rois`，静态与摄像头共用黑检测配置；帮助文本和阈值格式迁移。
- `rtl/marker_detector.v`：6个`BLACK_*`阈值、16个`P0..P3_*`ROI参数，合法源/统计/阈值/ROI检查，非法帧拒绝。仍采用原质心除法和帧首末/忙丢弃机制。
- `rtl/b_rectifier.v`及`examples/b_rectifier_instance.v`：完整转发新阈值/ROI参数，保留输入输出端口。
- 演示和向量生成：4个黑标记；小场景亮背景供默认四象限检测，大演示保留黑正文并采用局部ROI，提供`rois_demo.json`。
- 模型/testbench：补黑阈值、ROI身份、边界/干扰、非法配置和wrapper参数传递回归；共享清单新增`tb_marker_config`，全套为9项。
- 文档：重写README入口，增加逐文件指南、黑标记/迁移说明；接口、集成、硬件和验证资料更新当前合同，历史证据明确标记。

## 兼容变化

旧Python四色阈值字典及RTL的24个`R_* / G_* / Y_* / B_*`阈值参数删除。新的顶层有8个既有系统参数加22个检测参数，共30个；阈值和ROI都是编译/综合时参数。外部端口不变，A需更新参数覆写。JSON不自动写入RTL。

黑标记检测没有连通域分离。ROI内黑正文/背景共同影响质心，默认四象限只适合干净场景；实际纸张应根据标记位置配置局部窗口。标记中心仍应代表纸角。

## 完整备份与历史隔离

原路径`/Users/yishuyu/Documents/FPGA/PythonProject_local/member_b_perspective_final/`保持原样。上一级`member_b_perspective_original_2026-10-11.zip`是修改前完整工程，245文件、10,427,777字节；`source_backup_manifest.json`记录逐文件SHA256校验。

旧`results/`、ModelSim `work/`和`modelsim.ini`移到`backups/2026-10-11_before_black_detection/`，原已有的`2026-10-06_before_interface_v1_supplements/`保留。局部历史归档不能替代完整ZIP；旧四色日志/库不能用于当前黑标记通过结论。

## 验证入口

```text
python -B scripts/run_checks.py
python -B scripts/make_demo.py
```

完整suite实际状态/日期/计数以`results/verification.json`及当次日志为准。CLI演示须带`--thresholds examples/thresholds.json --rois examples/rois_demo.json`。原生ModelSim全套、PDS、真实摄像头、DDR/HDMI和开发板另行实跑记录，见 [validation_record.md](validation_record.md)。
