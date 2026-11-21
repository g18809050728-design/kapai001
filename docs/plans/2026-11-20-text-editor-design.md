# 主菜单文本编辑器设计与实现记录

> 后续结构升级：2026-11-21 §0.20.35 已将检索改为“实体优先”，见[实体优先设计](2026-11-21-text-editor-entity-design.md)。本文件保留旧版扁平字段实现的记录。

日期：2026-11-20  
需求：UIR-076（[需求文件](../../动作或者图片描述/主菜单文本编辑器_20261120.md)）  
根计划：§0.20.34

## 1. 背景与范围

用户要求在主菜单加入可自由检索、浏览并编辑游戏内文本的编辑器。本批按 G7 界面实施例外处理：只新增主菜单入口、文本目录、编辑界面和本机覆盖文件，不推进阶段，不修改规则、命令、RNG、存档 schema、正式存档或进行中的对局。

可编辑范围是**由正式内容数据驱动的显示文本**：

| 来源 | 内容 | 条目数 |
|---|---|---:|
| `src/ui/ui_labels.json` + `UiStyle` 内置词 | 人物、卡牌、任务/怪物、饰品、事件、状态、场景、背景等名称与术语 | 600 |
| `src/ui/room_stories.json` | 事件/房间标题、地点、叙述、事件选项标题 | 34 |
| `UiGlossary.ENTRIES` | 词条名称、分类、短说明、详细说明 | 176 |
| 正式卡牌/饰品/人物定义 | 174 张卡的基准/升级说明与战斗逐步说明、16 件饰品、4 位人物被动 | 712 |
| 合计 | | **1522** |

卡牌说明使用正式 `catalog` 的解析面生成默认文本；卡牌名、费用、类型、效果与全部战斗数字仍来自原规则。编辑器不把名称修改写回内容定义，只在本机覆盖层替换显示字符串。

不在本批：GDScript 中固定写死的按钮/提示文字，以及由规则实时拼装、带动态数值的短句（例如战斗摘要中的当前数值）。这些文本没有稳定的内容 ID，若强行替换会侵入界面代码和规则呈现，故本批不纳入。

## 2. 架构

### 2.1 覆盖层 `src/ui/text_overrides.gd`

- 默认路径：`user://text_overrides.json`。
- 结构：`{"schema_version":1,"updated_at":"...","entries":{"<uid>":"<text>"}}`。
- 只接受字符串键/值，单条最长 20000 字，最多 4000 条。
- 读取使用 `JSON.new().parse()`，损坏/版本不符时清空覆盖并记录错误，界面回退原始文本。
- 写入先写 `.tmp`，保留 `.bak` 后原子替换；失败返回可读错误，不改变内存状态。
- 测试通过 `TextOverrides.use_path()` 使用隔离文件，不触碰真实玩家覆盖文件。

覆盖 UID：

- `label:<label key>`
- `story:<events|rooms>.<id>.<title|location|narrative>`
- `story:events.<id>.option_titles.<option>`
- `glossary:<key>.<name|type|short|body>`
- `card:<id>:<0|1>:<detail|battle>`
- `relic:<id>`
- `passive:<passive id>`

### 2.2 应用点

| 文件 | 行为 |
|---|---|
| `src/ui/ui_style.gd` | `UiStyle.label()` 在原始标签解析后套用 `label:` 覆盖，保留点号键的规范回退 |
| `src/ui/campus_room_illustration.gd` | `details()` 为剧情字段和选项标题套用 `story:` 覆盖 |
| `src/ui/ui_glossary.gd` | 名称/分类/短说明/详细说明套用 `glossary:` 覆盖 |
| `src/ui/ui_content_text.gd` | 卡牌详情、战斗详情、饰品说明、人物被动说明分别套用覆盖；另提供 `*_default()` 供目录显示原文 |

应用是显示层的替换：`GameSession`、`RunService`、`BattleEngine`、随机数、存档与命令门控均未改动。

### 2.3 目录 `src/ui/text_library.gd`

- `TextLibrary.build(catalog)` 只读正式 `campus_four_year` 内容库。
- 名称来自标签表；剧情来自 `room_stories.json`；词条来自 `UiGlossary.ENTRIES`；说明默认值来自 `CompendiumView.build` 的真实解析面和 `UiContentText.*_default()`。
- 每条包含 `uid / group / category / id / title / default / source / note`，按分类、标题、UID 稳定排序。
- 目录显示原始默认文本；当前编辑值来自 `TextOverrides`，因此“恢复默认”不依赖运行时状态。

### 2.4 界面 `src/ui/text_editor_page.gd`

- 入口：主菜单 `menu:text_editor` → `GameShell` 的 `text_editor` 页面。
- 布局：顶部标题/统计/搜索/分类页签；左侧连续条目列表；右侧编辑面板；底部固定返回/保存/全部重置。
- 分类页签：全部、名称、说明、剧情、词条；名称再有 11 个分类过滤，说明有卡牌/饰品/人物，剧情有事件/房间。
- 搜索：正文、ID、标题、来源、分类统一小写匹配，空格分词 AND；120ms 去抖。
- 浏览：首批 12 条，接近底部追加 12 条；切换页签/搜索只重建结果，不重建旧条目组件。
- 编辑：多行 `TextEdit`；修改即时进入草稿；保存写覆盖文件；恢复本条默认/撤销未保存/全部重置；未保存返回二次确认；Ctrl+S 保存；Esc 返回。
- 响应式：1280×800、960×600，100/125/150% 字号；150% 时编辑框先于次级按钮显示，右侧面板可滚动，主按钮保持 ≥44 像素。

## 3. 安全与一致性

- 覆盖文件只被显示层读取；正式内容定义从未被改写。
- 编辑期间不调用会推进对局的命令；测试比较编辑前后 `SessionView` 的规范 JSON，确认 revision、run、battle、RNG、待选和事件日志不变。
- 空字符串允许保存（显示为空白），单条恢复/全部重置可清除。
- 覆盖文件损坏时仍能进入游戏，使用原始文本并显示提示。

## 4. 验证

- 专项套件：`tests/suites/test_ui_text_editor.gd`，覆盖目录集合、分类计数、搜索、编辑、应用、持久化、损坏回退、未保存保护、状态恢复、1280/960 与 100/125/150% 布局、无对局与活动对局两种会话不变。最终 8811 项，0 失败；退出 0。
- 实际截图：`artifacts/verification/text-editor-20261120/visual/`，主菜单、全部/名称/说明/剧情/词条、搜索、空结果、卡片详情、默认文本、未保存、已保存、960×600/150%，共 15 张。
- 完整 UI：退出 0，`G7 UI tests passed`（该次运行含 8803 项文本专项；补充检查后的独立专项为 8811 项）。
- 完整规则：退出 0，`G4/G5 headless tests passed`；默认入口退出 0，`Project bootstrap ready`。
- 隔离：专项与截图使用独立 SaveStore/覆盖文件，结束时恢复原覆盖路径；没有读写真实玩家存档或 `user://text_overrides.json`。
- 原始输出与摘要：`artifacts/verification/text-editor-20261120/`（`README.md`、`verification-summary.json`、stdout 日志）。

## 5. 已知边界与后续

- 固定界面按钮/提示文案与动态数值短句不在可编辑集合；若后续要求覆盖全部 GDScript 文案，需要单独做字符串本地化/文案层改造，不能以本机覆盖文件直接改动规则输出。
- 用户最终视觉签收、原整版 G0/G6/G8 出口、自然四年通关等仍按原计划分别保留。
