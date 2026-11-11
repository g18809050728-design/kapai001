# 《交大四年：DDL战争》设计与实施入口

2026-11-06 追加：设置页明确已选、当前生效与尚未应用；最后一击等待卡牌/扣血动作完成后再切页，速度参数保持。完整 UI 回归与双尺寸 40 张实渲通过，见[本轮记录](docs/设置状态与战斗转场实施记录_20261106.md)。

2026-11-06：战斗改为实际手牌逐张抽出、落位显示，弃牌从原卡位直接进入目标堆；按用户实测把特效基础速度统一提高 4 倍，页面倍速继续叠加。完整规则/四年/UI、导入和两尺寸 30 张实渲通过，见[B2 记录](docs/战斗动画时序实施记录_20261106.md)。

更新：2026-11-04。创建游戏仅使用 `campus_four_year`，已接入四角色 v3.1 卡牌、**四张连续学年地图**、校园服务、饰品与学年大奖励。以学年为单位，不分学期；选角显示被动效果，具体核查与缺口见[入口记录](docs/plans/2026-11-04-four-year-setup-design.md)。正式平衡、美术音乐与 G8 发布验收仍待完成；旧 `campus_v3` / `campus_mvp` 仅保留内部历史兼容。

2026-11-01：按用户要求把两份精英设计草稿（[草稿一](docs/精英敌人设计草稿.md)、[草稿二](docs/精英敌人设计草稿2.md)）的 12 个精英遭遇（E01–E07、Q0A–Q0E）落进 v1 数据与战斗引擎，新增每单位压力缩放、任务召唤/转换/自爆、意图停留、可选任务与绞尽脑汁/迷惑敌方增益；[小怪设计草稿](docs/小怪设计草稿.md)的新增普通敌人未实现。范围、语义解读、偏差与未完成项见[精英敌人实现记录](docs/精英敌人实现记录_20261101.md)。Godot `4.7.2.stable` 无头套件、UI 套件与启动冒烟均已在本机实跑通过（证据 `artifacts/verification/elite-godot-20261101-162637-290819/`）；平衡与人工视觉仍未验证。

2026-11-02：第一学期精英池定为 `Q01`、`E01`、`E02`、`E03`、`Q0B`、`Q0C`（`Q0B`/`Q0C` 提前到第 1 学期）。用机器人对起始牌组做了难度下限试玩：`Q0B`/`Q0C` 两人物 100% 胜偏易，`E02`/`E03` 为 50–100%，`E01` 对 P04 仅 4%；`Q0A`/`Q0D` 近似必败，已明确排除出第一学期。数据与复现见实现记录 §7。

2026-11-03：现有 v1 程序已加入 A25–A48 共 24 件通用饰品；规则、奖励/商店与存档集成、既有 UI 套件及启动冒烟已在 Godot 4.7.2 实跑通过，证据见[饰品实现记录](docs/饰品实现记录_20261103.md)与[规则日志摘要](artifacts/verification/relic-expansion-tests-20261103/summary.md)。怪物和 A49–A52 留待后续。当前生产包没有能力牌，因此 A27 在生产局无法触发、A46 的能力分支不可达；隔离 fixture 测试不能证明生产可用。人工视觉、平衡与完整用户路径仍未验证，此项不代表 v3.1 已实现或通过新版阶段。

## 本轮交付与阅读顺序

