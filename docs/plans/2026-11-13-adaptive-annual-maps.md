# 逐学年随机地图实施计划

日期：2026-11-13。状态：计划已执行，代码、契约、5号交接及本轮自动验证已完成；实际结果与剩余整版出口见[实施记录](../逐年随机地图实施记录_20261113.md)。

**目标**：种子决定初始地图，长分支提供不同大学经历；每学年开始时生成并冻结当年地图，上一学年经历有限影响下一学年的内容机会；支持可读路线、三层分岔预告、四学年机制与毕业去向差异。

**架构**：保留 CampaignMap 的两套固定地图作为旧档基线；新增 AnnualMapGenerator 纯生成器和 CampaignProgression 年度协调器。新版 campaign.version=2 保存主种子、生成版本、年度记录与经历摘要，运行节点仍由 RunCodec 编码。GameSession 继续作为唯一写入口。

**技术**：Godot 4.7.2 / GDScript，既有四学年内容包、RandomSource、SnapshotCodec、隔离无头及真实窗口验证。先规则和存档，再复用已有资源实施地图界面；不生产新图片。

## 1. 本轮裁决与边界

- T-01 已由用户裁决为随机拓扑；由本轮完成工程实现。四张图对应四学年，路线长度仍为 12/12/14/14，共52站，8次饰品/4次大奖励不变；取消新局候选节点必须为20/28/36/40及124总数的限制。
- 开局只生成大一；学年大奖励处理后冻结刚完成学年的经历；大二先确认方向、大四先确认去向，再生成该年地图。大三在跨年时直接生成。未来学年不预生成也不展示假地图。
- 同主种子、生成器/内容版本、学年和相同经历/明确选择得到相同年度地图；运行 run_id 不参与随机生成。生成使用从主种子、学年和规范化 profile 派生的独立 RandomSource，不受战斗/奖励/事件抽取或地图浏览影响。已生成地图保存、读档不重抽。
- 采用2条持续主路线与可选长期支线，分岔后至少3个独立节点再允许合流；起点/Boss外不设全图必经单节点。后继1–2个，边仅跨下一层，全候选可达且能到Boss，无精英/竞赛完整通路。
- 每条完整路线保证至少1个商店及2个休息机会；不允许连续精英、开局精英。服务与风险预算按学年统一，大一各种子采用相同预算约束；数值平衡须另有自然战斗实测，不能由结构检查代替。
- 商店、休息、服务和风险的中间层位也随种子变化，两条主路线分别分配；大二后半程保留可改向服务。大四每条路线至少两次ST毕设机会，替换原共同预算中的一场普通战斗，保障所有去向均有达到毕设2的机会；是否使用由玩家决定，其他风险预算不增。
- 经历只影响内容机会，不动态提高敌人数值；研究/竞赛/实习/社群计数只取已完成节点及实际使用服务，采用上限，保留其他倾向路线。选择方向和毕业去向权重高于经历；毕设仍为共同毕业要求。
- 四种去向至少体现在沿途节点、服务与最终挑战区别，优先组合既有战斗效果。旧定义/旧图作为旧档语义保留；若新增生产内容引起hash变化，只提供严格核对的显式兼容路径，不忽略内容或校验和。
- 本轮不生图、不修改玩家实际存档。5号后续按独立素材需求生产及接入；本轮G7复用已有纹理/主题和原生图形。整版G0/G6人工签收/G8自然通关、性能及打包出口不豁免。

## 2. 模块与接口

用户实测后的地图密度和外观改进由[追加计划](2026-11-13-map-density-polish.md)覆盖，新增FY-MAP-007：三个入口、中段3–5节点且至少半数4–5节点；算法版本1严格保留，新局算法2。下述首轮实现清单与证据保留其原版本适用范围。

| 模块 | 职责与接口 |
|---|---|
| `src/run/annual_map_generator.gd` | `generate(year:int, seed:String, profile:Dictionary={}) -> Dictionary`；返回 version/year/title/layers/relic_layers/seed/profile/nodes。节点固定字段为 key/year/layer/kind/subtype/title/next/column；next使用年内key，column为0–6整数。`validate(map:Dictionary) -> Array[String]` 检查拓扑/路线预算/合流；不依赖可写RunState。 |
| `src/run/campaign_progression.gd` | `enabled(run)` 区分新旧；`initialize(run,seed)`；`ensure_year(run)->GameResult` 幂等生成；`metadata(run,id)`/`year_info(run,year)` 返回已冻结记录，旧版退回CampaignMap；`complete_year(run)` 冻结经历；`validate_campaign(data,issues)`及`validate(run,issues)`严格验证schema、生成记录、已发布节点一致性。 |
| `src/run/campaign_service.gd` | 允许version1/2，沿既有grand/direction/destination命令在确认后生成；节点触发、服务和学年奖励统一从年度元数据读取。 |
| `src/run/run_service.gd` | 新局初始化大一；只读view返回当年层数、经历影响说明、节点元数据与三层预告。 |
| `src/run/route_forecast.gd` | 从冻结图计算选定节点及后3层的可达节点、必经风险和服务数量范围；只读，不调用RNG。 |
| `src/ui/route_canvas.gd` / `experience_page.gd` | 使用稳定column排布；节点短名/类型/状态；选中路线与三层可达高亮；全图概览和当前位置定位；保留不可达节点的查看能力，进入仍门控。 |

