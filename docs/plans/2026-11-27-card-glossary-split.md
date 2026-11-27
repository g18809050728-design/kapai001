# 战斗卡牌说明与名词解释分离（2026-11-27）

需求：UIR-092。目标是把战斗内卡牌说明窗口里的“效果说明”和“名词解释”拆成两个可独立编辑、独立显示的部分，并把名词解释收进窗口底部的可开关下拉框。规则、数值、命令、RNG、存档和内容定义均不改变。

## 行为

- 鼠标停留在手牌上达到原有时长后，右侧说明窗口只显示效果说明；按 `I` 固定的窗口同样只显示效果说明。
- 所有卡牌的基础/升级战斗说明去掉单独一行的“打出后按顺序结算：”，其余行保持原样。
- 有名词解释的卡牌在窗口底部显示“▸ 名词解释”小箭头按钮。点击（悬停窗口和固定窗口都可用）展开为“▾ 名词解释”，在上方显示术语列表；再次点击收起。
- 展开/收起只改变显示，不提交任何游戏命令。切换卡牌或关闭窗口时回到收起状态。
- 没有名词解释文本的卡牌隐藏箭头，窗口保持原有效果说明高度。
- 说明窗口在显示卡牌详情时接收指针输入，以便点击箭头和滚动内容；非卡牌摘要仍不拦截指针。指针可以跨过卡牌与侧窗之间的小间隙进入下拉框。
- 效果说明中出现的名词解释术语、以及下拉框中的术语名，统一使用暖金色 `#f0cf8a` + 下划线标识；解释正文和普通文字保持原色。
- 术语来源是当前显示的名词解释文本（包含用户编辑），按长度优先、不重叠匹配；没有名词解释时不做高亮。
- 高亮只发生在渲染层，不写回覆盖文本；文本编辑器中的字段仍是纯文本。
- 底部提示在可展开时显示“点名词解释展开 · I 固定介绍/取消固定”；无可展开内容时保留原提示。

## 文本与数据

- 新增独立 UID：`card:<id>:<level>:battle_glossary`。默认值由当前效果说明中出现的术语生成，每行一个“术语：说明”，不包含“名词解释：”标题。
- `card:<id>:<level>:battle` 只保存效果说明，默认生成时不再写入“打出后按顺序结算：”；`UiContentText.describe_battle_card()` 不再拼接名词解释，`describe_battle_card_glossary()` 单独读取名词解释。
- 兼容旧数据：加载 `user://text_overrides.json` 和内置默认时，如果旧 `:battle` 文本仍带“名词解释：”段，会在内存中拆成效果部分和新的 `:battle_glossary` 部分；同时只移除单独一行的“打出后按顺序结算：”，其他行保持原样。保存后自然写入新结构。显示层也对旧值保留同样的拆分和去标题兜底。
- 卡牌文本实体从 5 个字段变为 7 个：名称、基础/升级说明、基础/升级战斗说明、基础/升级名词解释。卡牌实体总数仍为 174，其他实体分类不变。
- 文本库实体仍为 600；逻辑字段由 1746 增至 2092，backing UID 由 1766 增至 2112，源库 UID 由 1754 增至 2100。
- 牌组/弃牌堆/消耗堆等列表继续使用效果说明，不在长列表中重复术语解释；术语仍可通过卡牌详情下拉框查看。

## 实现位置

- `src/ui/ui_content_text.gd`：拆分默认值、覆盖值、旧值兼容、术语生成、术语解析和高亮分段。
- `src/ui/text_overrides.gd`：旧 `:battle` 值的加载迁移。
- `src/ui/text_library.gd`、`src/ui/text_entity_library.gd`：新增卡牌名词解释条目和编辑字段。
- `src/ui/battle_layout.gd`、`src/ui/battle_screen.gd`：说明窗口底部箭头、下拉框、布局、指针保持、`RichTextLabel` 高亮渲染和缓存。
- `src/ui/ui_style.gd`：术语高亮颜色。
- `tests/suites/test_ui_battle_keyword_highlight.gd`：术语解析、最长优先、不重叠、纯文本保持和名词解释术语名高亮的纯函数测试。
- `tests/suites/test_ui_battle_pointer.gd`、`test_ui_battle_card_inspection.gd`、`test_ui_battle_polish.gd`、`test_ui_followup.gd`、`test_ui_text_editor.gd`：显示、点击、几何、高亮分段和编辑分离检查。

## 验证

```powershell
$env:GODOT_BIN = 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $env:GODOT_BIN --headless --path . --script res://tools/run_text_editor_tests.gd
& $env:GODOT_BIN --headless --path . --script res://tests/run_ui_battle_keyword_highlight_tests.gd
& $env:GODOT_BIN --headless --path . --script res://tests/run_ui_battle_layout_tests.gd
& $env:GODOT_BIN --path . --script res://tools/run_card_glossary_capture.gd -- res://artifacts/verification/card-glossary-20261127/battle
& $env:GODOT_BIN --path . --script res://tools/run_text_editor_capture.gd -- res://artifacts/verification/card-glossary-20261127/text-editor
```

开发时用临时入口逐个运行战斗指针、卡牌检查、布局、后续页面和周边交互套件；提交的正式回归入口仍是 `tests/run_ui_tests.gd`。

完整 UI 回归仍会出现既有的整套顺序下战斗指针悬停失败（指针套件单独运行通过）以及与本需求无关的饰品替换旧效果提示失败；卡牌说明、文本编辑器、布局和相关战斗交互套件均通过。

## 边界

- 只影响显示文本与窗口布局；不改变卡牌效果、费用、条件、触发、结算顺序、RNG、命令或存档。
- 下拉框只显示当前卡牌实际命中的原有术语集；不新增规则术语，也不改变全局“词条”分类。
- 高亮从当前显示文本派生，只存在于 `RichTextLabel` 分段中，不写入覆盖文件；文本编辑器字段仍是纯文本。
- 固定/悬停窗口仍使用原有卡牌详情位置规则；说明窗口与源卡牌保持不重叠。
- 旧覆盖文件迁移只在内存中发生，下一次保存才写入新 UID；未保存时原始文件不被改写。

## 发布状态

本次未发布公网：开发环境没有 `47.93.245.237` 的 SSH 凭据，`root` 登录返回 `Permission denied (publickey)`。本地实现、实渲和定向回归已完成；取得服务器访问后按根计划 §0.20.82 导出、切换版本目录并核对公网入口。