| 阅读入口 | 内容与状态 |
|---|---|
| [测试房间功能设计](docs/测试房间功能设计.md) | 统一文档（设计定稿 v1.0）：开始界面直接进入、随时更改一切的完整沙盒，含冻结接口/DTO、容量与单步、覆盖层 schema、G7 级界面、检查点/重放与 TR-AC；首版战斗沙盒已实施，剩余能力见实现记录 |
| [测试房间实现记录](docs/测试房间实现记录_20261111.md) | 首版战斗沙盒：隔离上下文、编辑事务/检查点、独立文件、主菜单入口、测试主页、战斗 HUD 与重写后的分页草稿编辑器（搜索/预览/应用/丢弃、F2/Esc/Ctrl+Z）；规则与 UI 回归退出 0，1280×800 与 960×600 实渲；未完成开关/重放/125–150% 实渲等缺口 |
| [战斗反馈与地图分岔](docs/战斗地图反馈实施记录_20261105.md) | 无专注点击不进介绍；抽牌/弃牌/消耗及结算反馈；新局地图按当前位置分岔，旧档保留冻结路线；完整回归与两尺寸 18 张实渲通过 |
| [阶段执行状态总览](docs/阶段执行状态总览.md) | G0–G8 当前实现、真实证据与剩余出口 |
| [执行记录核对与旧版清理](docs/执行记录核对与旧版清理_20261104.md) | 本次修正、7 份删除清单、原文字节备份及验证 |
| [本轮实现与完成状态](docs/四学年地图与视听实现记录_20261104.md) | 完成清单、真实测试证据、限制与下一步 |
| [四大地图方案](docs/四大地图复杂化设计方案.md) | 地图维护源，20/28/36/40 候选节点、12/12/14/14 层，共 52 层路线 |
| [饰品与学年大奖励](docs/饰品奖励与学期结束大奖励设计_v0.md) | 3 槽、16 种饰品、8 次饰品奖励、4 次学年大奖励；旧文件名保留链接 |
| [UI 体验改善实施记录](docs/UI体验改善实施记录_20261104.md) / [原方案](动作或者图片描述/UI体验与布局改善方案_参考杀戮尖塔2_20261104.md) | A–D 已实施：中央选卡/悬停详情、分类奖励、路线画布、目标比较、原生紧凑战斗、三档字号与反馈；规则/UI 回归及 56 张实渲通过 |
| [UI、音效与地图总结](docs/UI_音效_地图设计总结.md) | 当前页面、战斗摘要/快捷键、五路音量与素材缺口 |
| [卡图生产与使用](docs/八格卡图生产与接入_20261104.md) / [提示词](docs/全新卡牌图片生成提示词_v3.md) / [资源记录](docs/art/card-art-assets-v3.json) | 174 张新卡图已生成、核对并接入；四角色战斗及奖励/商店/牌组等页面通过显示验证，人工最终签收待办 |
| [人物、饰品与任务补图接入](docs/缺图素材生产与接入_20261104.md) / [资源记录](docs/art/missing-art-assets.json) | 71 张图片已接入：2 主角、3 伙伴、16 饰品、50 任务；导入、规则/UI 回归与两尺寸 18 张实渲截图核验通过 |
| [本轮设计](docs/plans/2026-11-04-four-year-design.md) / [视听需求](动作或者图片描述/四学年地图与视听优化_20261104.md) | 状态、交互与验收追踪 |
| [综合设计总览](docs/综合设计总览.md) / [角色设计](docs/角色与专属卡池重设计_v3.md) / [完整卡表](docs/校园卡牌设计表_v3.md) | 人物、规则和卡文维护源；旧总览 Excel 仅表示 2026-10-30 设计快照 |
| [卡牌实现契约](docs/卡牌实现契约_v3.md) | 已接线机制、R3 矩阵与已知偏差；目录不等于运行包 |
| [实施计划](实施计划与验收基线.md) / [工作约定](agent.md) | §0.6 已记录用户确认的本轮范围及实施例外；整版基线待核对项、完整路径/性能/打包验收仍待完成 |
| [项目计划](docs/交大四年_DDL战争_项目计划书.md) / [规则书](docs/交大四年_DDL战争_游戏规则书.md) / [统一设计](docs/交大四年_DDL战争_统一设计文档.md) / [设计思路](docs/交大四年_DDL战争_完整设计思路.md) | 四年范围覆盖旧切片限制，战斗规则仍依现有维护源 |
| [内容](docs/内容层契约.md) / [战斗](docs/战斗模块契约.md) / [局流程](docs/局流程契约.md) / [界面](docs/界面层契约.md) | 模块与只读视图边界 |
| [架构](docs/初步架构设计.md) / [接口](docs/接口文档.md) / [存储](docs/数据库与实体关系设计.md) | 公共动作、稳定快照、Settings 与恢复 |
| [需求台账](动作或者图片描述/需求台账.md) / [音频说明](assets/audio/README.md) | 实现追踪与占位资源 |
| [G0](docs/G0基线执行记录.md) / [G1](docs/G1工程骨架执行记录.md) / [G2](docs/G2内容与基础状态执行记录.md) / [G3](docs/G3战斗规则执行记录.md) / [G4](docs/G4局流程执行记录.md) / [G5](docs/G5存档恢复执行记录.md) / [G6](docs/G6资源准备执行记录.md) / [G7](docs/G7界面执行记录.md) / [G8](docs/G8整局体验验收记录.md) | 已更新为当前四年状态；[实现快照与旧基线](docs/baselines/README.md)分开登记 |
| [精英实现](docs/精英敌人实现记录_20261101.md) / [小怪实现](docs/小怪实现记录_20261102.md) / [历史文档](docs/archive/2026-11-04/README.md) / [旧设计交付](artifacts/redesign-20261030/README.md) | 历史来源、既有缺口及抽象模拟，非当前平衡签收 |

