# P01 / N01 动作精修设计、结果与后续方案

2026-11-15继续精修已交付：[第二轮对照](../../artifacts/verification/actor-rig-refinement-20261115/review/index.html)及[结果与下一步](2026-11-15-actor-refinement-design.md)完成肩肘、持物、眨眼/纸扇与场景地面，287项检查及兼容/规则/完整UI通过；累计API6/200张。下文保持第一轮v2的原始结果与差距记录。

实施开始：2026-11-14；评审交付：2026-11-15。用户要求在已完成的代表样板上精修，重点解决僵硬感，并联网参考《杀戮尖塔2》的动画实现。依据根计划§0.20.15，沿UIR-011/013/051/052/054/057/059执行。当前状态：精修已实现，最终实渲、旧样板兼容、完整规则与UI回归通过，交付用户查看；最终美术质量未签收。

**结论：Godot原生二维骨骼路线可以继续。** 本版已把首版的整体摆动改为身体重心、分关节动作、脚部支撑和独立次级循环，并在真实出牌/敌方行动/最后一击中运行。肩肘接缝、表情、持物拆分和场景地面仍限制最终观感，不能据自动测试宣称已经达到二代角色表现。

先打开[精修前后同步动画](../../artifacts/verification/actor-rig-polish-20261114/review/index.html)：默认实际运行速度，可暂停、重播、拖动到任意采集时刻，切换人物特写/完整战斗区；受控试镜和慢放分别标明。另有[同场截图](../../artifacts/verification/actor-rig-polish-20261114/review/comparison.jpg)、[真实实渲报告](../../artifacts/verification/actor-rig-polish-20261114/render-04/report.json)、[启动器](../../tools/start_actor_rig_polish.ps1)。原[首版方案与结果](2026-11-14-actor-rig-feasibility-plan.md)继续保留历史范围。

## 1. 实施前设计与范围

采用现有原生骨架继续精修：不同身体部件独立错峰，动作蓄力—快速作用—跟随—回收；待机呼吸与纸页循环独立，姿态切换从当前状态混合。加入身体位置/缩放/局部关节形变与脚部支撑，避免整张立绘绕点摆动。先用当前已核对的完整部件验证动作改善，需要补件时使用已授权现有API；不以增加生图张数代替动画打磨。

替代路线为迁移专用动画编辑器或逐帧重画。当前优先原生精修，因为已有真实战斗与生命周期验证，能直接比较同一角色；是否迁移编辑器应以编辑效率和最终可见质量决定。官方资料能证明的技术与本作设计推断分别登记，不把二代全部角色的具体软件/绑定方式当成已证实事实。

实施前核对当前部件/轴心/遮挡和官方连续动作，保留改前文件与hash。先制作局部角色/敌怪的动作试镜，再接真实seed32战斗；受控试镜与真实命令分开标记。两窗口、三字号、有效×4及用户倍速、减少动态、打断/取消/离场/重入、固定HUD/目标和逐命令领域/RNG/revision一致性均需留证。最终离线评审页提供精修前后相同动作、实际倍速与有标识的慢放；慢放不能替代正常运行效果。

现有资源G6子项继续限于P01/N01。默认入口不启用试验，玩家档隔离，已否决资源不恢复，冻结提交包不更新。最终美术可行性由用户查看精修画面后判断；本批不扩大为全量验收。

## 2. 联网资料核对：已披露事实与本作选择

官方原文、取得时间和SHA256均保存在[联网来源元数据](../../artifacts/verification/actor-rig-polish-20261114/research/sources.json)，逐项核对见[资源与资料记录](../../artifacts/verification/actor-rig-polish-20261114/resource-review.md)。

| 官方材料 | 可确认内容 | 本版采用的处理 |
|---|---|---|
| Mega Crit 2024-10-02月刊 | 增加动画、过渡与活力，同时重视操作响应 | 关键姿势清楚、动作有限收尾，保留实际基础×4和用户倍速 |
| Mega Crit 2026-07-17，动画师Chris介绍Aeonglass | 先用二维软件测试模拟三维环旋转，再画攻击草稿、调整环与剪影 | 先验证动作轮廓和作用关系，再接真实事件，保留实际尺寸的连续对照 |
| 同一官方说明 | 环使用独立时间线，受击/施法不中断旋转；流动物质在引擎内用shader替换占位表现 | 将待机呼吸、纸页、夹子、书签循环与行动分离；不随命中重播，不为纸怪强加该Boss材质 |
| Godot官方Animation / AnimationPlayer文档 | 属性轨道、插值、混合与播放完成信号 | 使用位置/旋转/缩放曲线，从当前姿态混合，以真实播放完成收尾 |
| Spine官方Applying Animations | 多轨混合与动画过渡 | 作为替代制作工具的通用对照；不能据此证明二代全部角色使用Spine |

二代全部角色的绑定文件、完整中间件配置和最新构建动画未公开在这些材料中。两段脚部IK、具体时长、错峰曲线与事件作用点是本作实现，不冒充Mega Crit公开的统一实现。

