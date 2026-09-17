# PVE 卡牌战斗 Demo（Godot 4）

按 `docs/PVE卡牌战斗Demo场景与构建规格.md`（v0.2）实现的单人 PVE 回合制卡牌战斗 Demo。
玩家扮演进入遗迹的冒险者，在「遗迹入口」与练习魔像战斗，击败魔像即完成 Demo。

> 📄 **现状 + 后续升级计划**见 `docs/PVE卡牌Demo_开发文档.md`（单一入口文档）。
> 🎨 **元素与 UI 设计说明（含配图）**见 `docs/PVE卡牌Demo_元素设计文档.md`，配图在 `docs/design/`。
> **设计决策表见 `docs/设计元素表.xlsx`**（13 张表：游戏基本信息 / 实体 / 卡牌 / 游戏机制 / 配色 / 字号 / 布局 / 尺寸 / 美术资源 / 配图）
> —— 要改任何设计元素或玩法数值，在「你的决定」列里填即可；助手用 `python tools\read_design_workbook.py` 读回。
> 升级方案工作簿见 `docs/PVE卡牌Demo_升级方案.xlsx`。本文是面向开发者的运行与架构说明。

- 引擎：**Godot 4.7.2**（GDScript）
- 设计分辨率与**默认窗口均为 1600 × 900**，拉伸模式 `canvas_items` + `keep`
- 启动后**直接进入战斗**（无主菜单、无路线选择）

---

## 快速开始

用 Godot 4.7 打开本目录（`project.godot` 所在处），按 F5 运行。
主场景已配置为 `res://src/ui/battle_scene.tscn`。

命令行运行（Windows 示例，路径按实际安装位置替换）：

```powershell
$godot = "D:\Tools\Godot_v4.7.2-stable_win64.exe"
& $godot --path D:\Code\card
```

### 操作

| 操作 | 说明 |
|---|---|
| 左键点击手牌 | 选中；单体牌需再点击魔像确认，无目标牌会出现「确认使用」按钮或再次点击卡牌生效 |
| 右键 / Esc / 点击空白 | 取消选择 |
| 结束回合 | 有手牌时进入「保留一张牌」选择，可取消返回行动阶段 |
| 顶栏「玩法说明」 | 打开规则弹窗（打开期间阻止背景操作，关闭后不推进回合） |
| 顶栏「快速」 | 缩短/跳过非必要演出，不影响任何规则结果 |
| 抽牌堆 / 弃牌堆 | 点击查看；抽牌堆只显示组成与数量，不暴露抽取顺序 |
| 结算日志 | 右下角可折叠 |

---

## 目录结构

```
project.godot              项目配置
docs/                      规格文档（只读输入，未改动）
src/core/                  规则层（纯 GDScript，不依赖任何场景节点）
  battle_types.gd            枚举、常量、事件类型
  card_db.gd                 11 种卡牌配置（§7）
  enemy_db.gd                练习魔像与遭遇配置（§8）
  battle_state.gd            战斗状态数据容器（§10）
  battle_engine.gd           规则引擎：状态机、能量、抽牌、伤害、随从、场景、敌方阶段
src/ui/                    界面层
  battle_scene.tscn/.gd      战斗场景：布局、交互、事件播放、弹窗
  card_view.gd               卡牌视图
  minion_view.gd             随从槽位视图
  palette.gd                 配色与中文字体
tests/
  run_tests.gd               规则层验收测试（对应 §12 的 A01–A25）
  ui_smoke.gd                界面冒烟测试（含 A19 / A22 的界面行为）
  ui_input.gd                真实鼠标输入测试（push_input 走完整 GUI 事件路由）
  event_trace.gd             事件链示例：逐条打印规则层产生的事件（见「事件链」一节）
  probe.gd、smoke.gd         早期语法/环境探针，保留备用
tools/
  make_upgrade_xlsx.py       生成升级方案工作簿
  verify_xlsx.py             读回校验工作簿结构
  make_design_assets.py      生成元素设计文档的配图（PNG + SVG）
  verify_design_assets.py    校验配图边界 / 墨迹 / 中文字形 / 坐标与实现一致
  verify_doc.py              把开发文档的事实性声明反向核回源码
  make_design_workbook.py    生成《设计元素表》Excel（含嵌入配图）
  read_design_workbook.py    读回设计元素表，只报告被改动的项
docs/design/                 元素设计配图（9 张 × PNG 预览 + SVG 源）
```

