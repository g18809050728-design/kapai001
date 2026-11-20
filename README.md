# 《交大四年：DDL战争》设计与实施入口

2026-11-21：按用户要求清理局外HTML预览、评审页/模板及参考网页存档，并加入Git排除规则。后文HTML链接保留为历史记录，页面已删除；使用游戏或同批Markdown/JSON查看现有实现和验证结果。游戏素材、骨架和动作数据保留。后续不再生成或上传这些HTML，详见[实施计划](实施计划与验收基线.md)§0.20.38。

2026-11-20 饰品池更新（§0.20.37）：**原有 16 件 FY 已从游戏移除，仅保留 104 件 RX**（40 件通用＋四角色各 16 件）。普通「新的四年」、学年奖励、测试房间、**「图鉴 → 饰品」**及文本编辑器都使用新池。原有 RX 图片不变。继续旧四学年档时移除已装备和待领取的 FY，不重抽 RX，不重置冒险。[实机图鉴](artifacts/verification/relic-removal-20261120/review/screens/gallery-all-1280-100.png) · [旧档处理与验证](docs/plans/2026-11-20-relic-removal-design.md)。

历史首测（§0.20.35）：曾以 24 件 RX 验证触发规则并制作全部 104 张独立图标。`& .\tools\start_relic_pilot.ps1` 仍是单独存档的 24 件 RX 试点，不含 FY。[首测截图与记录](artifacts/verification/relic-pilot-20261120/review/README.md) · [全量接入与造型对照](docs/plans/2026-11-20-relic-roster-design.md)。

2026-11-15当前§0.20.25已完成四角色正式接入：林序原V5、许知微V8、沈见章V10、唐以宁V11默认用于选角/战斗、保存继续及测试房间；原仅样板限制在四人范围内已取代。见[正式战斗四人图](artifacts/verification/actor-integration-20261115/review/battle.jpg)、[选角四人图](artifacts/verification/actor-integration-20261115/review/setup.jpg)及[实现/结果](docs/plans/2026-11-15-actor-integration-design.md)。490项实机、22条真实命令对照、61窗口图/300连续帧通过；完整规则63.653秒、完整UI289.659秒和默认入口烟测均退出0/错误0。916保护文件、17份改前快照与10个真实存档文件hash核对通过；API新增0、累计38/200。原G0/G6/G8出口、最终美术签收与慢放手部换面感另记。

2026-11-15唐以宁动作已修正为V11（§0.20.24）：先看[出手前后](artifacts/verification/actor-motion-20261115/review/p04-action-before-after.jpg)，再打开[V8/V11连续动作与慢放](artifacts/verification/actor-motion-20261115/review/index.html)。肩袖保持连接、肩肘重新联动、减少双膝同时折弯，持板加入轻微缓冲；原形象和上下身比例保持。336项实机、5真实命令和53项浏览器检查通过，见[实际结果](docs/plans/2026-11-15-actor-motion-design.md)与[验证汇总](artifacts/verification/actor-motion-20261115/verification-summary.json)。[启动器](tools/start_actor_party.ps1)默认P04/V11；P03V10、P02V8、P01原V5及正式入口保持。API新增0，累计38/200。慢放手部换面仍有短暂切换感，最终动作观感待查看；以下按历史批次阅读。

2026-11-15沈见章V10整套重制已完成（§0.20.23，V9被用户否决）：先看[全身对照](artifacts/verification/actor-rebuild-20261115/review/p03-before-after.jpg)、[头颈近景](artifacts/verification/actor-rebuild-20261115/review/neck-before-after.jpg)，再打开[全身与连续动作评审](artifacts/verification/actor-rebuild-20261115/review/index.html)。新母图重建27骨/14部件/6网格/19运行纹理，[启动器](tools/start_actor_party.ps1)默认P03/V10；P02/P04 V8、P01原V5保持。339项实机、5真实命令对照与66浏览器检查通过；本轮API9张、累计38/200。见[结果与边界](docs/plans/2026-11-15-actor-rebuild-design.md)和[汇总](artifacts/verification/actor-rebuild-20261115/verification-summary.json)。形象待用户最终查看，慢放手部切换仍会短暂重影；以下V9及更早文字按历史批次阅读。

