# 玩家与对局事件统计 · 2026-11-27

- 玩家活动按北京时间统计新增启用账号、主动同意匿名统计的独立游客浏览器，以及有开局、完成首战或结束对局事件的独立账号。累计启用账号数与日期无关。整个区间和单日分别去重。对局事件读取原始里程碑，可覆盖事件日志的保留期限。游客仅覆盖仍保留的匿名日志。
- 每日事件使用服务端记录的开局、首战及终局时间。对局漏斗及结局按开局日归组，可按角色、难度查询，包含统计修正和人工补录。对局结局区分胜利、失败、主动放弃、已结算但结局未知和未结算。人工补录没有玩家身份或实际结局时，只影响对局统计。
- 管理统计、对局筛选及其 XLSX 以玩家和对局事件为维度。既有对局与反馈中的版本元数据继续保留。保留管理员角色检查、跨页导出、修正、移出和恢复。
- 使用隔离开发库和浏览器核对事件日期、跨日去重、历史与补录口径、管理员权限和报表。正式发布沿用同站点及上一版回滚。撤下本机冗余监听后核对公网站点与内测 API。

## 验证与发布

- 隔离 MySQL 完整账号服务集成测试通过，覆盖北京时间午夜边界、区间去重、首战与终局跨日、历史导入、结局筛选、人工统计修正、权限及 XLSX 实际数据列。Chromium 隔离验证通过统计概览、对局明细与维护、三类 XLSX 下载、反馈回归及 390 px 手机 150% 字号。[概览](../../artifacts/verification/player-run-statistics-20261127/stats-overview.png) · [每日事件](../../artifacts/verification/player-run-statistics-20261127/stats-daily.png) · [手机概览](../../artifacts/verification/player-run-statistics-20261127/stats-overview-mobile.png)
- 正式 Web 和 API 已切换为 `20261127-player-run-statistics`。正式库就绪迁移为 `0007_admin_data`，新增聚合已在正式库只读核对。管理统计、明细和相应 XLSX 的匿名访问均返回 401。
- 公网 HTTPS 首页及全部 12 个压缩资源块返回 200，资源长度与发布包一致。游戏入口与资源逐字节匹配上一版。服务器内存不足，内核终止了公网实机测试的 Chromium 渲染进程，完整游戏启动未在本机重新通过。[浏览器日志](../../artifacts/verification/player-run-statistics-20261127/public-browser.log)
- 在 Nginx 中撤下旧回环网页预览 `18080`，在 Mihomo 中关闭回环监控接口 `9090`。复查两个端口均无监听，生产 HTTPS 和 API 正常，Nginx、Mihomo 与生产 API 均为运行状态。内测 HTTPS 返回 200，内测 API 就绪检查在操作前后均因内测库仍在 `0004_direct_signup` 返回 503。本次只发布生产。

## 回滚

Web 上一版位于 `/var/www/kapai001/releases/20261127-55590a3`。两个生产 API 服务的原 `50-version.conf` 指向 `/opt/kapai-api/releases/20261127-admin-data`。回滚时先切换 Web 链接，再恢复配置、重载 systemd 并重启生产 API。原配置、端口变更前后快照和上一版路径存于 `/var/backups/kapai001/20261127-player-run-statistics/`。监听变更可独立回滚，使用该目录的 `kapai001-preview.conf` 与 `config.yaml`，分别重载 Nginx 与重启 Mihomo。
