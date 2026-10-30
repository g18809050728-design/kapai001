# 2026-10-30 四角色与卡池设计交付

状态：设计文档及评审数据，不是运行内容包；未进行游戏行为或平衡实测。

| 文件 | 用途 |
|---|---|
| [校园角色与专属卡池_v3.xlsx](校园角色与专属卡池_v3.xlsx) | 15张工作表，172永久+2衍生，完整升级/考试面/章节与分组导读，另有六负面及功能覆盖 |
| [毒师与通用功能修订](../../docs/沈见章毒师与全角色通用功能修订_20261030.md) | v3.1六负面、三路线、全角色基础功能及本轮改动 |
| [campus-cards-v3.json](campus-cards-v3.json) | 逐牌维护快照；不读取/写入data，不是未来schema已冻结的证明 |
| [catalog_v3.py](catalog_v3.py) | 手工设计数据定义与数量约束，执行后更新JSON |
| [build_delivery.py](build_delivery.py) | 同一JSON生成卡表和Excel；分组导读/角色概要在本文件维护 |
| [verify_delivery.py](verify_delivery.py) | 数量、ID、完整字段、Excel逐字段回读、导读、相对链接及文件保护核查 |
| [validation.json](validation.json)、[validation.md](validation.md) | 实际核查的机器记录/可读报告；含命令、时间、环境、退出码及边界 |
| [协作合并说明](git-integration.md)、[来源与归档记录](git-integration.json) | 远程候选保留方式、冲突取舍、来源提交/原文hash与可逆链接调整 |
| [before-v3.zip](before-v3.zip)、[baseline.json](baseline.json) | 修改前文档/旧校园Excel字节及SHA256；baseline用于识别本次改删 |
| [本轮改前ZIP](debuff-revision/before-v3.1.zip)、[本轮SHA256](debuff-revision/before-v3.1.json) | v3到v3.1改前56文件备份，不覆盖更早before-v3 |
| [逐牌差异](debuff-revision/card-changes.json)、[参考摘录](debuff-revision/reference-cards.json) | 对照本轮备份的45张修改、4张新增，以及9张参考卡的中英文原记录与来源hash |
| [protected-before.json](protected-before.json) | 修改前运行文件/测试/工具/素材/旧研究等保护hash；核查不读取玩家存档 |
| [sync_docs.py](sync_docs.py)、[sync_contracts.py](sync_contracts.py)、[finalize_docs.py](finalize_docs.py) | 本次一次性同步过程；不是运行工具，不应在人工后续改稿后重新迁移 |

设计内容：林序顺序/复用、许知微发表/章节、沈见章任务负面、唐以宁伙伴；每人40种、四组各10，总共11主流派、16分组。论文参考的保留与新增见[修订说明](../../docs/论文路线卡牌修订与实现草案.md)。

研究Excel继续保存在[2026-10-29目录](../redesign-20261029/README.md)，本轮不重新抓取或修改其数据。Spire Codex第三方快照不能证明官方最新补丁；此处校园卡为本项目原创设计。

更新逐牌数据时依次运行：

```powershell
python artifacts/redesign-20261030/catalog_v3.py
python artifacts/redesign-20261030/build_delivery.py
python artifacts/redesign-20261030/verify_delivery.py
```

同时同步机制维护源及相关契约。验证器不解释整套卡文、不模拟战斗、不执行Godot，不保证设计已平衡或不存在无限组合。桌面Excel未逐页人工验收；回读是文件/字段一致性证据。