## 3. 最终实现

| 僵硬来源 | 改动 | 实际可见结果与限制 |
|---|---|---|
| 人物整片摆动、腿身过长 | 调整身体比例，腿部拆成大腿/小腿/脚踝骨骼；两个三权重网格及脚部IK | 身体可移动重心，脚部保持支点；当前站姿仍偏含膝，后续需结合造型修整 |
| 各部件同时开始、同时停止 | 为头、躯干、前后臂、衣摆/纸页/夹子分别写曲线 | 蓄力、快速作用、跟随回收错开；道具与前臂仍是一块图，手指不能单独表演 |
| 纸怪主体像硬纸板 | 主体增加网格与压缩/拉伸，纸页、夹子、书签独立循环 | 出手能压低、伸展再回弹；大幅转体仍缺替换绘图 |
| 动作打断先复位、收势提前被定时器截断 | 从当前姿态交叉混合；AnimationPlayer完成信号负责收尾，保留有限超时兜底 | 受击不中断次级循环，回收不被旧计时器截掉；减少动态同步稳定IK |
| 已扣数值，角色才出手 | 精修入口将局部命中、完成量/压力提示和表条表现延后到作用阶段 | 不改变领域即时发布、命令顺序和实际数值；后续更复杂多段技能仍需单独验证 |
| 最后一击目标先消失 | 在表现层保留被移除目标，完成受击/离场后再释放并进入奖励 | 真实最后一击保留倒下过程，待机不进入终局等待；没有增加领域实体 |
| 与背景缺少联系 | 由脚部位置绘制柔和接触阴影 | 局部承托有所改善，但教室地面透视仍不匹配，整体悬浮感未完全解决 |

P01现在为20骨骼、8件在用部件、3个加权网格；N01为14骨骼、9件、2个网格。图片与原图hash保持一致；本批仅生成新的rig/source描述文件，没有新增API图片，累计仍为5/200张。原rig和纹理未覆盖。

动作编排时长与实际基础速度分开保存：P01出手1.72秒、受击1.36秒、离场1.80秒；N01出手1.80秒、受击1.40秒、离场2.00秒。页面1×时实际分别除以4，例如P01出手约0.43秒、N01出手约0.45秒。已测用户1/2/3倍下P01动作实际0.429/0.217/0.138秒，对应预期0.430/0.215/0.143秒；这里是动作定时实测，不是帧率或最低配置成绩。独立循环不纳入终局屏障。

改动位置：`src/ui/battle/native_actor_rig.gd`、`battle_actor_view.gd`、`battle_stage_effects.gd`、`src/ui/battle_screen.gd`和`src/ui/game_shell.gd`。精修开关和资源根路径由`tools/run_actor_rig_pilot.gd --polished`启用；默认入口及首版v1资源路径保持原行为。资源可用`python tools/build_actor_motion_polish.py`重建；评审页可用`python tools/build_actor_motion_review.py`重建。

## 4. 真实验证与可复现证据

| 验证 | 实际结果 | 原始证据 |
|---|---|---|
| 最终精修实渲render-04 | 259项检查，零失败；5条真实命令，19张PNG、459帧；42.966秒，退出0/引擎错误0 | [报告](../../artifacts/verification/actor-rig-polish-20261114/render-04/report.json)、[命令/输入hash](../../artifacts/verification/actor-rig-polish-20261114/render-04.run.json)、[stdout](../../artifacts/verification/actor-rig-polish-20261114/render-04.stdout.txt) |
| 旧样板兼容 | 226项检查，19张PNG、245帧；28.380秒，退出0/错误0 | [报告](../../artifacts/verification/actor-rig-polish-20261114/legacy-compat-01/report.json)、[运行元数据](../../artifacts/verification/actor-rig-polish-20261114/legacy-compat-01.run.json) |
| 完整规则套件 | G1/G2/G3、G4、G5通过；60.285秒，退出0/错误0 | [原始日志](../../artifacts/verification/actor-rig-polish-20261114/regression-rules-01.stdout.txt)、[运行元数据](../../artifacts/verification/actor-rig-polish-20261114/regression-rules-01.run.json) |
| 完整UI套件 | G7通过；268.834秒，退出0/错误0 | [原始日志](../../artifacts/verification/actor-rig-polish-20261114/regression-ui-01.stdout.txt)、[运行元数据](../../artifacts/verification/actor-rig-polish-20261114/regression-ui-01.run.json) |
| 最终输入补核 | 补充GameShell与构建/验证脚本hash后再运行240项非截图检查，5条真实命令；19.527秒，退出0/错误0 | [报告](../../artifacts/verification/actor-rig-polish-20261114/final-input-check-01/report.json)、[44个输入hash](../../artifacts/verification/actor-rig-polish-20261114/final-input-check-01.run.json) |
| 离线评审页 | 1440与640宽度无水平溢出，播放/暂停/拖动、取景和慢放可用，页面错误/失败资源0 | [浏览器记录与截图](../../artifacts/verification/actor-rig-polish-20261114/review-browser/report.json) |