2026-11-15三人比例与颈部修正（§0.20.21）：先看[修正版三人合图](artifacts/verification/actor-proportions-20261115/review/lineup.jpg)，再打开[上一版/修正版全身与连续动作评审](artifacts/verification/actor-proportions-20261115/review/index.html)。P02/P03/P04髋到踝纵向缩短22%，上身与鞋保持自身尺度；沈见章重绘头颈，消除旧颈部叠线、领口缺口与重复下颌。独立[启动器](tools/start_actor_party.ps1)默认V8，`-Character P02/P03/P04`选人、`-Version V7`查看旧版。1004项实机检查、17条真实命令对照、63项浏览器检查通过，P01原V5保持；本轮API新增1张，累计28/200。见[实际结果与剩余边界](docs/plans/2026-11-15-actor-proportions-design.md)和[验证汇总](artifacts/verification/actor-proportions-20261115/verification-summary.json)。以下三人V7及更早结果按历史批次阅读，用户最终形象评价另记。

2026-11-15其余三位主角已完成：先看[许知微、沈见章、唐以宁完整人物合图](artifacts/verification/actor-party-20261115/review/lineup.jpg)，再打开[三人全身与连续动作评审](artifacts/verification/actor-party-20261115/review/index.html)，可切换角色、暂停和慢放；[独立试玩](tools/start_actor_party.ps1)支持`-Character P02`、`P03`或`P04`。三人均接入原生骨架、表情、持物跟随和战斗动作；实机、原V5兼容、规则/完整UI与浏览器检查通过。林序仍为用户选定原V5；API本批12张、累计27/200。制作、验证及剩余细节见[实际结果](docs/plans/2026-11-15-actor-party-design.md)，最终形象待用户查看。

2026-11-15人物版本选择：用户反馈“V5的版本更好一些”，当前代表样板采用原版V5，后续以它为基准。打开[V5全身与连续动作评审](artifacts/verification/actor-anatomy-20261115/review/index.html)或运行[V5独立试玩](tools/start_actor_anatomy.ps1)；[V6前后对照](artifacts/verification/actor-seams-20261115/review/index.html)保留作未选方案。选择依据及核对见[记录](artifacts/verification/actor-seams-20261115/user-selection-v5-01/report.json)，下列批次结果按历史阅读。

2026-11-15 人物形体修正（§0.20.18）：针对上下身不协调和画面左腿畸形，重画连续腰胯/双腿，按图内髋膝踝重新绑定，校正头身与上下身比例，并修复受击时的裤片残影。先看[完整人物前后对照](artifacts/verification/actor-anatomy-20261115/review/fullbody-comparison.jpg)，再打开[全身与连续动作评审](artifacts/verification/actor-anatomy-20261115/review/index.html)或运行[新版独立启动器](tools/start_actor_anatomy.ps1)。最终render-05为356项、24图/458帧、5条真实命令A/B一致；v1～v4兼容及完整规则通过，完整UI最终回归通过。API本轮成功3张、累计15/200；P01为27骨骼/14基础部件/6网格，N01沿用v4。[实际结果与下一步计划](docs/plans/2026-11-15-actor-anatomy-design.md)列明肩肘/袖片、持物透视和不同体型验证缺口。完整人物形体改善已实际看图，最终美术待用户查看；下列数字保留为各旧批次记录。

2026-11-15 第三轮人物精修（§0.20.17）：新增转身、伸笔出手、受击表情及纸怪合扇/折痕绘图，并修整出手遮挡、颈部重叠和切换叠影。打开[最新 v3/v4 动态对照](artifacts/verification/actor-rig-drawings-20261115/review/index.html)，或运行[独立启动器](tools/start_actor_rig_drawings.ps1)。340项定向检查、19图/455帧、5条真实命令A/B和v1/v2/v3兼容通过；规则/完整UI回归通过。API本轮成功6张、累计12/200，接入5张局部表、派生16件PNG。[实际结果与可行方案](docs/plans/2026-11-15-actor-drawings-design.md)列明剩余大转身、极限袖片及类型扩展缺口。默认入口、旧资源和真实玩家档保留，最终美术待查看。下列前批记录保留原批次含义。

