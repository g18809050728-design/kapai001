# 账号、MySQL 与云存档内测记录

已按批准范围接入 Linux 独立 HTTPS 内测。内测地址为 `https://localhost:18443/`，远程访问可使用 SSH 隧道。MySQL 通过项目的 Unix socket 接入，API 监听本机 18444。开发、内测和生产使用不同库及应用凭据。现有公网试玩保留先前构建，生产数据库已经迁移但无账号和对局行。[获批计划](2026-11-21-account-cloud-save-plan.md) · [部署和复测命令](../../server/README.md)

| 需求 | 交付与实测 |
|---|---|
| DB-01 | 使用服务器现有 MySQL 8.0.45 建独立实例，替代草案建议的 8.4 LTS。Alembic 迁移到 `0002_retention`，重跑幂等。应用账号读写成功、DDL 被拒绝。含内测对局与云版本的备份恢复到新库。连接不可用用例中存活 200、就绪 503。 |
| AUTH-01 | 同源会话 Cookie、邮箱验证、重置密码、删除账号、游客入口、对局历史与终局事件。MySQL 集成覆盖已验证才可登录、会话与账号绑定、重置时失效、重复对局及结算冲突。真实桌面 Web 注册、验证、登录、开局写入历史。客户端队列定向检查核对不同对局分别隔离结算冲突。Godot 专项验证同一真实会话发出一次开局、首战和终局。内测邮件使用本机受限投递目录。 |
| ADMIN-01 | 管理员双重验证、服务端权限、聚合看板、角色撤销、访问审计、定时保留策略。MySQL 集成核对普通账号受限、管理员 MFA、游客去重、版本漏斗和权限实时变更。开通与撤权命令均留有审计行。普通账号主菜单未出现管理入口。 |
| SYNC-01 | 桌面 1280×800 登录开局并推进到首战第 2 回合。独立 844×390 触屏模拟浏览器登录，取得完全相同的快照并点击继续进入同一战斗。实际快照约 31 KB。集成验证旧修订冲突、同请求重复上传、事务写入失败、前版读取和隔离删除。Godot 验证旧 FY 档移入账号缓存、保持原字节、读档迁移及所有随机流一致，并拒绝未知内容替换有效档。 |
| SAVE-CLOUD-01 | 本地按稳定边界保存，重复快照跳过重写，云端合并普通请求，手动保存及关键边界优先上传。实机一次新局至第 2 回合记录 3 次云写入。账号 API 返回 503 时，已登录标签页刷新保有本机进度。原生同一快照重复保存 8 次对比，P50 约 109→36 ms，P95 约 176→59 ms，优化版保留历史备份。 |
| MP-DESIGN-01 | 已建对局与参与者关系，时序稿覆盖创建房间、两席位、预期修订号、命令重试、重连与服务端结算。本期实现单人数据和账号约定，实时房间排入未来联机计划。 |

## 验证边界

内测运行 Python 3.11.13、MySQL 8.0.45、Godot 4.7.2、Chromium 141。原生规则套件出口 0，退出时引擎报告资源仍在使用，保留原始日志。整套 UI 同进程执行达到主机内存上限，分批及逐项重跑的 29 套中有 28 套通过。战斗演出套件 `test_ui_battle_polish` 在本次代码和改前基线 `f8966f1` 的标准无头入口均报 Godot signal 11。浏览器首轮亦遇到内存限制，最终在测试进程专用内存组中运行。实机核对补齐了中文表单字体。[规则原始日志](../../artifacts/verification/account-cloud-20261121/native-rules.log) · [UI 崩溃基线对照](../../artifacts/verification/account-cloud-20261121/ui-battle-polish-baseline.log) · [浏览器结果](../../artifacts/verification/account-cloud-20261121/browser-result.json) · [账号存档专项](../../artifacts/verification/account-cloud-20261121/native-account-legacy.log) · [MySQL 接口集成](../../artifacts/verification/account-cloud-20261121/api-integration-final.log)

内测验证使用隔离数据。手机真机、Windows 实机、正式 SMTP 对外投递与公网切换仍待验收。旧档用例和终局故障注入使用可复现的独立测试档。并发写入通过服务端修订号冲突接口验证，完整的跨设备分叉界面尚需真机签收。整版 G0–G8 仍按各自门槛验收。[操作画面](../../artifacts/verification/account-cloud-20261121/08-mobile-resumed-battle.png) · [登录面板](../../artifacts/verification/account-cloud-20261121/01-login-final.png) · [模拟接口不可用](../../artifacts/verification/account-cloud-20261121/09-mobile-offline-ready.png)

战斗演出套件另用单线程场景与 ALSA 空设备重跑，均复现退出码 134。其余 28 套的通过证据保存在分组或单套日志。[单线程日志](../../artifacts/verification/account-cloud-20261121/ui-battle-polish-single-thread.log) · [ALSA 日志](../../artifacts/verification/account-cloud-20261121/ui-battle-polish-alsa.log)
