# 交大四年：DDL战争

单人、离线、校园题材的回合制卡牌构筑游戏。**Godot 4.7.2 + GDScript**，本地单体架构。

## 文档入口

| 文档 | 用途 |
|---|---|
| `交大四年_DDL战争_项目计划书.md` | 范围、排期、成功标准、待确认事项 |
| `交大四年_DDL战争_统一设计文档.md` | 人物/卡牌/数值的唯一来源（冲突时以其为准） |
| `交大四年_DDL战争_游戏规则书.md` | 固定编号规则、废止迁移、参数索引 |
| `docs/项目设计/初步架构设计.md` | 模块划分、数据归属、核心流程、开发顺序（§8） |
| `docs/项目设计/接口文档.md` | 模块调用契约（GameSession / GameAction / BattleEngine / RunService） |
| `docs/项目设计/类与方法设计.md` | 类职责与内部方法 |
| `docs/项目设计/数据库与实体关系设计.md` | 实体、快照布局、提交事务与校验 |
| `docs/项目设计/常量与规则配置.md` | 常量与配置的唯一来源说明 |
| `docs/项目设计/战斗模块契约.md` | **src/battle/** 对外契约：BattleEngine / BattleStep / 事件 / 相位顺序 |
| `docs/项目设计/局流程契约.md` | **src/run/** 对外契约：RunService / RunStep / 节点推进规则 / 幂等键 / 视图路由 |

## 现状

- ✅ **P0 工程骨架**：`project.godot`（锁定 4.7.2）、目录骨架、可启动的主场景占位页
- ✅ **开发顺序第 1 步之「内容加载」**：`src/content/content_db.gd` 载入并校验 `data/definitions/rulesets.json`
- ✅ **随机源**：`src/common/random_source.gd`（map/reward/event/battle 四条独立流 + 可保存快照，64 位 seed/state 存十进制字符串）+ `src/common/result.gd`（统一 `Result<T>`）
- ✅ **无头验收测试入口**：`tests/run_tests.gd`（当前 1815 项断言全绿，退出码即 CI 结果）
- ✅ **核心状态层**：`src/common/ids.gd`（run_id + 单调序号，不消耗随机）、`src/run/run_state.gd`（永久牌/饰品/实例序号）、`src/battle/battle_state.gd`（9 个子实体 + 牌区唯一权威）、`src/app/session_state.gd`（revision 与随机快照的唯一持有者）
- ✅ **内容定义层**：`data/definitions/`（cards / characters / relics / tasks / encounters）+ `data/manifests/mvp.json`；`ContentDB.load(manifest_id)` / `get_definition` / `get_candidates` 按 kind 索引、跨类引用校验、候选池过滤（基础标签不进奖励池）
- ✅ **战斗引擎（步骤 1）**：`src/battle/battle_engine.gd`（`begin/preview/apply/make_view` + 显式相位机 + 核心结算）+ `src/battle/card_rules.gd`（有效卡面/费用/合法性预检）；契约见 `docs/项目设计/战斗模块契约.md`，K01/K02 与 N01 可打完整场（赢/输路径均有测试）
- ✅ **战斗引擎（步骤 2）**：K03 效果内选择（先抽后选、待选期间禁操作）、K04 灵感、K13 每实例每回合限次（按 origin_card_id）、K14 编译加值、P01 第 3 张工作牌被动、§3.6 状态到期时点
- ✅ **战斗引擎（步骤 3）**：`data/definitions/{units,scenes}.json`（F01~F08 / L01~L06）+ B01 三阶段首领 + K43/K44/K46/K51/K53/K56 验证卡；单位召入/换班/暂离、合作阶段、护卫改向不溢出、考试备考/回忆面、场景建立替换与本战限次、多阶段转阶段；战斗验证清单 `data/manifests/battle_mvp.json`
- ✅ **存档层（步骤 4 前半）**：`src/storage/`（`SnapshotCodec` 编码/解码/迁移 + checksum、`SaveStore` 原子保存/备份/三层校验/故障恢复、`ProfileMerge` 幂等合并、结局三步提交）；契约见 `docs/项目设计/数据库与实体关系设计.md` §11
- ✅ **局流程（步骤 4 后半）**：`src/run/**` —— RunService / RunMap / RewardOffer / ShopState / EventState / TermSettlement / RunSummary / RewardGenerator / TransactionResolver；一学期 6 节点闭环（进入→开战→结算→奖励→商店→休息→首领→学期结算），契约见 `docs/项目设计/局流程契约.md`
- ✅ **局流程界面（步骤 5）**：`src/ui/**` —— `GameShell`（路由/分发/存档/门控/战斗交接）+ 12 个页面（主菜单/选人/地图/奖励/商店/事件/休息/战斗入口/学期结算/结局/摘要/设置）+ `main.gd` 真入口；契约见 `docs/项目设计/界面层契约.md`（页面跳转表、uid 命名、视图字段来源、存档入口、战斗交接）
- ✅ **内容层（一学期 MVP 完整启用）**：`data/manifests/mvp.json` = **mvp-0.6** —— 24 张正式牌 + X01 特殊牌 + P01/P04 + 8 件饰品（A01/A04/A05/A07/A08/A11/A15/A18）+ N01～N04 与 Q01 与 B01 + F01～F04 + L01～L03 + V01/V03/V04/V10；数值逐条对齐《统一设计文档》§4/§5/§8/§9/§10.2。验收在 `tests/suites/test_content_mvp.gd`（130 条断言：逐字数值 + 每个类别的「出厂清单经 ContentDB 可见」+ 引擎接线核对（op / 被动 trigger / 饰品 hook 时点）+ 账本集合等式），契约见 `docs/项目设计/内容层契约.md`
- ⚠️ **内容层仍存在的缺口**（不影响 MVP，完整 v1.0 需补）：查重护盾 `plagiarism_shield` 未接线「屏障吸收」，ContentDB 加载期会以 `CONTENT_INVALID` + 缺口说明拒绝引用它的定义，受影响的是 N06「查重护盾8」等学期 3 起的任务；账本（landed 考古 / manifest_holdback / outside_mvp）与下一段计划见 `data/manifests/content_deferred.json`
- ⏭ 下一步：教学关与双人物实机试玩（t4）、独立验收（t6/t7）

## 运行

用 Godot 4.7 打开本目录按 F5。主场景 `res://src/ui/main.tscn` → `src/ui/main.gd`：载 `ContentDB`（默认 mvp 清单）→
造 `GameShell` → 打印 `[MAIN] 内容版本=… 清单=… 校验问题=0`，然后进主菜单（继续 / 新局 / 设置）。

战斗界面由 `main.gd` 自动探测 `res://src/ui/battle_screen.tscn`（t1 交付）：有就交给它打；
没有时启用「开发回退（引擎代打）」把战斗结算掉——所以局流程从主菜单到学期结算始终可以整局试玩。

## 无头验收测试

```powershell
$godot = "D:\Tools\Godot_v4.7.2-stable_win64_console.exe"   # 必须用 _console 版才能拿到 stdout
& $godot --headless --path . --script res://tests/run_tests.gd
if ($LASTEXITCODE -ne 0) { throw "测试失败" }
```

每次运行的第一行是**环境行**，它回答「这份结果是哪个版本的」：

```
[ENV] HEAD=b78cd3c dirty=13  ⚠ 工作区有未提交改动：本结果不代表该提交（HEAD=b78cd3c）
```

`HEAD` 用 git plumbing 文件解析（`.git/HEAD` → ref 文件 / `packed-refs` / detached；`.git` 是文件时按
`gitdir:` 走），`dirty` 是 `git status --porcelain` 的行数，取不到就显式写 `dirty=unknown`（**不会静默省略**）。
dirty>0 或 unknown 时那行会跟一句「本结果不代表该提交」——引用/转发任何测试结论前先确认这一行。

冒烟（验证工程可加载、主场景可跑、内容库校验通过、战斗界面探测结果）：

```powershell
& $godot --headless --path . --quit-after 120
```

### 干净检出（新 clone / CI / 未构建的 worktree）：跑测试前先 `--import` 一次

仓库**不提交** `/.godot/`（含 `global_script_class_cache.cfg`）。在全新检出上直接跑主套件，GDScript 解析不到尚未注册的全局类名，会先炸一批、并在 stderr 报 `Identifier not found`：

```powershell
git worktree add .cold HEAD                     # 或 git clone 到新目录
& $godot --headless --path .cold --import       # 一次性：生成 .godot/ 与全局类名缓存
& $godot --headless --path .cold --script res://tests/run_tests.gd
if ($LASTEXITCODE -ne 0) { throw "测试失败" }
```

实测对照（提交 e92f0bd → 修复后 9809d4c，均在临时 worktree 里跑）：

| 步骤 | 修前 e92f0bd | 修后 9809d4c |
|---|---|---|
| 冷检出**不** `--import` 跑主套件 | 403 通过 / 125 失败，stderr 首因 `Compile Error: Identifier not found: BattleState` 与 `RunState` | **1840 通过 / 0 失败**，`Identifier not found` 0 命中 |
| 冷检出 + `--import` 跑主套件 | — | **1840 通过 / 0 失败** |

判读速查：冷跑出现大量「战斗 / 存档 / 局流程」红时，**先看 stderr 有没有 `Identifier not found`**——有就是缺 class cache，不是业务 bug，`--import` 一次即可；没有才去查代码。

修复内容：`src/battle/battle_state.gd` 与 `src/run/run_state.gd` 里**对自身 class_name 直接 `.new()`**（会触发上述报错）改成项目既有写法 `load("res://…").new()`（另有 7 处先例）。`tests/suites/test_cold_checkout_guard.gd` 守住这条不变式：逐行扫 `src/**/*.gd`，任何脚本对自身 class_name 直接 `.new()` 都会被它挡下——它比「逐文件 `--check-only`」强，因为编译器遇错即停、只能看到每个文件的第一处。

⚠️ 一个会让 `[ENV]` 行失去意义的副作用：`--import` 会给每个脚本生成 `.gd.uid`（本次 32 个），而 `.gitignore` 目前**没有**忽略 `*.gd.uid`、仓库又已经跟踪了其中一部分。结果是干净检出跑完 `--import` 后 `git status` 反而变 dirty，`[ENV]` 行显示 `dirty=32 ... 本结果不代表该提交`。
当前选项（**尚未决定，属待评估项**）：整批提交 `.gd.uid`（与已跟踪的部分一致），或在 `.gitignore` 加 `*.gd.uid` 并停止跟踪。定案前，若 `dirty` 计数全部由 `.gd.uid` 构成，可以忽略该警告。

界面层的两套冒烟已登记进 `run_tests.gd`：`tests/suites/test_ui_shell_pages.gd`（12 个页面的按钮可用性/门控/离线视图）与
`tests/suites/test_ui_shell_run.gd`（只用 press(uid) 走完一学期 6 个节点 + 存档继续 + 失败重开 + 出厂清单首领可达）。

### 套件登记规则（运行时自动发现，不需要改共享文件）

`tests/run_tests.gd` **不再 preload 任何套件**，它在运行时枚举 `tests/suites/` 顶层的 `test_*.gd` 并按路径排序逐个跑：

- **新增套件 = 把文件放进 `tests/suites/`**（`extends RefCounted` + `func run(h)`），不需要改任何共享文件；
- `tests/suites/audits/**` **永不自动跑**（那里是刻意红的独立审查探针），只用自己的显式入口：
  `& $godot --headless --path . --script res://tests/suites/audits/audit_storage_run.gd`；
- 某个套件解析失败时，只记一条失败（`[FAIL] 套件可加载：<文件>`）并继续跑其余套件——**局部失败不坍塌成全树失败**；
- 主套件有看门狗：即使某个套件打断了收尾流程，也会强制 `quit()`，不会像以前那样空转到超时；
- 跑 `--script` 的入口建议加 `--quit-after 3000` 作保险（Godot 的 SceneTree 在编译失败时不会自己退出）。

新增套件后自查（不要只看工作区，要看 HEAD 本身；工作区干净 ≠ HEAD 自洽）：

```powershell
git cat-file -e HEAD:tests/suites/test_xxx.gd      # 该路径在 HEAD 里存在吗
git ls-tree -r HEAD --name-only | Select-String tests/suites   # HEAD 里到底跟踪了哪些测试文件
```

### 沙箱注意（本机 dsh 特有）

Godot 把 `user://` 写到 `%APPDATA%\Godot\...`，而本机沙箱对 `C:\Users\...\AppData` 没有写权限，
会报 `Could not create directory: 'user://logs'`。在**本机/CI** 里把 APPDATA 重定向到工作区即可：

```powershell
$env:APPDATA = "D:\Code\card\.godot-user"
```

`.godot-user/` 已进 `.gitignore`；真实玩家环境不需要这个变量。

## 实现约定

- 规则核心是普通数据对象，**不依赖场景树、动画与音频**；UI 只提交操作、只渲染快照与事件。
- **JSON 是运行数值的唯一来源**；GDScript 只存稳定标识（`src/common/game_constants.gd`）。
- Godot 的 `JSON` 解析把**所有数字都解析成 float**：读整数一律走 `ContentDB.run_int()/battle_int()/status_int()`，
  不要写 `typeof(x) == TYPE_INT` 这种校验。
- 协议与存档存字符串值（`GameConstants` 常量），不存枚举数字或常量变量名。
- 新内容必须能写进 `data/definitions/*.json` 并被 `validate()` 检查，不硬编码进 GDScript。
- Godot 不暴露 `Outer.Inner.new()`：跨脚本造子实体一律走 `BattleState.create_*()` 工厂。
- 内层类名不能与 Godot 原生类同名（`SceneState` 已被引擎占用，代码里叫 `BattleSceneState`）。

## 历史与待决

仓库 `HEAD`（4acbcdf）仍是旧项目「PVE 卡牌战斗 Demo」（Godot 4.7 遗迹战斗 Demo：`src/core/battle_engine.gd`
1144 行、`tests/run_tests.gd` 992 行、`assets/art`、`tools/*.py`）。本轮按《统一设计文档》v1.0 重设计提案
重写：旧 Demo 的「点数与融牌」体系已被规则书明确**废止**，故其 92 个源码/美术文件目前处于
「已删除、未提交」状态，未做恢复。

**待确认**：是否恢复其中仍可复用的部分（无头测试脚手架写法、`assets/art` 占位美术、`tools/*.py` 生成脚本）。