2026-11-15沈见章体态修正版V9（§0.20.22）已实装：头部向肩上方回收、抬平下颌、重新连接颈根，6类动作结束回到新的中立姿态。先看[头颈前后近景](artifacts/verification/actor-posture-20261115/review/neck-before-after.jpg)及[完整人物与V8/V9连续动作评审](artifacts/verification/actor-posture-20261115/review/index.html)，页面默认沈见章。342项实机检查、5条真实命令对照及66项浏览器检查通过；7组下半身实渲像素无变化，P02/P04仍V8、P01仍原V5。[启动器](tools/start_actor_party.ps1)默认V9，用`-Character P03`查看本轮、`-Version V8`查看修改前。API新增1张、累计29/200；[实际结果与边界](docs/plans/2026-11-15-actor-posture-design.md)和[验证汇总](artifacts/verification/actor-posture-20261115/verification-summary.json)另存。最终形象待查看，以下V8及更早批次结果保留历史含义。

2026-11-15 第二轮人物精修（§0.20.16）：肩肘连续权重、手腕/笔记本拆分跟随、眨眼、纸扇弯曲及教室地面已实现。打开[上一版/本轮同步动画](artifacts/verification/actor-rig-refinement-20261115/review/index.html)，可单独放大人物或纸怪；[独立启动器](tools/start_actor_rig_refinement.ps1)保留原入口和隔离存档。287项、19图/456帧、旧v1/v2兼容与规则/完整UI通过；新增背景1张，累计6/200。实际改善、剩余转体/情绪绘图差距与后续步骤见[本轮结果和可行方案](docs/plans/2026-11-15-actor-refinement-design.md)。

2026-11-15 人物动作精修（§0.20.15）：针对僵硬感，参考官方动画师资料，完成P01/N01重心、脚部支点、分关节错峰、纸怪压缩回弹、独立循环及命中/离场衔接。打开[前后同步动画](artifacts/verification/actor-rig-polish-20261114/review/index.html)，可正常播放、暂停、拖动和慢放；运行[精修启动器](tools/start_actor_rig_polish.ps1)。259项检查、19图/459帧、旧样板兼容及规则/完整UI回归通过；结果、官方来源和剩余接缝/表情/地面差距见[精修记录与后续方案](docs/plans/2026-11-14-actor-motion-polish-design.md)。新增API图片0张、累计5/200，默认入口保留，最终人物美术待查看。

2026-11-14 菜单与饰品查看深化（§0.20.13、UIR-068）：菜单落实规则/记录/冒险信息、设置/保存/主页操作；饰品逐槽查看真实图片和完整效果，满槽领取前比较替换；规则、记录与专注图标统一。修复展开菜单的鼠标穿透与保存提示遮挡。见[实施与验证](docs/菜单与饰品查看优化_20261114.md)及[实机对照](artifacts/verification/menu-relic-feedback-20261114/review/index.html)。本批未修改人物，用户美术签收及整版出口保留。

2026-11-14人物与敌怪动作实践已完成：P01/N01原生二维骨骼接入真实战斗到奖励，226项定向检查、规则与完整UI回归通过；已用API 5/200张。看[离线对照与动画](artifacts/verification/actor-rig-pilot-20261114/review/index.html)、[实践结果与实施方案](docs/plans/2026-11-14-actor-rig-feasibility-plan.md)，运行[样板启动器](tools/start_actor_rig_pilot.ps1)。比例、接缝、动作表演和场景融合仍需精修；默认入口未启用试验，已否决资源不恢复，最终美术签收及全量G6/G8出口保留。

2026-11-14 最新地图整体构图纠正（根计划§0.20.12、UIR-019/063）：用户指出问题在图标和路径的组合，上一批材质不代表解决。本轮重画13类同源校园墨线符号，调整节点错落与间距，路径改为连续柔和曲线并在文字处留白，减少重复角标/短弧。完整UI、定向实渲、导入退出0/错误0，60张最终实渲与36组真实鼠标留证；见[本批记录](docs/地图整体构图修正_20261114.md)和[前后对照](artifacts/verification/map-composition-feedback-20261114/review/index.html)。人物、用户审美签收及整版出口继续保留。

2026-11-14 最新地图质感纠正（根计划§0.20.11、UIR-019/063）：原创纤维纸张/折痕/磨损边缘、墨印节点和虚线路径、侧方纸片预览已实施。地图页省略重复地图按钮，M切换本页概览；其他房间/战斗保留只读全图。完整UI、定向实渲和导入退出0/错误0，707项定向检查、60张最终PNG及36组Windows鼠标留证。见[本批记录](docs/地图质感与冗余入口修正_20261114.md)及[前后实渲对照](artifacts/verification/map-material-feedback-20261114/review/index.html)；人物、用户最终审美及整版G0/G6/G8原出口保留。