四人共11条主流派，牌组可在同人物内混搭。许知微只有发表和章节两主路线，引用循环及完成度经营纳入桥接；章节可以持续输出，发表会拆掉章节引擎。这是相对论文参考稿的新增设计，完整取舍见本轮汇总。

2026-10-30 协作合并保留了其他人的[饰品与怪物候选](docs/饰品与怪物.md)和[小怪草稿历史候选](docs/小怪设计草稿_历史候选_20261030.md)。两份原方案均按来源版本归档，不进入当前 v3.1 范围；冲突以本轮设计为准，详情见[合并说明](artifacts/redesign-20261030/git-integration.md)。

## 维护源与阶段证据

| 入口 | 使用范围 |
|---|---|
| [实施计划与验收基线](实施计划与验收基线.md)、[工作约定](agent.md) | 阶段、范围调整、退出条件和证据要求 |
| [项目计划](docs/交大四年_DDL战争_项目计划书.md)、[规则书](docs/交大四年_DDL战争_游戏规则书.md)、[统一设计](docs/交大四年_DDL战争_统一设计文档.md)、[设计思路](docs/交大四年_DDL战争_完整设计思路.md) | 当前v2上游，已直接重写；旧来源原文/hash可从 Git 历史查阅 |
| [G0登记](docs/baselines/g0.json)、[需求追踪](docs/G0需求追踪.md)、[G0记录](docs/G0基线执行记录.md) | v1 精确生产范围、裁决和历史核验 |
| [精英敌人实现记录](docs/精英敌人实现记录_20261101.md) | 2026-11-01/02 精英遭遇的内容/引擎扩充、首期名单与试玩、未完成项与验证状态 |
| [饰品实现记录](docs/饰品实现记录_20261103.md) | v1 A25–A48 的范围、触发规则、实现与实测状态；A49–A52 及怪物仍待后续 |
| [架构](docs/初步架构设计.md)、[接口](docs/接口文档.md)、[存储设计](docs/数据库与实体关系设计.md) | 模块边界、公共 API、稳定存档与恢复 |
| [内容契约](docs/内容层契约.md)、[战斗契约](docs/战斗模块契约.md)、[局流程契约](docs/局流程契约.md)、[界面契约](docs/界面层契约.md) | v2目标行为；现有代码/schema/API仍v1，新版待冻结 |
| [玩家术语说明](docs/卡牌名词与Buff效果说明.md) | v2名词、人物资源、合作、场景与考试说明 |
| [G1](docs/G1工程骨架执行记录.md)、[G2](docs/G2内容与基础状态执行记录.md)、[G3](docs/G3战斗规则执行记录.md)、[G4](docs/G4局流程执行记录.md)、[G5](docs/G5存档恢复执行记录.md) | 已执行的工程、内容、战斗、局流程和存档验收 |
| [G6制作包](assets/g6/README.md)、[G6记录](docs/G6资源准备执行记录.md)、[G7记录](docs/G7界面执行记录.md) | 现有 46 个素材、合并后的制作规范和批次、实际验证及边界 |
| [UI需求台账](动作或者图片描述/需求台账.md)、[G7设计](动作或者图片描述/G7界面与交互设计.md)、[新版文字需求](动作或者图片描述/角色卡池重设计需求_v2.md) | v1 已验证条目与 v2 待实现需求分别登记 |

