# 镜头模型独立 RTL 数值基线（synthetic）

后续保持本文原RTL和证据，另在 [精确调度优化阶段](../lens_throughput_20261017/README.md) 验证了Brown350→158、组合652→288周期及隔离模块资源/内部时序。该优化仍未达到实时视频或企业镜头验收，不改变本文原基线的验证范围。

**尚未达到企业实机验收，也未接入整板或通过新PDS。** 佳能EOS R50仅是用户声明的机身型号；真实标定缺失，不能套用网络参数。V5C、B原代码和既有DDR/CDC/恢复链路未改变。

## 已实现和验证

- q30_alu.v：带符号Q34.30加/乘/迭代除法，128位中间量、最近偶数舍入、溢出/除零拒绝。
- lens_profile_bank.v：完整23字K/畸变/H/尺寸/模式/版本/frame id包校验，pending保持、帧边界原子提交；运行模式/尺寸变动立即失配，提交时重新检查。当前只接收synthetic provenance=1。
- lens_map.v：无畸变理想相机坐标到原始镜头图的Brown k1/k2/p1/p2映射。逐事务捕获参数，带符号越界、错误/tag/版本保持，背压/复位检查。
- lens_composed_map.v：目标坐标先经理想平面H，再镜头正向映射回原图。全包在最初请求同沿快照；其输出坐标在测试中只经过一次原B双线性采样，生产DDR采样接口尚未接入。
- corner_preparation.py：开发阶段的主机侧局部阻尼Newton原角点去畸变，复用B原浮点H求解。局部收敛不证明全局逆解唯一，也不生成真实相机标定。

4组RTL回归零errors/warnings；Brown及H+Brown分别1024坐标、1024采样像素与既有独立定点参考精确一致，浮点/定点最大样本坐标误差0.0005226414286880754源像素。包括非零projective H和全部Brown项同时作用，以及合成raw四角→逆畸变→理想H的准备流程。分别禁用k1/k2/p1/p2的4个故意错误配置全部被坐标测试拒绝；另有5项主机角点/H准备测试。见 [精确证据](verification.json)、[归档](evidence/synthetic_numeric_evidence.zip) 和 [审查修复](REVIEW.md)。

**性能尚未解决**：顺序基线Brown最多350周期/点，组合H+Brown最多652周期/点（测试所见）。这不是实时1080p实现，不能用保持画面或重复扫描掩盖吞吐。下一阶段需要流水线/资源设计和完整1920×1080处理路径、真实新图率/延迟、资源及全部最终约束验证。

源图坐标与测试保持1920×1080、16:9；模型不依赖四色角标。没有新增自动黑白图卡检测器，主机显式四角来自synthetic已知数据；没有实拍图的镜头矫正效果结论、MTF/SFR或实测物理比例。没有利用同图拟合或分段修图来解除验收门禁。

## 复现

```powershell
python -B member_c/IntegratedBaseline/lens_model_next/prepare_vectors.py
& member_c/IntegratedBaseline/lens_model_next/run_tests.ps1 -Suffix fresh_alu
& member_c/IntegratedBaseline/lens_model_next/run_tests.ps1 -Suffix fresh_bank -Bench tb_lens_profile_bank
& member_c/IntegratedBaseline/lens_model_next/run_tests.ps1 -Suffix fresh_brown -Bench tb_lens_map
& member_c/IntegratedBaseline/lens_model_next/run_tests.ps1 -Suffix fresh_composed -Bench tb_lens_map -Composed
```

新后缀保留独立编译源和向量快照。每次测试只替换bench中的向量路径；实际编译SHA另存。run_tests读取冻结B原bilinear_interp.v，不改其内容。prepare_vectors复用已有浮点/定点模型及B参考。collect_evidence.py固定收集本轮final输出目录，重做一轮需显式更新目录并核验。

[企业缺口门禁](../compliance_20261015/gates_20261017/GAP_AND_SEQUENCE.md) 继续保持NOT_READY；真实验收blocked_by_missing_calibration，同时独立合成开发继续推进。
