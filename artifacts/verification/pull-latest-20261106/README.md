# 重新拉取与冲突整合验证

日期：2026-11-06。用户要求撤销上次冲突处理，重新 pull 并解决本次冲突；此前“别提交”的要求继续有效。

保留原工作区后执行 `git merge --abort`，再运行 `git pull --no-commit --no-rebase origin main`。本地 HEAD 为 `a2aaa69727b660ced6c9d36ca6715e42f285bd92`，本次拉取目标为 `e5315e92ae39b8600058cf524a841bfba227c2bd`（添加卡牌描述）。pull 的退出码 1 代表进入冲突，原始输出见 [stdout](pull.stdout.log)、[stderr](pull.stderr.log) 和 [退出码](pull.exit)。本轮仅解决并暂存，不创建提交或推送；完成后的仓库仍保留 MERGE_HEAD，等待用户后续决定。

## 冲突处理

| 文件 | 整合结果 |
|---|---|
| `docs/局流程契约.md` | 保留远端当前位置分岔规则，V04 全部合格工作牌升级移至 §0.2 |
| `docs/界面层契约.md` | 保留战斗动画、设置和最新卡牌说明；V04/实际完成量反馈移至 §0.7，终局遵守最新等待流程 |
| `实施计划与验收基线.md` | 远端 §0.14～0.15.1 保留，本地 V04/飘字为 §0.16；不扩大阶段验收结论 |
| `动作或者图片描述/需求台账.md` | 解决 FY-UX-024 重号：V04 改记 FY-UX-027；保留远端 FY-UX-024～026 与本地 FY-ACT-004 |
| `src/ui/battle_screen.gd` | 合并目标坐标与终局演出入口；非终局避免重复完成量文字，同时保留血条 Tween 和屏障反馈；保留最新停留/固定说明交互 |
| `src/ui/game_shell.gd` | 保留非终局任务旁 `-N`，终局沿远端完整战斗页等待事件及 Tween；移除旧截图覆盖方案 |
| `tests/run_ui_tests.gd` | 两边 suite 均保留，包括最新卡牌说明、伤害提示、战斗/地图反馈 |

同时同步 `docs/G0需求追踪.md`；`test_ui_damage_popup.gd` 增加真实 shell 出牌检查：伤害文字只显示一次，血条仍从命中前值开始并出现中间值。历史 V04 原始证据中的旧编号不改写。

## 实际验证

引擎：`4.7.2.stable.official.ed1daf0bf`，Windows，headless。通过 [run_verification.py](run_verification.py) 执行以下入口，各进程使用本目录下独立的 APPDATA/LOCALAPPDATA，不使用真实玩家目录：

```text
D:/chrome/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path <仓库绝对路径> --editor --import --log-file <证据绝对路径>/import.godot.log
D:/chrome/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path <仓库绝对路径> --script res://tests/run_tests.gd --log-file <证据绝对路径>/rules.godot.log
D:/chrome/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path <仓库绝对路径> --script res://tests/run_ui_tests.gd --log-file <证据绝对路径>/ui.godot.log
```

准确绝对路径、起止时间、环境、退出码及每次运行的 158 个代码/测试/数据/工程输入 SHA256 见对应 `*.result.json`。

| 验证 | 实测结果 | 原始输出与环境 |
|---|---|---|
| Godot 导入 | 退出 0 | [stdout](import.stdout.log)、[stderr](import.stderr.log)、[运行记录](import.result.json) |
| 完整规则/数据/四年流程 | 退出 0 | [stdout](rules.stdout.log)、[stderr](rules.stderr.log)、[运行记录](rules.result.json) |
| 完整 UI | 退出 0，`G7 UI tests passed` | [stdout](ui.stdout.log)、[stderr](ui.stderr.log)、[运行记录](ui.result.json) |

本机引擎输出 `Failed to read the root certificate store`；导入另提示忽略备份内的嵌套工程。原始日志完整保留，最终检查独立确认无 GDScript 解析/加载错误，不能写成引擎错误总数为零。

## 工作区与边界

原合并结果、索引、元数据及 342 个相关文件的字节备份在本地 `before-abort/`；其中原有 285 个未暂存文件与备份逐一 SHA256 对照。备份、原始二进制 patch、隔离存档和导入缓存不加入暂存区。只暂存明确列举的冲突处理文件与本次验证记录，不使用 `git add .`。

最终索引检查、冲突标记扫描、HEAD/MERGE_HEAD、原有未暂存文件保护与测试输入一致性见 [final-checks.json](final-checks.json)，检查逻辑见 [finalize_merge.py](finalize_merge.py)。

本次没有重新截图或人工实渲验收；UI runner 的多尺寸输入/状态检查不能替代视觉签收。整版 G0 规则/清单未决项、G6 资源许可/人工签收、G8 自然四年路径/性能/打包继续依根计划保留；旧截图和旧测试结果不充作本次通过证据。
