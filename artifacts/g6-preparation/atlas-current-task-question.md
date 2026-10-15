# g6_atlas_tool 当前回合状态

父代理的新任务与多条消息正文均为空（工具/传递问题）。本代理已完成离线切图工具，详见 atlas-tool-status.md。新回合目前只读核对了战斗相关契约/视图，没有新增 UI 文件，也没有改领域代码。

若本轮是 G7 战斗 UI，请将明确任务、UiPage/UiTheme/UiAssets API 写到本文件旁的 delegated-tasks.md 或其他共享 .md，再发空消息触发即可；当前根计划仍写 G6 准备中、G7 未开始，selection 仍 awaiting_generation，不能仅凭空任务擅自实施 G7。

附本轮只读发现：

- GameSession._battle_view 返回 battle_id/node_id/encounter_id/phase/round_index/ddl/player/hand/units/tasks/statuses/scene/zone_counts/zones_public，pending_choice 在外层 SessionView。卡面在 hand[].effective_card，但没有文档约定的 effective_cost/effective_vitality_cost/playable。UI 可以查询 preview 取 costs，或由视图补齐。
- BattleEngine.preview 目前仅支持 play_card，end_turn/confirm_choice/set_ally_target 会返回 battle.action.preview_not_ready。若 G7 对所有操作都 preview 门控，必须补全这些 preview，不能在 UI 本地猜合法性。
- assets/g6/README.md 当前出现数字批量替换异常，如日期 6066-60-66、尺寸 6860×6660、G6-06 重复、SHA666。本代理未改此文件，请父代理核对是否为中间工作态。
