from pathlib import Path

root = Path(__file__).resolve().parents[2]
plan = root / '实施计划与验收基线.md'
text = plan.read_text(encoding='utf-8')
text = text.replace('版本：v1.7｜日期：2026-10-15｜状态：G0–G5 已通过；G6 资源准备中', '版本：v1.8｜日期：2026-10-15｜状态：G0–G5 已通过；G6 资源已交接；G7 本地界面实施中')
paragraphs = text.split('\n\n')
for index, paragraph in enumerate(paragraphs):
    if paragraph.startswith('当前阶段状态（'):
        paragraphs[index] = '当前阶段状态（2026-10-15）：**G0–G5 已通过；用户提供的 6 张 4K 图集及 46 张切片已核对并登记选定版本，G7 本地界面实施中，G8 未开始**。生产清单启用全部 66 个冻结 ID，holdback=0；G4 四条隔离路线与 G5 自动保存开/关续玩、六种终局提交故障恢复证据保持原记录。G5 正式证据为 `artifacts/verification/g5-20261015-163959-566-9abc4b/`。G6 实际资源见 `assets/g6/selection.json`、`assets/art/g6-v1/` 和 [G6记录](docs/G6资源准备执行记录.md)；外部平台、付费调用次数未知，不能将代理生图 0 次解释为用户未生图。用户已要求在图片生成切分后进入下一步，本轮据此接入本地 G7；当前核图为 AI 视觉核对，不冒称用户人工签收，最终人工视觉与来源许可记录在 G8 发布前补齐。G7 设计见[界面与交互设计](动作或者图片描述/G7界面与交互设计.md)，实现及实际验证见[G7记录](docs/G7界面执行记录.md)。F03 层数和部分生产饰品触发仍为已登记缺口，原有流程/存储验收不代表生产玩法、平衡或性能已通过。阶段历史见[G1](docs/G1工程骨架执行记录.md)、[G2](docs/G2内容与基础状态执行记录.md)、[G3](docs/G3战斗规则执行记录.md)、[G4](docs/G4局流程执行记录.md)、[G5](docs/G5存档恢复执行记录.md)；来源与范围见[G0登记](docs/baselines/g0.json)及[需求追踪](docs/G0需求追踪.md)。'
text = '\n\n'.join(paragraphs)
text = text.replace('G6 图片生成与资源核对（当前准备中）', 'G6 图片生成与资源核对（资源已交接）').replace('G7 UI 与剩余交付补全（后续）', 'G7 UI 与剩余交付补全（当前实施）')
text = text.replace('当前 G6 准备并生成、核对 AI 图片；随后 G7 补全视觉/动作设计、实现 UI 和剩余交付项，最后进行完整用户路径验收。', 'G6 已完成本地资源交接，当前 G7 补全视觉/动作设计并实现 UI，最后 G8 进行完整用户路径与发布验收。')
text += '\n\n### 2026-10-15 G6 → G7 本地接入记录\n\n用户确认图片生成与切分完成并要求下一步。本轮允许基于已逐批 AI 核图的选定版实现本地 G7，保留 G6 原要求中的最终人工视觉签收和来源许可记录，随 G8 发布前补齐；此授权不代表人工签收已存在，也不豁免 G7 真实按钮、待选、动画不变性及 G8 生产玩法/性能/打包检查。UI 只依赖选定素材和 GameSession 公开视图，不能以界面绕开规则缺口。\n'
plan.write_text(text, encoding='utf-8')

contract = root / 'docs/界面层契约.md'
text = contract.read_text(encoding='utf-8')
text = text.replace('本文件定义目标行为；当前没有 UI 工程或测试，示例路径与测试名不代表已实现。', '本文件定义界面契约；G7 已开始实现，实际验证状态见 [G7执行记录](G7界面执行记录.md)。')
text += '\n\n## 16. G7 当前实现适配（2026-10-15）\n\n详细视觉/动作设计见 [G7设计](../动作或者图片描述/G7界面与交互设计.md)。MVP 采用 `page_flow.gd` 按 screen 统一实现局流程页面，入口仍为 `src/app/main.tscn`；战斗入口整合到 `BattleScreen`，进入节点即展示已创建的真实战斗。`term/ending` 属完整版本，不以不可达页面凑数。页面测试入口为 `tests/run_ui_tests.gd`。\n\n- `GameShell` 对每个规则草稿统一 preview 门控。会话的非出牌战斗预览复用 BattleEngine.apply 的状态/RNG副本，只返回合法性，不发布模拟结果或未来抽牌；正式状态/revision/RNG 不变。\n- 手牌及公开牌堆保留 `effective_card` 并提供 `face`、`effective_cost`、`effective_vitality_cost`，费用由引擎 calculate_cost 报价。卡片预选允许补目标，最终提交仍以 preview 为准。\n- `UiPage.build_action()` 无参返回最近草稿；BattleScreen 用内部动作工厂，避免覆盖成不同签名。local_selection_changed 触发 shell 重新门控。\n- `option_id=leave` 的事件选项使用 `event:option:leave`，与离开节点 `event:leave` 区分；`settings:apply` 保存设置，`settings:save` 手动保存当前学期。\n- 战斗 UID 为 `card:<id>`、`task:<id>`、`unit:<id>`、`choice:<id>`、`choice:confirm`、`battle:end_turn/cancel/animation/speed/draw/discard/exhaust/rules/save/menu`。日志整体刷新，动画只消费发布事件，不驱动规则。\n- 战斗展示合并为 `battle_screen.gd` 与 `battle/battle_event_animator.gd`，组件清单中其余文件是可拆分目标，当前不创建空壳。\n'
contract.write_text(text, encoding='utf-8')
