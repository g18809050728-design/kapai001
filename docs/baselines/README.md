# 基线与当前实现快照

[current-state.json](current-state.json)登记 2026-11-04 当前 `campus_four_year` 的 manifest、全部启用 ID、定义/source hash、四图参数、实现证据与待完成事项。它是观察到的实现状态，不是正式 G0 冻结或 G8 通过记录。本轮范围已由用户确认，整版未决项见[G0记录](../G0基线执行记录.md)和[阶段总览](../阶段执行状态总览.md)。

[g0.json](g0.json)保留 2026-10-14 v1 的历史登记原字节，旧 campus_mvp 精确范围、hash、T/RB 与数值只对当时版本有效。当前上游和运行时已经扩展为 v3.1 四角色/四学年，不再写成“现有程序仍对应 v1”。旧 `verify_g0.py`/`verify_g2.py` 的精确集合断言不得用作当前版本的验收命令。

G0–G7 执行记录已按用户要求更新为当前状态；旧记录原文见[清理前快照](../../artifacts/verification/docs-refresh-20261104/documents-before.zip)。如需复核旧阶段，应在隔离目录恢复对应来源与当时运行输入，不覆盖当前设计、数据或玩家档。
