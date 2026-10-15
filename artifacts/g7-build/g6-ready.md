# G6 资源交接完成

2026-10-15，g6_spec 已完成，可继续 G7。

- 46 个选定文件位于 `assets/art/g6-v1/`，真实加载路径读 `assets/g6/selection.json` 的 `selections[].selected_file`。
- 六图集、46 素材、66 内容映射、16 VIS/ACT 处理方式齐全，来源与候选/选定 SHA256 已登记。
- 六张 contact sheet 已由 AI 实际查看，另复查 F03/F04/K05/K06/A05 及修正后 K05/K06。`artifacts/g6-review/review.json` 是观察证据。
- K05/K06 已以内裁 `[8,8,654,654]` 去掉顶边残线，输出 646×646；其他 44 张为候选字节一致副本。源图与候选保留。
- 全部 RGB 实底。F03/F04 手部/道具、A05 盒边局部截断；P01/A01/A07/A11 贴边，适合相框式展示。部分包装/稿纸含拟字，规则文本必须由 UI 绘制。
- `assets/g6/README.md` 已完整重写，数字变 6 异常已清除。`docs/G6资源准备执行记录.md` 已更新为当前 AI 核对及原型资源选定状态。
- `python artifacts/g6-review/check_selection.py` 退出 0；518 项文件来源、尺寸、映射和文档链接检查通过，结果在 `artifacts/g6-review/selection-check.json`。没有运行 Godot 或游戏全回归。
- 外部平台、模型、实际计费调用次数未知；代理生图调用 0；人工签字未记录。

父代理仍需同步根计划、根 README、UI 台账、`docs/G6资源制作规范.md` 顶部的旧“未生成”口径；本代理未改这些文件或游戏代码。