2026-11-14 最新地图/顶栏细化（根计划§0.20.10）：首次点击预选，再次点击同一已选可达节点即可进入，保留快速双击、确认及键盘，全图浮层仍只读。右侧按二代地图/牌组/设置三入口重整，次要操作进入分组菜单，支持滚动/快捷键/焦点恢复，演出设置原地更新。两尺寸三档字号与真实鼠标验证见[本批记录](docs/地图再次点击与顶栏深化_20261114.md)，人物继续暂停。

2026-11-14 当前创建与操作修正（[根计划§0.20.9](实施计划与验收基线.md)）：固定创建配置区及独立种子弹层，三档难度实际生效，同源顶栏图标，待选返回主页保留选择，校园服务情境图，一次确认及完整地图浮层。新局map_version=3消除等价分路，旧v1/v2继续原算法。完整规则/四学年、UI和导入退出0/错误0；1017项定向检查、44张实渲和16组Windows鼠标通过，见[实现与证据](docs/创建地图与操作体验修正_20261114.md)。人物继续暂停，类型费用图案与原位双击保留，难度数值仍为试玩参数。

2026-11-14 当前美观/实用优化（[根计划§0.20.8](实施计划与验收基线.md)）：地图固定节点摘要与独立路线滚动，奖励/商品名称底托、勾选/焦点与价签，主要确认分层，战斗关键数字更清楚。完整UI、规则/四学年回归退出0/错误0，新增215项可用性检查及Windows鼠标16组通过；两尺寸三档字号、96张实渲及改前/后对比见[本批记录](docs/UI美观与实用性优化_20261114.md)。原类型费用图案、原位双击与人物暂停保持，整版出口未扩大。

2026-11-14 最新反馈修复（[根计划§0.20.7](实施计划与验收基线.md)）：地图单击原地预选，连续双击原鼠标位置直接进入可达节点且只提交一次；恢复剑、盾、齿轮、校园建筑、闪电和破损纸页类型费用角标，已写入底层规则。完整UI/规则/四学年回归退出0/错误0；Windows原生鼠标16组通过，两尺寸/150%字号实渲已查看，见[修复与验证记录](docs/地图双击与卡牌类型修复_20261114.md)。人物继续暂停，二代整体UI目标与整版阶段出口保持。

2026-11-14 上一批整体重做（§0.20.6）：用户要求 UI 做成与《杀戮尖塔2》一样，已写入 AGENTS.md、agent.md 和[根计划§0.20.6](实施计划与验收基线.md)。现已按二代构图重做窄顶栏、全屏战斗、扇形手牌与独立费用徽章、暖纸地图、菜单/选角、奖励、商店、事件/休息和公共弹层；人物资源继续暂停。设计、真实画面、回归结果与剩余差异见[本轮实施记录](docs/杀戮尖塔2_UI重做实施记录_20261114.md)，可直接打开[双尺寸实机对照页](output/sts2-ui-rebuild-20261114/preview.html)。本批完整UI/规则/四学年回归退出0/错误0，74图、229项网页检查和20项一致性检查留证；人物及正式插画差异未签收。旧局部特效证据保留为历史，不能替代整体 UI 验收。

以下同日及更早记录保留各自批次范围；当前创建/操作与分路以§0.20.9为准，原类型角标及原位双击仍按§0.20.7保留。

2026-11-14 文档提交包：已整理[冻结需求、验收用例、概要/详细设计与修改说明](docs/提交文档_20261114/README.md)。DOC-20261114-1只冻结本次文档，整版G0/G6/G8状态仍依原计划。

2026-11-14：用户暂停人物UI，校园8项及之前所有人物候选均不接受，停止资源搜索/生成/接入。按[根计划§0.20.5](实施计划与验收基线.md)继续[ui-plan](ui-plan/README.md)其余任务，已完成原生非人物特效原型接入：压力/恢复、资源获得/支付、状态和阶段分别表达，吸收/破防与实际损失分离。完整规则/四年及最终UI回归通过，双尺寸18组160帧采样留证，见[实施记录](docs/非人物特效实施记录_20261114.md)。紧凑任务浮字重叠及最终观感待继续核对；旧12张纹理仍未选用，人物、全量G6人工/许可及G8出口保留。

上一批已完成 4 主角、7 伙伴和 60 任务共 71 个实体、88 个任务阶段、57 个遭遇及资源映射盘点；一张 P01 新造型概念已生成，AI 观察结论为需返工、未选用。该批范围为根计划 §0.20.1；§0.20 的“仅文字、不生图”适用于 2026-11-13 文档批次。单张概念不计为分层资源。

