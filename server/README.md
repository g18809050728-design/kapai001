# 账号服务开发与运维

Windows 开发、当前 Linux 服务启动、数据库实查与管理员创建入口见[程序启动指南](../docs/程序启动指南.md)。

当前主程序为 `https://47.93.245.237/`，生产 API 由 `kapai-api-prod.service` 监听回环 18445，连接 `kapai_prod`。生产配置位于 `/etc/kapai001/prod-app.env` 与 `/etc/kapai001/prod-api.env`，工作目录是后端发布快照 `/opt/kapai-api/releases/20261121-admin-developer-tools`。注册使用用户名和密码，管理员同样通过密码登录。邮件找回密码待配置 SMTP。生产网关及回滚步骤见[发布记录](../docs/plans/2026-11-21-production-accounts-release.md)。

本服务由 FastAPI、SQLAlchemy、PyMySQL 和 Alembic 组成。单人规则照常在 Godot 执行。MySQL 负责账号、会话、对局摘要、统计与云同步副本。[实施计划](../docs/plans/2026-11-21-account-cloud-save-plan.md)

## 开发数据库

可以用 Windows 本机 MySQL，也可以在 Linux 使用独立的开发库。建库用 InnoDB、`utf8mb4`。给迁移账号授予本库 DDL/DML，给应用账号授予本库 `SELECT, INSERT, UPDATE, DELETE`。数据库通过本机端口或 socket 连接。复用 [环境样例](config.env.example)，在运行进程的环境中设置实际凭据。Linux socket 用 `KAPAI_DB_SOCKET`，优先于 TCP。开发库、内测与公网的连接凭据分别注入。

```sh
python3.11 -m venv .venv
.venv/bin/pip install -r server/requirements.txt
.venv/bin/alembic -c server/alembic.ini upgrade head
```

迁移 `0004_direct_signup` 将账号启用与邮箱验证分开，已有验证邮箱的账号继续可用。应用就绪入口核对迁移版本。开发机也可以用 PowerShell 调用对应的虚拟环境解释器并用 `$env:` 设置环境。启动时使用应用凭据，从 `server/` 运行 `uvicorn kapai.main:api`，生产通过反向代理暴露同站点的 `/api/v1/`。就绪入口 `/internal/ready` 和存活入口 `/internal/live` 仅供内网或本机检查。

## 本机内测

本环境提供 [systemd 配置](deploy/kapai-api-stage.service) 和 [同源 Nginx 配置](deploy/kapai-stage.nginx.conf)。MySQL，API 和 Nginx 内测入口分别使用项目独立 socket、回环 18444 和回环 HTTPS 18443。可用 SSH 隧道在有桌面的设备上查看。

```sh
ssh -L 18443:127.0.0.1:18443 user@your-server
```

浏览器打开 `https://localhost:18443/`。信任服务器管理员交付的内测证书后验证。Web 端先确认登录，之后开放玩法入口。`KAPAI_REGISTRATION=1` 开放用户名和密码注册，无需 SMTP。已有验证邮箱的账号可按原流程重置密码，内测邮件写入 `/var/lib/kapai-account-stage/`，生产邮件使用独立 SMTP 主机、STARTTLS 和发件人。`KAPAI_ACCOUNTS`、`KAPAI_ADMIN`、`KAPAI_CLOUD` 控制对应账号功能。管理员同时拥有开发者权限，正式站及内测均可使用测试房间和文本编辑器，不再使用独立团队工具开关。

Web 构建通过 `KAPAI_BUILD_VERSION=版本 sh tools/export_web.sh <目录>` 标记统计版本。用独立版本目录做构建和验证。发布时把 Nginx 路由指向新版本和独立生产 API，回滚时可切回已验证的构建并关闭对应功能，保留 MySQL 行和本地进度。

## 管理员、备份与保留

用应用账号环境从 `server/` 执行 `python -m kapai.manage admin-create 管理员邮箱`，也可附加 `--username 用户名`。密码由私有终端输入。管理员使用邮箱或用户名加密码登录。用 `python -m kapai.manage admin-revoke 管理员邮箱` 撤销角色和现有会话。角色操作和受权统计访问写审计表。

使用受保护的客户端配置文件和 `mysqldump --single-transaction --no-tablespaces` 备份，再将备份恢复到独立库，核对迁移版本、表、数据和外键。部署时为生产安排加密备份存储与轮转，本地阶段使用空库和测试数据演练。每日 `python -m kapai.manage prune` 处理过期会话、令牌、90 天事件和 30 天幂等回执。对局表保留首战、结算等里程碑用于长期统计。每份云快照限 4 MiB。云版本保留当前与上一份，终局历史另外保留摘要。删账号会清理账号云档和单人对局历史。

运行内测 API 集成测试时安装 `httpx`，将开发库应用凭据加载到环境，从项目根目录执行 `PYTHONPATH=server python server/tests/integration.py`。测试使用临时邮件目录和随机测试账号。
