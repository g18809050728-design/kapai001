# Battle UI 交接状态

已落盘：

- `src/ui/battle_screen.gd` / `.tscn`：战斗视图、手牌、任务/单位目标、换班、效果内待选、普通保留（仅 preview 提供候选时）、结束回合、牌堆公开查看、规则说明、日志、动画开关和速度。
- `src/ui/battle/battle_event_animator.gd`：RefCounted 纯展示队列；由 Screen._process 推进；0.12 秒基准；按 run/revision/index 去重；关闭动画立即清空待播队列。
- `artifacts/g7-build/battle-api.md`：UID 及对接约定，与测试代理冒号 UID 一致。

2026-10-15 已运行 `gdformat src/ui/battle_screen.gd src/ui/battle/battle_event_animator.gd`，并运行同两文件 `gdlint`，结果 `Success: no problems found`。这是静态格式/解析检查；**没有运行 Godot**。父代理统一导入、编译与真实 Button.pressed 测试。

实现要点：

- 卡牌本地预选由 preview 判定：仅缺目标的 INVALID_TARGET 可继续选择，资源不足/限次等均禁用。完整草稿再次 preview 后发唯一 action_requested。
- 目标与换班候选来自 required_selections；没有访问 ContentDB、BattleState、引擎或存储。费用只用 hand 的 effective 字段。
- 待选 `action_draft` 屏蔽非 confirm_choice 草稿，所有非 choice:* 控件禁用；choice:confirm 同时受真实 preview 与数量门控，不会在 Shell 门控后错误启用。
- 非法提交后 shell 同 revision 重绘保留选择；接受新 revision 清支付前预选，不清同 choice_id 的已选候选。
- 抽牌堆仅数量，draw_pile_card_ids 恒空。弃牌/消耗只展示 zones_public。
- 日志来自 event_log 快照，与动画独立刷新，不反查已离场实例名称。
- 布局主体可滚动，手牌横向滚动；固定全局状态/错误反馈由 GameShell 外框负责。

留给父代理的真实运行关注点：Godot 编译类型告警、preview 对 set_ally_target 缺 task 参数与 confirm_choice 的实现、真实 UI tests UID 联调。不得把静态检查写成 G7 通过。