2026-11-13 已完成一轮可玩表现原型：同源卡面、向上路线、场景房间、独立战斗实体与真实资源反馈。按当时需求，原费用圆球直接换成攻击剑、防御盾、功能齿轮、场地校园建筑和能力闪电，数字继续表示专注费用。卡牌/规则/RNG对照、真实命令双闭环和原型实渲见[实现记录](docs/UI表现重制实现记录_20261113.md)。用户随后明确新的整体目标：尽量贴近《杀戮尖塔2》的整体观感，再作校园题材转换，并重做人物与敌怪的身体部件多层贴图动画。该批完成文字需求 UIR-049～060 登记，当前资源准备按上方 G6 记录推进；旧原型不能当作新方向的完成结果。目标与需求从[整体表现重制需求 v3](动作或者图片描述/整体表现重制需求_20261113.md)开始。

2026-11-13：已按[实施计划](docs/plans/2026-11-13-adaptive-annual-maps.md)实现逐年随机拓扑、长分支、经历有限影响、冻结存档、真实路线预告及毕业去向差异。[实现与实测](docs/逐年随机地图实施记录_20261113.md)记录400图约束、52站受控路线、规则/UI与144张实渲；[5号素材接入规格](动作或者图片描述/逐年随机地图需求_20261113.md)可直接交接，后续新图登记到textures即可使用。真人平衡与最终美术仍待后续验收。

2026-11-06 追加：设置页明确已选、当前生效与尚未应用；最后一击等待卡牌/扣血动作完成后再切页，速度参数保持。完整 UI 回归与双尺寸 40 张实渲通过，见[本轮记录](docs/设置状态与战斗转场实施记录_20261106.md)。

2026-11-06：战斗改为实际手牌逐张抽出、落位显示，弃牌从原卡位直接进入目标堆；按用户实测把特效基础速度统一提高 4 倍，页面倍速继续叠加。完整规则/四年/UI、导入和两尺寸 30 张实渲通过，见[B2 记录](docs/战斗动画时序实施记录_20261106.md)。

更新：2026-11-04。创建游戏仅使用 `campus_four_year`，已接入四角色 v3.1 卡牌、**四张连续学年地图**、校园服务、饰品与学年大奖励。以学年为单位，不分学期；选角显示被动效果，具体核查与缺口见[入口记录](docs/plans/2026-11-04-four-year-setup-design.md)。正式平衡、美术音乐与 G8 发布验收仍待完成；旧 `campus_v3` / `campus_mvp` 仅保留内部历史兼容。

2026-11-01：按用户要求把[精英设计草稿一](docs/archive/2026-11-04/精英敌人设计草稿.md)、[草稿二](docs/archive/2026-11-04/精英敌人设计草稿2.md)的 12 个遭遇（E01–E07、Q0A–Q0E）落进 v1 数据与战斗引擎，并补充每单位压力缩放、任务召唤/转换/自爆、意图停留及可选任务。[小怪设计草稿](docs/archive/2026-11-04/小怪设计草稿_历史候选_20261030.md)的普通敌人当时未实现。范围、语义解读和未完成项见[精英敌人实现记录](docs/精英敌人实现记录_20261101.md)。Godot `4.7.2.stable` 无头套件、UI 套件与启动冒烟当时实跑通过；平衡与人工视觉未验证。

2026-11-02：第一学期精英池定为 `Q01`、`E01`、`E02`、`E03`、`Q0B`、`Q0C`（`Q0B`/`Q0C` 提前到第 1 学期）。用机器人对起始牌组做了难度下限试玩：`Q0B`/`Q0C` 两人物 100% 胜偏易，`E02`/`E03` 为 50–100%，`E01` 对 P04 仅 4%；`Q0A`/`Q0D` 近似必败，已明确排除出第一学期。数据与复现见实现记录 §7。

2026-11-03：现有 v1 程序已加入 A25–A48 共 24 件通用饰品；规则、奖励/商店与存档集成、UI 套件及启动冒烟当时已在 Godot 4.7.2 实跑通过，范围与留存命令见[饰品实现记录](docs/饰品实现记录_20261103.md)。部分旧验证产物已不在当前工作区，不把历史路径作为现存证据链接。怪物和 A49–A52 留待后续。当前生产包没有能力牌，因此 A27 在生产局无法触发、A46 的能力分支不可达；隔离 fixture 测试不能证明生产可用。人工视觉、平衡与完整用户路径仍未验证，此项不代表 v3.1 已实现或通过新版阶段。

