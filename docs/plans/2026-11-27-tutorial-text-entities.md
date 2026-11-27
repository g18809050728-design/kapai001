# 新手教程文本实体（UIR-094）

2026-11-27

## 来源与范围

用户要求：新手教程文本在文本编辑器中作为文本实体可编辑，并新增一个教程分类。

本批只把教程的**显示文字**接入现有 `TextOverrides` 三层文本（用户覆盖 → 内置默认 → 源文案）。教程触发、页数、分页顺序、高亮锚点、遮罩、输入隔离、规则、数值、命令、RNG、存档 schema 与档案教程标记都不改变。

## 编辑器结构

文本编辑器页签顺序变为：

`全部 / 卡牌 / 饰品 / 人物 / 剧情 / 词条 / 怪物 / 教程 / 其他`

「教程」页签包含 6 个分页实体，按阅读顺序排列：

| 实体 | 页 | 字段数 |
|---|---|---:|
| `tutorial:intro_1` | 开局 1/6 · 三个数值 | 9 |
| `tutorial:intro_2` | 开局 2/6 · 地图 | 9 |
| `tutorial:intro_3` | 开局 3/6 · 战斗准备 | 12 |
| `tutorial:battle_1` | 战斗 4/6 · 先读敌人 | 11 |
| `tutorial:battle_2` | 战斗 5/6 · 专注 | 9 |
| `tutorial:battle_3` | 战斗 6/6 · 出牌与结束回合 | 10 |

每个实体可编辑：

- 章节（页眉中的「开局 / 路线 / 战斗」）；
- 标题；
- 正文（单句说明，多行输入）；
- 每个词条的名词与说明；
- 最后一页的主按钮文字（「开始冒险」「开始战斗」）。

字段 UID 使用稳定形式：

```text
tutorial:<page_id>.chapter
tutorial:<page_id>.title
tutorial:<page_id>.body
tutorial:<page_id>.bullet_<n>.term
tutorial:<page_id>.bullet_<n>.text
tutorial:<page_id>.next
```

例如 `tutorial:intro_1.bullet_0.term`。UID 与分页顺序固定，不随显示文字变化。

## 生效方式

- `UiTutorialContent` 保留原始 `PAGES` 文案；`intro_steps()` / `battle_steps()` 每次读取时通过 `TextOverrides.text(uid, source)` 解析。
- 文本编辑器保存后再次打开教程或开始新一局，直接显示新文字；不需要重启游戏。
- 「恢复」清除教程字段的用户覆盖，回到当前默认层（内置默认或源文案）。
- 教程文案不再借用 `UiGlossary.label()`；教程词条拥有自己的 UID，编辑教程不会改动全局词条名称。若用户希望全局术语与教程同步，应另行设计别名，不在本批自动联动。
- 教程按钮、页码与「新手教程」页眉前缀仍是固定界面文案；可编辑范围限于上述实体字段。

## 计数

- 实体：600（原 594 + 教程 6）
- 逻辑字段：1746（+60）
- 后端 UID：1766（+60）
- 源文本库 UID：1754（+60）

`data/text_defaults.json` 原有 237 条；2026-11-27 已把用户编辑的 24 条教程字段并入（UIR-095），共 261 条。未编辑的教程字段仍回退到 `src/ui/tutorial_content.gd` 源文案；用户覆盖单独保存到现有 `user://text_overrides.json`。

## 实现位置

- `src/ui/tutorial_content.gd`：原始 6 页文案、稳定 UID、运行时覆盖解析。
- `src/ui/text_library.gd`：扁平文本库新增 `tutorial:*` 条目与「教程」分类。
- `src/ui/text_entity_library.gd`：新增 `tutorial` 类型、6 个实体与分页排序。
- `src/ui/text_editor_page.gd`：新增「教程」页签、类型顺序与教程分页排序。

## 验证

- 文本编辑器专项：`TEXT_EDITOR_TESTS=passed`，9063 项检查；6 个教程实体、60 个教程字段，教程页签顺序为 1→6，搜索「精力」命中，编辑标题/词条后 `UiTutorialContent` 立即读到新文字，恢复后回到当前默认。
- 教程专项：`UI_TUTORIAL=passed`；教程触发、锚点、跳过、重看与输入隔离仍通过；文案长度不再固定上限，长文本使用滚动。
- 实渲：`artifacts/verification/tutorial-20261127/text-editor/editor-tutorial-entity.png` 显示新页签与教程实体；原教程双尺寸实渲继续使用 `artifacts/verification/tutorial-20261126/`。
- 只改显示层；没有修改规则、命令、RNG、存档或正式档案。

## 边界

- 教程实体没有增加/删除分页的编辑能力；页数由教程流程固定。
- 固定按钮「跳过教程」「上一步」「下一步」与页眉「新手教程」不在本批可编辑范围。
- 其他分类的既有行为与计数断言已同步更新；旧用户覆盖文件无需迁移。
