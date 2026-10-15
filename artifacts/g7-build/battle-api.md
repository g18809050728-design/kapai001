# BattleScreen G7 对接协议

战斗页沿用测试代理提出的冒号 UID：

- 手牌 `card:<card_id>`；任务 `task:<task_id>`；单位 `unit:<unit_id>`。
- 预览候选补选 `replace:<unit_id>`（换班）、`target:<id>`（非任务/单位候选）。
- 待选 `choice:<candidate_id>` / `choice:confirm`。
- `battle:end_turn` / `battle:cancel` / `battle:animation` / `battle:speed`。
- `battle:draw` / `battle:discard` / `battle:exhaust` / `battle:rules` / `battle:close_panel`。
- `battle:menu` / `battle:save`。

`preview_callback` 接收 `{type,payload}` 返回 ActionPreview/null。手牌/单位/目标按钮属于本地预选，Screen 使用 preview 决定可选性并在草稿补齐后只发一次 action_requested；这些本地按钮不依赖 Shell 将不完整草稿视为可提交。结束回合与待选确认登记为常规 action_draft，由 Shell 统一预览门控。

额外只读观察 API：`selection_snapshot()`（card_id/unit_id/target_ids/replace_unit_id/choice_selected_ids/retained_card_ids）、`display_snapshot()`（公开牌堆、日志、反馈、事件消费快照）。取消仅清本地选择，不发规则命令。

`is_locked()` 取 view.pending_choice；`lock_snapshot()` 返回 pending、hand/tasks/units/end_turn/decks/rules/animation/cancel/save/menu 的禁用状态。待选只允许候选与确认。

`draw_pile_card_ids()` 恒返回空数组。`consume_events(events,run_id,revision)` 不修改 view/log，不访问规则。

父代理需提供 hand.effective_cost / effective_vitality_cost / face / playable（可选）及 pending_choice/event_log/run_id/revision/can_save。普通保留只在 end_turn preview 给出 `retained_card_ids` required_selections 时展示；K19 retain 只走 pending_choice。

Godot 导入与运行由父代理统一执行，本代理不启动引擎。
