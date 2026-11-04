# 四学年新局入口与被动核查

日期：2026-11-04。来源：用户要求创建游戏仅使用四学年版本，并核对四角色被动。实施范围见根计划 §0.9，需求 FY-VIS-006。

## 设计

GameSession.get_setup_options 只加载 campus_four_year，返回四名角色及各自 passive_id。历史包允许加载的内部逻辑继续用于历史档和兼容测试。UiFlowPage 使用提供的唯一 manifest，删除版本按钮与角色选择时的 v3 切换；通用测试页面仍使用测试会话提供的唯一 manifest。

选角卡在名字后显示被动说明，由 UiContentText 按 passive_id 映射。文案与战斗状态分离：林序“步骤复用”说明当前自动取回和未提供放弃选择；许知微“论文记录”说明新名进度、旧名引用及引用付款；沈见章“复合反应”说明不同负面组合与每回合一次；唐以宁“分工默契”说明首张合作结算后的协同和放松。未知被动不捏造效果。

本轮核对现有机制，不改动被动规则。P01 缺少主动放弃取回仍消耗机会的交互，按卡牌契约 §8 继续记为部分完成。

## 验收

1. 生产 setup 仅有 campus_four_year，四角色可选，页面无 setup:manifest:* 按钮。
2. 四人说明均可见，切换人物、随机种子、返回重开仍使用四学年；从历史局重开同样进入四学年。
3. 用四学年生产内容实际执行四人被动，检查取回、进度/引用、复合反应和首张合作的效果及限次；既有角色套件继续验证边界。
4. 隔离 APPDATA/LOCALAPPDATA 运行规则/UI 回归，保留命令、引擎、输入 hash、退出码和原始输出；1280×800 与 960×600 实际渲染选角页，检查被动可读与底部操作可达。

## 实测证据

使用 Godot `4.7.2.stable.official.ed1daf0bf`，APPDATA/LOCALAPPDATA 均隔离，不读写实际玩家档。

| 被动 | 实际生效与验证 | 当前结论 |
|---|---|---|
| 林序：步骤复用 | 四年包中策略后打工作，前策略实际回手；0 费策略原实例限次未刷新；同回合第二次连携不再取回 | 核心已生效，主动放弃取回的选择仍缺，按契约 §8 为部分落实 |
| 许知微：论文记录 | 开题自身不记账，新名进度 +1；同回合重复名被拒，跨回合重复名引用 +1；其他新名继续增进度。既有 P02 套件覆盖引用逐层专注付款、章节和发表 | 核心已生效，本次未穷尽所有换题/章节组合 |
| 沈见章：复合反应 | 一张牌先施诱发再施易伤，正文后易伤额外 +1；第二张牌的新负面不再获得强化。既有 P03 套件继续覆盖自动效果与相关机制 | 核心已生效，本次未穷尽生产状态组合 |
| 唐以宁：分工默契 | 普通与独立作答考试分别验证：首张合作结算后协同 +1、被动放松 +2，第二张合作没有第二次被动收益 | 核心已生效，伙伴满槽专用交互仍按卡牌契约另列 |

实现位置：`src/battle/battle_engine.gd` 的 `_v3_try_passive_retrieve`、`_v3_paper_record`、`_v3_apply_compound_reaction`、`_run_character_passive`。v3 被动由这些专门规则运行，角色 JSON 中旧通用 `passive.effects` 不可用于推导当前实际效果。创建页通过 passive_id 使用独立只读文案。

- `python tools/verify_four_year.py setup-passive-focused res://tests/run_four_year_tests.gd`：[摘要](../../artifacts/verification/four-year-20261104/setup-passive-focused/summary.json)与[原始输出](../../artifacts/verification/four-year-20261104/setup-passive-focused/run_four_year_tests.stdout.txt)，退出 0、引擎错误 0，`FOUR_YEAR_PASSIVES=passed`（仅上述已覆盖行为）。
- `python tools/verify_four_year.py setup-passive-regression-final res://tests/run_tests.gd res://tests/run_ui_tests.gd`：[摘要](../../artifacts/verification/four-year-20261104/setup-passive-regression-final/summary.json)，规则/UI 两进程退出 0、引擎错误均 0。四人物分别经菜单选角、新种子和开始按钮进入四学年；P02 从历史 v3 局重开需确认且最终进入四学年。
- `python tools/verify_four_year.py setup-visual --visual res://tools/capture_four_year_setup.gd`：[摘要](../../artifacts/verification/four-year-20261104/setup-visual/summary.json)，退出 0、引擎错误 0。两尺寸各保存顶部、中部、底部，共 6 张截图；AI 检查被动说明换行可读、无版本选项、滚动底部可见开始/返回按钮。示例：[1280 顶部](../../artifacts/verification/four-year-20261104/setup-render/setup-1280-top.png)、[960 底部](../../artifacts/verification/four-year-20261104/setup-render/setup-960-bottom.png)。现有 P02/P03 肖像缺失仍属 G6，不由本轮生成资源。

初次回归的失败原始输出保存在 `setup-passive-regression/`：新增测试误把永久卡 ID 当作战斗实例 ID，现改用 origin_card_id 找实例；旧 K 牌 UI 测试依赖被删除的版本按钮，现以内部 API 建立相同历史测试输入，其余交互断言保留。最终结果以上述 final 目录为准。

本次不代表整版 G0、G6 或 G8 通过；P01 选择交互及全部生产组合、真人平衡和完整四年路径仍需后续验收。