年度记录必须严格区分生成元数据和访问context。不得把待访问节点的元数据塞进访问context，旧版pending context为空的校验继续有效。

## 3. 执行清单

### A：基线、计划、协议（G0子项）

- [x] 根计划新增本轮范围/顺序例外；同步四图、局流程、界面和存档契约、需求台账；保留旧图说明。
- [x] 保存开工工作区观察、RED阶段输入hash及最终git状态；核对引擎、测试入口和上游来源，建立FY-MAP-001～006追踪。未补造完整开工git快照，证据限制见实施记录。

### B：生成器与约束（G1–G4子项）

- [x] 先建立生成器测试：同种子重放、不同种子变化、至少3节点才合流、可达/无死路/无精英路线、恢复/商店预算、逐层/出度。
- [x] 实现有约束的长分支生成、年度节点内容和轻量profile偏向；每年都有其他方向可选；中间层位也随种子变化。
- [x] 批量100种子×4年通过；保存拓扑签名、计数、失败输入及原始输出。失败地图拒绝发布，无固定单图回退。

### C：逐年生成与存档（G2/G4/G5子项）

- [x] 实现version2 campaign记录、年度摘要、初始化/幂等生成；旧version1固定图继续校验和读档。
- [x] 跨年按奖励→经历摘要→方向/去向→生成顺序执行；拒绝/重复确认不改图或随机状态。
- [x] 验证未来图未生成、同输入复现、不同实际经历可影响下一年、读档后当前图与未来生成一致；畸形/混合/篡改记录拒绝。
- [x] 受控路线完整走52站、8次饰品/4次大奖励；记录受控战斗结果注入边界，不冒称自然通关。

### D：学年和去向（G3/G4子项）

- [x] 大一探索、大二方向、大三履历、大四毕设全部使用动态元数据；新版研究节点改用类型识别；大四每条路两次ST机会。
- [x] 四去向映射沿途不同名称和内容机会；最终挑战采用独立配置并验证真实BattleEngine/BattleCodec；旧图保留原终局定义。

### E：文字需求与地图界面（G6核对已用资源后G7）

- [x] FY-MAP-004/005文字登记与5号资源交接表；已预留背景/节点/去向textures资源槽，复用已有素材，无付费请求。
- [x] 三层真实路线预告，可能/必经及数量范围区分，未知后继降级；选中/高亮/取消不改变领域/RNG/revision。
- [x] 纵向滚动与稳定横向路线；短节点、图例、当前/可进/已过/不可达状态；全图概览和回到当前位置。
- [x] 两尺寸1280×800/960×600、字号100/125/150，144张实渲；长名、未生成学年、方向选择前、鼠标/键盘及缺图退路检查通过。

### F：回归、审查、交付

- [x] 新定向suite、四学年、完整规则和UI回归实际运行；历史fixture与新行为测试分离，最终退出0、引擎错误0。
- [x] 生成器/UI分别独立检查；主线审查存档、确定性、预告真实性及只读边界，修复后重跑受影响检查。
- [x] 命令、环境/引擎、输入hash、退出码、原始日志、种子和截图保存至`artifacts/verification/adaptive-maps-20261113/`，计划/实施记录已同步。

## 4. 验证命令

使用独立APPDATA/LOCALAPPDATA；引擎为`D:\chrome\godot\Godot_v4.7.2-stable_win64_console.exe`。本轮验证脚本`tools/verify_adaptive_maps.py`接受suite路径/实渲参数并保存证据。建议顺序：

```powershell
python tools/verify_adaptive_maps.py import
python tools/verify_adaptive_maps.py generator res://tests/run_annual_map_generator_tests.gd
python tools/verify_adaptive_maps.py progression res://tests/run_adaptive_map_tests.gd
python tools/verify_adaptive_maps.py regression res://tests/run_tests.gd res://tests/run_four_year_tests.gd res://tests/run_ui_tests.gd
python tools/verify_adaptive_maps.py visual --visual res://tools/capture_adaptive_maps.gd
```

实现计划已获用户直接执行授权，不新增重复确认。分工为主代理处理基线、状态/存档与跨年接入；独立子代理在明确接口下处理纯生成器/定向测试及只读预告/地图界面，最后统一审查。
