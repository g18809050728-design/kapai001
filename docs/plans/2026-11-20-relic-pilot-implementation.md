# 2026-11-20 · RX 饰品首测实施记录

> **后续决策（§0.20.37）**：旧首测的 FY 已移除，当前试点仅含 24 件 RX，正式冒险含 104 件 RX。以下记录保留历史语义，见[现行版本](2026-11-20-relic-removal-design.md)。

按[原设计 §5](2026-11-20-relic-pool-design(1).md)及根计划 §0.20.35 交付。**7＋17 件共 24 件已可试玩；104 件都有独立图标及条目；其余 80 件未实现效果、不参与掉落。** 不把本批试点变成正式掉落池，也不把技术验证当作最终美术或平衡签收。

## 试玩

从仓库根目录启动（也可用 `-GodotPath` 指定本机 Godot）：

```powershell
& .\tools\start_relic_pilot.ps1
```

- **测试房间**：先选角色与遭遇，再在三个饰品栏选通用或本角色的首测件，然后进入战斗。触发提示使用实际结算事件，显示来源、实际值和剩余次数。
- **新游戏**：试点四学年仍保留三个装备槽。完成大一／大二第 3、9 层，大三／大四第 4、11 层的节点后进入饰品选择。这里改的是**试点奖励发放时点**，未重做地图生成或节点布局；正式自适应地图的大三／大四奖励仍沿用第 4、10 层。
- 启动器只追加 `-- --relic-pilot`。试点使用 `campus_four_year_relic_pilot.v1`，存档、配置、个人记录、测试快照、文本覆盖均在 `user://relic_pilot/` 下。常规启动不启用 RX 规则定义或候选，不读写试点档。

## 规则与界面

| 分组 | 第一批（7 件） | 第二批（17 件） |
|---|---|---|
| 通用 | `RX-C01`、`RX-C02`、`RX-C09` | `RX-C05`、`RX-C17`、`RX-C23`、`RX-C26`、`RX-C28` |
| 林序 | `RX-P01-01` | `RX-P01-05`、`RX-P01-09`、`RX-P01-15` |
| 许知微 | `RX-P02-01` | `RX-P02-02`、`RX-P02-07`、`RX-P02-15` |
| 沈见章 | `RX-P03-01` | `RX-P03-05`、`RX-P03-09`、`RX-P03-16` |
| 唐以宁 | `RX-P04-01` | `RX-P04-06`、`RX-P04-08`、`RX-P04-11` |

- 候选顺序为通用、当前角色专属、混合；混合包含本学年原 FY 池。按学年权重先抽稀有度组，再在按 ID 排序的合法组内抽定义。候选过滤错角色、同次重复及金色 RX，最多一件金色旧件。只消耗 `reward` RNG，生成时冻结；查看、取消和保存继续不重抽。满槽可替换；重复折算 +25，新件满槽折算 +30，放弃饰品 +20。
- 首测件只从既定奖励来源投放；不加商店、开局、精英额外或 Boss 专属掉落，也不改学年大奖励／毕业条件。永久配置沿用三槽，不开放随时换装。
- `RX-C26` 有效普通休息每局最多两次；`RX-C28` 主动放弃有效独立卡牌奖励每局最多三次。已用次数由试点档 `campaign.rx_uses` 保存，换下、重戴和读档不会刷新。确认页按实际状态显示额外恢复／金钱。
- `RX-P02-02` 只在首次发表、起算 C 在 50–79 时给原卡的非对称主目标首段 +8；论文 C、满分判定与副段不变。主目标、章节窗口、回收确认、状态快照、伙伴主动离场／考试替代等按各自的规则调用点判断，不把所有饰品当成通用出牌触发。
- 奖励、替换对比、已佩戴详情与战斗 HUD 共用同一 ID 的图标；品质边框由原界面绘制。长说明支持滚动，换位与放弃仍有清晰确认。无真实触发事件不闪烁。

## 图标与源文件

使用本机配置的 `jiji.cc`（清单服务 `api-slb.jiji.cc`）与 `gpt-image-2.5-sunburst`，`medium`。成功返回 **13 张八格原图＋3 张局部补绘图＝16 张**，项目记录累计 **159/200** 张。无须再调用 API 即可使用当前成品。

