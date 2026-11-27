# 新手教程编辑文本作为内置默认

2026-11-27

需求：UIR-095

相关：UIR-081 文本默认层、UIR-094 教程文本实体

## 来源

用户已在文本编辑器的「教程」分类编辑了 24 个字段，修改保存在本机 `user://text_overrides.json`。本批把这些修改并入项目内置默认层 `data/text_defaults.json`，使编辑器的「默认」、字段恢复、全部重置和新开一局都直接使用这些文本。

源文件备份：

- `artifacts/verification/tutorial-defaults-20261127/text_defaults.before.json`
- `artifacts/verification/tutorial-defaults-20261127/text_overrides.before.json`
- 合并后快照：`text_defaults.after.json`、`text_overrides.after.json`
- 机器报告：`report.json`

## 处理

- 从本机覆盖文件提取全部 `tutorial:*` 条目，共 24 条。
- 追加到 `data/text_defaults.json` 的 `entries`；内置默认从 237 条增至 261 条。
- 从本机 `user://text_overrides.json` 移除这 24 条，保留其余 8 条非教程卡牌说明覆盖（用户仍可继续单独覆盖）。
- 空的 `tutorial:intro_1.body` 按用户编辑保留为空；教程面板在正文为空时隐藏正文行，不额外补文案。
- 源 `src/ui/tutorial_content.gd` 的原始短文案不删除，继续作为第三层回退。

## 分层结果

1. 用户当前覆盖（本机剩余的 8 条卡牌说明）；
2. `data/text_defaults.json`（261 条，含 24 条教程）；
3. `src/ui/tutorial_content.gd` 的源短文案。

因此：

- 文本编辑器教程字段显示新默认；字段「恢复」和新局教程显示新文本。
- 「全部重置」清除用户覆盖后仍回到新默认，不会回到旧短文案。
- 旧覆盖文件格式不变；只清理教程 UID，其他用户编辑不动。
- 运行中的游戏进程已缓存旧文本，需要重新打开游戏或重新进入教程后才会读到新默认。

## 验证

- `TEXT_EDITOR_TESTS=passed`，9063 项；教程标题默认显示「基础数值」、首战标题「敌人」，空正文默认保留为空，字段恢复回到新默认。
- `UI_TUTORIAL=passed`；新默认文本、教程触发、锚点、跳过、重看和输入隔离均通过。
- 实渲：`artifacts/verification/tutorial-20261126/visual/` 与 `visual-150/` 已用新默认重新生成；首战长文本在 150% 字号使用滚动提示。
- 未修改规则、数值、命令、RNG、存档 schema 或档案教程标记。

## 边界

- 本批只并入用户已编辑的 24 条教程字段；未编辑的教程字段继续使用原默认。
- 固定按钮「跳过教程」「上一步」「下一步」、页码和页眉前缀不在可编辑范围。
- 公网发布未在本机执行：没有生产服务器 SSH 公钥。