> **Git 迁移说明（2026-11-21）**：当前检出保留 Godot 源工程、选定美术、兼容及试点资源、测试、工具和设计/溯源文档。AI 母图与制作过程、外部参考媒体、G6 离线母图/候选、截图和原始验收输出仅在本地档案保留（已淘汰的文件除外）。文中的历史审阅链接有些指向这些本地目录；重建美术或查看原始验收时需另行带上对应档案。它们不参与正常启动，也不随 Git 同步真实玩家存档。

## 本轮交付与阅读顺序

| 阅读入口 | 内容与状态 |
|---|---|
| [整体表现重制需求 v7](动作或者图片描述/整体表现重制需求_20261113.md) / [ui-plan阅读入口](ui-plan/README.md) | 唯一维护UIR-001～067；当前创建/操作追加见§9.2，人物仍暂停。旧01～05方案先按历史适用范围阅读 |
| [上一轮表现原型实现与证据](docs/UI表现重制实现记录_20261113.md) | UIR-001～048对应的卡框、事件、地图/房间及战斗实体原型，含完整UI/规则回归、376有效面检查、60正常命令双闭环；不代表新方向和正式分层动画已验收 |
| [测试房间功能设计](docs/测试房间功能设计.md) | 统一文档（设计定稿 v1.0）：开始界面直接进入、随时更改一切的完整沙盒，含冻结接口/DTO、容量与单步、覆盖层 schema、G7 级界面、检查点/重放与 TR-AC；首版战斗沙盒已实施，剩余能力见实现记录 |
| [测试房间实现记录](docs/测试房间实现记录_20261111.md) | 战斗沙盒：隔离上下文、编辑事务/检查点、独立文件、测试主页、战斗 HUD 与分页草稿编辑器；自由模式默认解除槽位/唯一等限制，可精确调时间/阶段、编辑怪物意图、使用章节区、按 ID 调用任意内容并用 JSON 创建自定义定义；规则与 UI 回归退出 0，21 张实渲；未完成自定义角色开局、125% 实渲等缺口 |
| [编辑器 UI 设计](docs/plans/2026-11-12-test-editor-ui-design.md) | 纸墨语义 token、对比度、布局、组件状态、键盘与无障碍规范；v1.1 增加自由调用、精确时间、怪物意图与自定义定义；含 21 张实渲对照 |
| [战斗反馈与地图分岔](docs/战斗地图反馈实施记录_20261105.md) | 无专注点击不进介绍；抽牌/弃牌/消耗及结算反馈；新局地图按当前位置分岔，旧档保留冻结路线；完整回归与两尺寸 18 张实渲通过 |
| [阶段执行状态总览](docs/阶段执行状态总览.md) | G0–G8 当前实现、真实证据与剩余出口 |
| [执行记录核对与旧版清理](docs/执行记录核对与旧版清理_20261104.md) | 本次修正、7 份删除清单、原文字节备份及验证 |
| [本轮实现与完成状态](docs/四学年地图与视听实现记录_20261104.md) | 完成清单、真实测试证据、限制与下一步 |
| [四大地图方案](docs/四大地图复杂化设计方案.md) | 地图维护源：新局逐年随机图、12/12/14/14层，共52层；20/28/36/40仅为旧固定图 |
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

2026-10-30 协作合并保留了其他人的[饰品与怪物候选](docs/饰品与怪物.md)和[小怪草稿历史候选](docs/archive/2026-11-04/小怪设计草稿_历史候选_20261030.md)。两份原方案均按来源版本归档，不进入当前 v3.1 范围；冲突以本轮设计为准，详情见[合并说明](artifacts/redesign-20261030/git-integration.md)。

## 维护源与阶段证据

