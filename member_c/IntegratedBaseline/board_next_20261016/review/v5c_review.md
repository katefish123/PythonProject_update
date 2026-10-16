# V5C 独立代码审查与修复

审查对象：整板接线、服务等待观测、当前/历史故障隔离、共同恢复。审查者只读检查，由主任务修复并运行回归。

1. 诊断快照延迟可能重新触发恢复。旧实现将诊断 current_source 接回保护；注入“只有观察值异常”时复现 DIAGNOSTIC_OBSERVER_TRIGGERED_RECOVERY。现改为真实 source_faults 独立三级同步进入 UI 保护，诊断只观察。新版整机测试同时验证假观察值不触发复位、真实源故障会触发共同复位并记录首次事件。
2. AR 与首个 R 同拍时，服务监测器原先无条件设置 reading，单拍事务无法退休。旧测试复现 ZERO_LATENCY_SINGLE_R_NOT_RETIRED。现按 rvalid/rlast 识别同拍接收，并初始化 seen_r；单拍、多拍及后续读间隙回归通过。

修复后复审未发现同类 Critical/Important 问题。证据目录 evidence/v5c 保存实际源 SHA 与日志；代码审查不能替代物理时序和实板验收。