- [图标总览和实机截图](../../artifacts/verification/relic-pilot-20261120/review/README.md)；[逐件外观描述 JSON](2026-11-20-relic-visual-descriptions.json)（旧 FY 附录仅作文字参考；没有重绘）。
- [104 件数据目录](../../data/four_year/relic_pilot/catalog.json)保存原设计的 ID、效果和外观；[24 件运行时定义](../../data/four_year/relic_pilot/definitions.json)只有首测内容，未追加到正式 `relics.json`。
- [引擎使用的单件图及溯源清单](../../assets/art/relic-pilot/asset-manifest.json)：104 张 256×256 无损 WebP。保留每个格位、原图哈希与成品哈希；[API 原图、提示和作业记录](../../output/imagegen/relic-pilot-20261120/)已留存。
- [目录及提示生成器](../../tools/build_relic_pilot_catalog.py)从未改动的设计表提取；[裁图脚本](../../tools/process_relic_pilot_art.py)可由已保存原图重建，无需发起请求。

## 验证结果

| 项目 | 实际结果 |
|---|---|
| [饰品专项](../../artifacts/verification/relic-pilot-20261120/focused-matrix-final.log) | 3,132 项、0 失败；24 件都有真实规则事件。包含 60 场引擎对局：四角色 × 五类遭遇 × 0／1／3 件，同 seed `415`，1085 条战斗命令；54 胜、6 场 DDL 到期，见[矩阵数据](../../artifacts/verification/relic-pilot-20261120/battle-matrix.json)。对局未脚本送胜，不能由单 seed 推出整体平衡。另以**脚本战斗结算**串行覆盖四学年 8 次饰品奖励＋4 次大奖励，不是自然通关。 |
| [实机 UI](../../artifacts/verification/relic-pilot-20261120/pilot-ui-render-final.log) | 203 项、0 失败，29 张截图。实际主场景、测试房间、战斗 HUD、放弃卡牌确认；奖励、替换和详情验证 1280×800／960×640 及 100／125／150% 字号。 |
| [默认规则回归](../../artifacts/verification/relic-pilot-20261120/rules-signoff.log)／[默认 UI 回归](../../artifacts/verification/relic-pilot-20261120/ui-signoff.log) | G1–G5 规则退出 0（65.437 秒）；G7 UI 退出 0（322.842 秒，无引擎报错）。规则退出时有 73 个 ObjectDB 实例、14 个资源未释放；在单独的[改前基线](../../artifacts/verification/relic-pilot-20261120/baseline-rules.log)同样复现，不据此声称规则日志无错误。 |
| 导入与启动 | 默认／试点无头烟测均退出 0，见[默认启动](../../artifacts/verification/relic-pilot-20261120/final-smoke-default.log)／[试点启动](../../artifacts/verification/relic-pilot-20261120/final-smoke-pilot.log)。资源导入退出 0；41 条 UID 重复警告均指向旧批次证据截图，不涉及新增饰品图。 |
| [图标审计](../../artifacts/verification/relic-pilot-20261120/art-audit.json)与保护校验 | 104 张能解码、尺寸符合、无重复，四张最终总览已打开核对。仓库快照 2,533 项中 2,509 项字节不变，24 项是本批登记的源码变更；6 份真实玩家文件字节不变。正式内容摘要不变。 |

完整数字、用例边界、文件校验和日志路径见[验证汇总 JSON](../../artifacts/verification/relic-pilot-20261120/verification-summary.json)。定向规则使用 `res://tests/run_relic_pilot_tests.gd`；截图工具为 `res://tools/capture_relic_pilot.gd`（需 `-- --relic-pilot`，并将 `APPDATA`／`LOCALAPPDATA` 隔离在证据目录的 `isolation-*` 子目录下）。

仍待验收：用户对图标的最终取舍、多种子／自然四学年平衡与选择率、原整版 G0–G8 出口。其余 80 件及包括金色取舍在内的规则扩展不在本次启用范围内。
