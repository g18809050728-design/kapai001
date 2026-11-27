# 以玩家为入口的管理工作台 · 2026-11-27

- 管理统计默认展现现存启用账号，包含普通玩家与管理员。支持通过昵称、登录名、编号和角色查找，创建时间与最后登录时间均可按北京时间筛选及排序。
- 玩家资料显示注册和最近登录、本人原始对局及权限变更。对局带角色、难度、首战、结局及起止时间，导入历史标明来源。原活动汇总作为独立入口。
- 成功建立会话时记最后登录。旧账号从保留的七天会话推导可知时间，缺记录时显示「暂无记录」。失败登录和会话探测不更新时间。
- 现有管理员可从目标玩家资料确认升为管理员。角色与审计同事务写入，旧会话失效，新登录可获得现行管理员及开发工具权限。权限记录汇总后台提升及现有命令行创建与撤销，记录操作者、目标、时间和原因。
- 加法迁移保留原有数据。隔离库测试原始对局、查询、角色授权及会话、审计与迁移，再核对生产入口和回滚路径。

## 验证与发布

- 隔离 MySQL 从 `0007_admin_data` 带有历史账号、会话和权限记录升级。成功恢复最近保留会话的微秒级登录时间，缺会话的账号仍为空，原审计事件持续可读。
- MySQL 完整接口集成通过，含北京时间午夜边界、四种排序、账号状态和角色筛选、首战和历史导入、原始数据、角色授权、拒绝匿名和普通玩家写入、重复操作保护、旧会话失效及审计。
- Chromium 隔离浏览器通过玩家筛选、保存返回条件、查看原始对局、确认提升、重新登录及权限记录。桌面和 390 px 手机 150% 字号检查通过，现有反馈、活动汇总、昵称维护和三个 XLSX 下载回归通过。[玩家目录](../../artifacts/verification/player-admin-workspace-20261127/player-directory.png) · [手机目录](../../artifacts/verification/player-admin-workspace-20261127/player-directory-mobile.png) · [玩家资料](../../artifacts/verification/player-admin-workspace-20261127/player-profile.png) · [权限记录](../../artifacts/verification/player-admin-workspace-20261127/player-role-events.png)
- 正式 Web 与 API 已切换到 `20261127-player-admin-workspace`。生产迁移前备份已验证，已启用账号中有 4 个可从保留会话恢复登录时间。公网验证首页、账号脚本和登录入口，新增管理查询及角色写入的匿名访问返回 401。角色提升使用隔离测试账号实测，公网冒烟集中于账号页面。[公网入口日志](../../artifacts/verification/player-admin-workspace-20261127/public-entry.log)

## 回滚

Web 上一版为 `/var/www/kapai001/releases/20261127-player-run-statistics`。回退应用时切回该 Web 目录，调整生产 API 与清理服务的 `50-version.conf` 到 `/opt/kapai-api/releases/20261127-player-run-statistics-directory-compat`，重载 systemd 后重启生产 API 并检查就绪。该版本继续记录成功登录，兼容 `0008_player_directory`。备份和改前配置在 `/var/backups/kapai001/20261127-player-admin-workspace/`。回退应用保留数据库迁移、已生效的角色及审计记录。