---

## 架构要点

**规则与表现严格分离**（§1、§10）。规则层不 `extends Node`、不碰任何 UI，可用固定随机种子完整复现一场战斗；
每个规则入口返回**有序事件数组**，界面只播放事件：

```gdscript
engine.start_battle(seed)        # 初始化战斗 + 首个玩家回合
engine.play_card(instance_id)    # 使用卡牌（内部先校验，成功才扣费执行）
engine.request_end_turn()        # 点击结束回合 → 返回是否需要保留选择
engine.confirm_end_turn(keep_id) # 确认结束回合：保留 → 弃牌 → 随从自动攻击 → 敌方阶段 → 新回合
engine.cancel_end_turn()
engine.restart(seed)             # 重新挑战
```

界面**不计算伤害**，伤害只由规则层结算一次（§10）。动画与节奏完全不影响结果。

### 实现时容易踩错的规则

- **费用与回能的顺序**是卡牌效果的一部分：斩击是「先 +1 能量，再造成 5 伤害」。
- **追击**读取的是本回合「此前」已成功使用的攻击牌数，因此实现上先快照再自增计数；技能即使造成伤害也不计入。
- **破盾击**按本次伤害结算**前**目标是否有护盾决定打 3 还是 7。
- **护盾清除时机不对称**：玩家护盾在下个玩家回合开始清除；魔像护盾在下个敌方阶段开始时才清除，所以它的护盾会保护它度过玩家的下一整个回合。
- **承伤回能**只在敌方行动造成玩家**生命**伤害时触发：被护盾完全吸收不触发，随从受伤不触发，自伤不触发。
- **结算区**的存在是必要的：正在结算的过牌卡（战术整理）在本次洗牌时不会被抽回。
- **终局即冻结**：一旦进入胜负，停止当前卡牌的后续效果、剩余随从攻击与敌方行动。
- **嘲讽与溢出**：单段伤害击败随从后的超额伤害不溢出给玩家。
- **意图目标实时联动**：数值在公开后锁定，但召唤嘲讽随从会使攻击目标立即改变。

---

## 测试

```powershell
& $godot --headless --path . --script res://tests/run_tests.gd   # 规则层 157 项断言
& $godot --headless --path . --script res://tests/ui_smoke.gd    # 界面  53 项断言
& $godot --headless --path . --script res://tests/ui_input.gd    # 真实输入 9 项断言
& $godot --headless --path . --script res://tests/event_trace.gd # 事件链示例（只打印，不做断言）
```

三套测试均以**退出码**表示结果（0 = 全部通过）。当前状态：全部通过（各跑 8 轮稳定）。
`ui_smoke.gd` 每轮使用随机种子，存在与手牌相关的分支，因此断言只依赖「实例所在区域」这类与抽牌无关的量。

### 事件链

`event_trace.gd` 会把规则层产生的事件逐条打印出来，是理解「逻辑怎么跑」最快的方式：

```powershell
& $godot --headless --path . --script res://tests/event_trace.gd
```

它跑三个场景：**A** 规格 §8.2 的第一回合手把手指例（可与文档逐步对照）；
**B** 嘲讽随从实时改变意图目标 → 随从击杀魔像 → 终局截断后续事件；
**C** 回合开始的固定顺序（先「回合 +1 能量」再「场景 +1 能量」）。

事件是一条**有序、只读的记录**：规则层改完状态后按发生顺序追加，界面照着播即可。
典型的一条链（打出一张攻击牌）：