真实命令为seed32正常首战：4次工作牌、1次结束回合，完成24工作量，玩家72→67精力，正常进入奖励。每条命令与独立无骨架会话的领域/RNG/revision/事件记录指纹一致。自动输入来自正常GameShell提交路径，不冒充真人自然通关。

1280×800、960×600及100/125/150%字号定向核对覆盖固定HUD/目标区、真实选牌、动作中待机连续、当前姿态打断、减少动态完全稳定、取消/清理/重入和最终事件屏障。最终采样中脚踝端点最大误差为0.000504个骨架单位；这是端点约束证据，不等于每个贴图像素无形变或最终视觉已验收。

已经实际查看同场全图、小窗口150%、正常速度与慢放逐段联系表，以及浏览器中的出牌/敌方命中/离场前后对照。P01重心、纸怪压缩回弹和最后一击保留有改善；肩肘拼接、静止面部和教室悬浮感仍能看到。独立GIF按实际采集间隔保存，GIF有10ms时间量化；交互播放器使用原始毫秒记录。截图回读和写盘影响采样，不作性能基准。

迭代如实保留：render-01因减少动态后的IK单帧变化有6项失败，render-03因前倾姿态脚部超出可达范围有1项失败；render-02虽通过行为检查，仍发现回收可能被定时器提前结束，继续修正后才选择render-04交付。导入退出0/错误0，旧证据目录的重复UID警告留在原stderr，不声称无警告。CodeGraph对本批GDScript查询返回无关Python符号，已按失败结果使用限定文件读取，未重建索引。

## 5. 下一步可行方案与判断条件

| 顺序 | 具体工作 | 进入下一步的条件 |
|---|---|---|
| A1，本轮已交付评审 | P01/N01关节、权重、独立循环、脚部支点、动作节奏和真实事件精修 | 用户能在正常速度前后对照中判断僵硬感是否已下降；当前交付不替用户作最终审美决定 |
| A2，代表资源继续打磨 | 修补肩肘覆盖；拆分笔记本/手腕，增加2～3个作用方向和必要表情；修正场景地面透视 | 静止、动作峰值和连续衔接均没有明显断口，实际游戏尺寸下轮廓、力度与承托可接受 |
| B，验证不同类型 | 再做1个真实同伴、1个非纸片精英、1个有真实阶段切换的Boss；逐个资源核对后进入真实事件 | 不同体型、持续循环和阶段映射均成立，且能估算每套实际绘制/绑定工时 |
| C，小批生产 | 沿原71实体/88任务阶段清单分家族生产；只补实际缺件，保持生成预算累计追踪 | 每批有原件、拆件源、动作版本、映射、hash、实渲和美术意见，不靠批量生图代替动作设计 |
| D，全流程与默认启用 | 已核收资源接入多人目标/房间/真实Boss和低配置场景，完成完整G7/G8要求 | 两尺寸三字号、真实交互、自然路径、性能与打包证据齐全后，再处理默认启用 |

制作工具先继续使用原生AnimationPlayer及JSON曲线。若A2在大量替换绘图、网格编辑和动作调参上明显低效，再以同一角色导出一段专用动画工具版本比较编辑效率、运行时兼容、授权费用和最终画面；本批未采购中间件，也未证明迁移必然改善动作。当前主要瓶颈是动画用拆件和关键姿势，单纯增加骨骼或更换软件不能补出缺失绘图。

API上限不是生产张数目标，本轮0新增；全量工时和最终费用尚无不同类型样本，暂不报确定数值。全量资源人工审美/许可、自然四年路径、最低配置和Windows发行等原G0/G6/G8出口保留。

## 6. 复现与证据完整性

在项目根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/start_actor_rig_polish.ps1
```

入口使用独立`user://actor-rig-pilot-<pid>-<ticks>`，不读写正式玩家档。验证另选未使用的证据名：

```powershell
$env:CAMPUS_ACTOR_EVIDENCE = 'artifacts/verification/actor-rig-polish-20261114'
$env:CAMPUS_ACTOR_PILOT_OUT = 'res://artifacts/verification/actor-rig-polish-20261114/recheck-01'
python tools/verify_actor_rig_pilot.py recheck-01 -- --script res://tools/run_actor_rig_pilot.gd -- --polished --verify --capture
```

改前60文件hash和可信备份见[before.json](../../artifacts/verification/actor-rig-polish-20261114/before.json)及[before-complete.zip](../../artifacts/verification/actor-rig-polish-20261114/before-complete.zip)；GameShell在编辑前补入。最终[验证汇总](../../artifacts/verification/actor-rig-polish-20261114/verification-summary.json)、[改后hash](../../artifacts/verification/actor-rig-polish-20261114/after.json)与[交付检查](../../artifacts/verification/actor-rig-polish-20261114/delivery-audit.json)分别登记运行结果、当前版本及链接/资源检查。目录日期保留实施开始日，不把11月15日交付写成此前已完成。