| 入口 | 使用范围 |
|---|---|
| [实施计划与验收基线](实施计划与验收基线.md)、[工作约定](agent.md) | 阶段、范围调整、退出条件和证据要求 |
| [项目计划](docs/交大四年_DDL战争_项目计划书.md)、[规则书](docs/交大四年_DDL战争_游戏规则书.md)、[统一设计](docs/交大四年_DDL战争_统一设计文档.md)、[设计思路](docs/交大四年_DDL战争_完整设计思路.md) | 当前v2上游，已直接重写；旧来源原文/hash可从 Git 历史查阅 |
| [G0登记](docs/baselines/g0.json)、[需求追踪](docs/G0需求追踪.md)、[G0记录](docs/G0基线执行记录.md) | v1 精确生产范围、裁决和历史核验 |
| [精英敌人实现记录](docs/精英敌人实现记录_20261101.md) | 2026-11-01/02 精英遭遇的内容/引擎扩充、首期名单与试玩、未完成项与验证状态 |
| [饰品实现记录](docs/饰品实现记录_20261103.md) | v1 A25–A48 的范围、触发规则、实现与实测状态；A49–A52 及怪物仍待后续 |
| [架构](docs/初步架构设计.md)、[接口](docs/接口文档.md)、[存储设计](docs/数据库与实体关系设计.md) | 模块边界、公共 API、稳定存档与恢复 |
| [内容契约](docs/内容层契约.md)、[战斗契约](docs/战斗模块契约.md)、[局流程契约](docs/局流程契约.md)、[界面契约](docs/界面层契约.md) | 模块与只读视图边界；UI表现新目标见根计划 §0.20 和 UIR-049～060 |
| [玩家术语说明](docs/卡牌名词与Buff效果说明.md) | v2名词、人物资源、合作、场景与考试说明 |
| [G1](docs/G1工程骨架执行记录.md)、[G2](docs/G2内容与基础状态执行记录.md)、[G3](docs/G3战斗规则执行记录.md)、[G4](docs/G4局流程执行记录.md)、[G5](docs/G5存档恢复执行记录.md) | 已执行的工程、内容、战斗、局流程和存档验收 |
| [G6制作包](assets/g6/README.md)、[G6记录](docs/G6资源准备执行记录.md)、[G7记录](docs/G7界面执行记录.md) | 现有 46 个素材、合并后的制作规范和批次、实际验证及边界 |
| [UI需求台账](动作或者图片描述/需求台账.md)、[G7设计](动作或者图片描述/G7界面与交互设计.md)、[新版表现文字需求](动作或者图片描述/整体表现重制需求_20261113.md) | 历史条目、当前行为回归及最新整体视觉/分层资产需求分别登记 |

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

从已更新的 GitHub `main` 迁移到 Linux 时，可用 `git clone --depth 1 --single-branch --branch main <仓库地址>` 只拉取最新源码。先安装项目指定的 Godot 4.7.2；在仓库根目录执行以下无头冒烟（有桌面的 Linux 可用 `godot --path .` 启动游戏）：

```sh
godot --headless --editor --path . --quit
godot --headless --path . --quit-after 2
```

服务器的 `.godot/` 会自行重建；旧玩家进度和文本覆盖如需迁移，应单独备份/复制 Godot `user://`，不要上传到仓库。

### 浏览器版

安装 Godot 4.7.2 对应的官方导出模板。Web 预设使用单线程 GL Compatibility，需要支持 WebGL 2 的浏览器。使用同一访问地址继续游戏，进度保存在该地址的浏览器站点数据中。Godot 加载器接受公网 HTTPS 和本机回环地址。

```sh
godot --headless --path . --import
sh tools/export_web.sh dist/web
```

将 `dist/web` 中的构建产物复制到 `/var/www/kapai001/releases/<版本>`，并将 `/var/www/kapai001/current` 链接到该版本。将 [Nginx 配置](tools/kapai001.nginx.conf) 安装到 `/etc/nginx/conf.d/`，执行 `nginx -t` 与 `systemctl enable --now nginx`。Nginx 已运行时执行 `systemctl reload nginx`。本机试玩地址为 `http://127.0.0.1:18080/`。公网部署需要在外网可达的 HTTPS 站点提供同一构建目录。

随游戏包发布的简体中文字体采用 SIL OFL 1.1。字体来源见 [Noto Sans CJK 2.004](https://github.com/notofonts/noto-cjk/tree/Sans2.004/Sans) 和 [Noto Serif CJK 2.003](https://github.com/notofonts/noto-cjk/tree/Serif2.003/Serif)。

手机上双指轻点两次或点「全屏」可进入全屏，浏览器支持时会锁定横屏。长按手牌可阅读完整效果，轻触可选牌或出牌。输入搜索关键词后，点输入条旁的「完成」收起键盘。Safari 无网页全屏时，可通过共享菜单添加到主屏幕，从图标进入独立窗口。

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