```
card_moved        斩击  手牌 → 结算区     ← §6.3 普通牌先进结算区
card_played       打出「斩击」
attack_card_used  本回合已成功使用攻击牌 1 张
energy_changed    delta=+1 → 2（来源 卡牌效果） ← 效果声明「先回能，后伤害」
card_gained_energy「斩击」作为卡牌效果回能 1
damage            魔像 受到 5 伤害（护盾吸收 0，生命 -5）→ 剩余生命 30
card_moved        斩击  结算区 → 弃牌堆
```


### 为什么单独有 ui_input.gd

`ui_smoke.gd` 是**直接调用** `_on_card_clicked()` 等处理函数的，跳过了 Godot 的 GUI 事件路由。
真实鼠标点击曾因此漏掉两个 bug：

1. 选中手牌时 `_refresh_hand()` 会销毁正在处理该次点击的卡牌，`accept_event()` 随之失效，
   事件继续冒泡到 `_unhandled_input` 并被当成「点击空白处」——表现为**点一下选中、同一下又取消，永远出不了牌**。
   修法：选中态改为就地更新（`_update_selection_visuals()`），不重建节点。
2. 根 `Control` 默认 `mouse_filter = MOUSE_FILTER_STOP`，会吃掉空白处的鼠标事件，使「点击空白处 / 右键取消」失效。
   修法：根节点设 `IGNORE`，另加一个位于最底层的空白处 catcher（`_bg_catcher`）专门负责取消选择。

这两个 bug 互相掩盖：不修 (1) 就暴露不出 (2)。

规格 §12 的 A01–A25 覆盖情况：

- **A01–A18、A20、A21、A23、A24、A25** —— 由 `run_tests.gd` 直接断言规则层行为。
- **A19（连续点击再来一局）** —— 规则层验证状态不重复初始化，界面层验证 `_restarting` 保护、飘字与弹窗清理。
- **A22（玩法说明弹窗）** —— 界面层验证遮罩拦截鼠标、开合时回合/生命/能量均不变。

---

## 已知偏差与未实现项

1. **基础音效未实现**（§11 构建顺序第 6 步的一部分）。仓库内无音频资源，且第 6 步属「打磨表现」，按规格「优先交付完整流程，再打磨表现」的次序留待后续。
2. **伤害预览未实现**（§5.1 中标注为「可以展示」，非强制）。
3. **角色与卡面为图形/文字占位**，符合 §4.1「初版允许使用图形占位角色」。
4. **新增了一个规格未提及的「重开本局」按钮**（右下角控制区），用于 Demo 中途重开；不影响任何规则。规格原本只在胜负弹窗提供「再来一局」。
5. **界面用代码构建而非 `.tscn` 手工摆放**。`battle_scene.tscn` 只有一个挂脚本的根节点，全部控件在 `_build_ui()` 中创建。这是刻意的取舍：布局逻辑集中在可 diff、可测试的代码里。若后续要做美术化排版，可逐步迁移到 `.tscn`。

---

## 环境注意事项

- 请使用**标准（非 mono）构建**，例如 `D:\Tools\Godot_v4.7.2-stable_win64.exe`。
  若改用 mono 版且本机未安装 .NET 8，启动时会打印若干 `.NET: Failed to load compatible .NET runtime` 错误；
  本项目只用 GDScript，**不受影响**，但建议直接用标准构建以免刷屏。
- `user://` 指向 `%APPDATA%\Godot\app_userdata\<项目名>`。若该目录不可写，Godot 会提示无法写日志与着色器缓存，
  同样不影响玩法。把 `[application] config/name` 改成 ASCII 名称可避免路径中的中文。
- **中文字体**：Godot 内置默认字体不含 CJK 字形。`src/ui/palette.gd` 通过 `SystemFont` 挂载
  微软雅黑 / SimHei / Noto Sans CJK 等系统字体，测试中已断言字形可用。若移植到无这些字体的平台，需自带字体文件。