新版实施先重新G0冻结生产ID、事件/经济、事件队列和schema/存档兼容，再依G1～G8逐步实现与留证。当前静态文档检查不代表平衡、完整用户路径或发布通过。

林序以顺序和复用构筑，许知微以论文与章节构筑，沈见章以负面联动，唐以宁以伙伴与协同构筑。奖励按当前人物＋公共非基础永久牌过滤，每人 50 种资格。

## 启动与核验

使用 Godot `4.7.2.stable`（本机版本串 `4.7.2.stable.official.ed1daf0bf`）。2026-11-01 的实测记录使用 `D:\Godot\Godot_v4.7.2-stable_win64_console.exe`；2026-11-03 本机当前可运行路径为 `D:\chrome\godot\Godot_v4.7.2-stable_win64_console.exe`。`tools/verify_*.ps1` 的内置搜索路径仍为 `F:\GoDot`、`D:\Godot`、`C:\Godot` 与 `godot` 命令；在本机用 `GODOT_BIN` 或 `-GodotPath` 显式指定当前路径。

本轮文档核对已重新执行导入、规则/UI、主入口与预期失败探针，见[本次验证](artifacts/verification/docs-refresh-20261104/runtime-review.json)。

本轮实测 Godot `4.7.2.stable.official.ed1daf0bf`。首次运行或清理 `.godot/` 后先导入以注册全局类：

```powershell
$env:GODOT_BIN = 'D:\chrome\godot\Godot_v4.7.2-stable_win64_console.exe'
# 换机器时可改为：$env:GODOT_BIN = 'F:\GoDot\Godot_v4.7.2-stable_win64_console.exe'
& $env:GODOT_BIN --headless --editor --path . --quit
& $env:GODOT_BIN --path .
```

数据与地图文档使用同一生成器。以下验证将 APPDATA/LOCALAPPDATA 隔离在证据目录，不加载实际玩家存档：

```powershell
python tools/build_four_year_content.py
python tools/build_card_art_prompts.py
python tools/verify_four_year.py local-check res://tests/run_tests.gd res://tests/run_ui_tests.gd
python tools/verify_four_year.py local-ui-target res://tests/run_ui_experience_tests.gd
python tools/verify_four_year.py local-ui-render --visual res://tools/capture_ui_experience.gd
python tools/verify_four_year.py local-capture --visual res://tools/capture_four_year.gd
python tools/verify_four_year.py card-art-usage-render --visual res://tools/check_card_art.gd
python tools/verify_four_year.py missing-art-local --visual res://tools/check_missing_art.gd
python tools/verify_four_year_docs.py
```

验证器当前使用上述 F 盘引擎，换机器时设置 `GODOT_BIN`。证据保存在 `artifacts/verification/four-year-20261104/<运行名>/`，包含命令、环境/版本、输入 SHA256、退出码和原始输出。四年截图位于同级 `visual-final/`；本次 UI 改善截图固定输出到 `artifacts/verification/ui-experience-20261104/visual/`，含 1280×800、960×600 和战斗/奖励/选角三档字号。

卡图使用的[资源检查与截图](artifacts/verification/card-art-20261104/usage/render/result.json)、[规则/UI 回归](artifacts/verification/four-year-20261104/card-art-usage-regression/summary.json)和[实际渲染结果](artifacts/verification/four-year-20261104/card-art-usage-render-final/summary.json)已留存。卡图核验截图固定输出到 `artifacts/verification/card-art-20261104/usage/render/`，命令与引擎输出仍按运行名保存。

玩家数据位于 `user://saves`，Windows 默认为 `%APPDATA%\Godot\app_userdata\交大四年：DDL战争\saves\`。旧入口用自身 manifest/version/hash 读取，本轮未迁移或改写实际玩家档。

旧 `verify_g0.py` 固定核验 v1 历史来源，不能证明新版 G0 通过。受控四年路线和自动页面检查也不替代真人通关、平衡、最终资源签收或发布打包。
