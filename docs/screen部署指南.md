# 使用 screen 部署与长期运行指南

适用项目：《交大四年：DDL 战争》。核对日期：2026-11-21；适用服务器：当前 `/opt/kapai001` 所在的 Alibaba Cloud Linux 3。本文按已有环境编写，命令使用 **Bash**，涉及服务、配置及发布目录的操作在 `root` 终端执行；普通 SSH 用户先运行 `sudo -i`。

**本服务器已经部署成功，直接访问 `https://47.93.245.237/` 就能玩。** 当前服务已经由 systemd 后台管理，关闭 SSH 后仍会运行，并已设置开机启动。如果你的目的只是断开 SSH 后继续提供游戏，第 1～2 节即可；如果希望亲自用 screen 托管账号 API，再按第 3 节切换。

本文交付部署操作说明。本次编写只检查了现有环境，没有停止服务、切换托管方式、重新导出或发布游戏。

## 1. 先理解本项目要运行什么

浏览器中的 Godot 游戏由 Nginx 提供静态文件；登录、对局记录和云存档请求通过同一个 HTTPS 地址转到 FastAPI，再访问 MySQL。

| 组件 | 当前位置或入口 | 当前运行方式 |
|---|---|---|
| 源工程 | `/opt/kapai001` | 修改源码、导出用，不需要持续运行 Godot |
| 正式游戏 | `https://47.93.245.237/` | Nginx 提供 Web 构建 |
| 网页当前指向 | `/var/www/kapai001/current` | 指向已发布版本的符号链接 |
| 核对时的 Web 版本 | `/var/www/kapai001/releases/20261127-player-feedback` | 与源工程的后续修改不自动同步 |
| 正式账号 API | `127.0.0.1:18445` | `kapai-api-prod.service` |
| 正式后端快照 | `/opt/kapai-api/releases/20261127-player-feedback` | API 从此目录加载代码 |
| 后端 Python 环境 | `/opt/kapai-api-venv` | 已安装后端依赖 |
| 正式数据库 | `kapai_prod` | `kapai-mysql.service`，MySQL 8.0.45 |
| 数据库 socket / 数据目录 | `/run/kapai-mysql/mysql.sock` / `/var/lib/kapai-mysql` | 仅本机 socket 连接 |
| 正式环境配置 | `/etc/kapai001/prod-app.env`、`prod-api.env` | 数据库凭据、站点地址和功能开关 |
| Nginx 配置 | `/etc/nginx/conf.d/kapai001.conf` | HTTPS、静态文件和 `/api/v1/` 转发 |

服务器已安装 GNU screen 4.06.02、Godot 4.7.2 及 Web 模板、Python 3.11.13、Nginx 和 MySQL。本机 API 健康检查与 HTTPS 首页在核对时均正常。后续版本以实时命令为准：

```bash
cd /opt/kapai001
screen --version
screen -ls
systemctl is-active kapai-mysql kapai-api-prod nginx
systemctl show kapai-api-prod -p WorkingDirectory --value
readlink -f /var/www/kapai001/current
curl --fail --max-time 10 http://127.0.0.1:18445/internal/ready
```

目前就绪响应为 `{"status":"ok","migration":"0005_feedback"}`。没有 screen 会话时，`screen -ls` 显示 `No Sockets found`，并不表示游戏停止了。

**screen 的作用是保留终端和其中的进程。** 它能让任务在 SSH 断开后继续执行；服务器重启、API 崩溃或进程被系统终止后，screen 本身不会自动恢复任务。现有 systemd 服务已经提供开机启动及 API 失败重启。因此本文保留 MySQL、Nginx、证书续期和每日数据清理的原有管理方式，只提供 API 的可选 screen 接管步骤。

## 2. 保持现有部署，用 screen 查看和维护

启动已有正式服务，适合日常使用：

```bash
systemctl start kapai-mysql
systemctl start kapai-api-prod
systemctl start nginx
systemctl start kapai-api-prod-prune.timer
systemctl is-active kapai-mysql kapai-api-prod nginx
```

建立一个运维终端，在里面查看 API 日志：

```bash
screen -S kapai-ops
journalctl -u kapai-api-prod -f -n 50
```

需要离开时，**先按 `Ctrl+A`，松开后再按 `D`**。看到 `detached` 后可以关闭 SSH，游戏和日志查看任务都会继续运行。下次 SSH 登录后：

```bash
screen -ls
screen -r kapai-ops
```

在这个日志终端中按 `Ctrl+C` 只结束 `journalctl`，随后输入 `exit` 关闭运维会话；API 仍由 systemd 运行。第 3 节直接运行 API 的会话中，`Ctrl+C` 则会停止 API。

## 3. 可选：把正式 API 交给 screen

本节会短暂停止账号、云存档等 API 请求。选择没有玩家正在操作的维护时段，先完成第 7 节备份。**同一个 18445 端口只能由一种方式托管**，按下面顺序执行；无需修改公网地址和 Nginx 转发端口。

### 3.1 准备专用账号和启动脚本

screen 会话由 root 创建，API 使用单独的低权限账号运行。以下命令只需准备一次：

```bash
id kapai-screen >/dev/null 2>&1 || useradd --system --no-create-home --shell /sbin/nologin kapai-screen
install -d -m 0750 /var/log/kapai001-screen

# 保存当前已发布后端的实际位置，不直接运行正在修改的源工程。
systemctl show kapai-api-prod -p WorkingDirectory --value > /etc/kapai001/screen-api-release
chmod 0600 /etc/kapai001/screen-api-release

cat > /usr/local/sbin/kapai-api-screen <<'SH'
#!/bin/bash
set -euo pipefail
umask 027

# 防止误开第二个 screen API 实例。
exec 9>/run/lock/kapai-api-screen.lock
flock -n 9 || { printf 'screen API is already running\n' >&2; exit 1; }

kapai_api_release=$(cat /etc/kapai001/screen-api-release)
case "$kapai_api_release" in
    /opt/kapai-api/releases/*) ;;
    *) printf 'Invalid API release directory\n' >&2; exit 1 ;;
esac
test -f "$kapai_api_release/kapai/main.py"
cd "$kapai_api_release"

set -a
. /etc/kapai001/prod-app.env
. /etc/kapai001/prod-api.env
set +a

# root 读取私有配置；runuser 将配置传入低权限进程。
exec /usr/sbin/runuser -u kapai-screen -- \
    /opt/kapai-api-venv/bin/uvicorn kapai.main:api \
    --host 127.0.0.1 --port 18445 \
    --proxy-headers --forwarded-allow-ips=127.0.0.1 --no-access-log
SH

chmod 0700 /usr/local/sbin/kapai-api-screen
bash -n /usr/local/sbin/kapai-api-screen
```

当前两个 `.env` 文件兼容 Bash 的加载方式，并由 root 独占读取。保留其 0600 权限；不要把凭据贴进命令、screen 日志或仓库，也不要开启 `set -x`。启动脚本使用应用账号配置，不加载迁移账号配置。

### 3.2 停止原 API，再启动 screen

先检查 screen 中没有同名 API 会话，再停止 systemd 的 API。MySQL 和 Nginx 继续运行：

```bash
screen -ls
systemctl stop kapai-api-prod
ss -lntp 'sport = :18445'
```

`ss` 应只剩标题行。如果仍有监听进程，先查清来源，不要继续启动第二份。

```bash
screen -L -Logfile /var/log/kapai001-screen/api.log -dmS kapai-api /usr/local/sbin/kapai-api-screen
screen -ls
curl --fail --retry 5 --retry-connrefused --retry-delay 1 --max-time 5 http://127.0.0.1:18445/internal/live
curl --fail --max-time 10 http://127.0.0.1:18445/internal/ready
```

应看到 `kapai-api` 的 `Detached` 会话，两个健康入口都返回 `status=ok`。再从自己的电脑访问 `https://47.93.245.237/`，验证登录、游客入口及已有进度读取。检查实际进程使用的账号：

```bash
ps -u kapai-screen -o pid,user,args
tail -n 80 /var/log/kapai001-screen/api.log
```

全部通过后，再取消旧 API 的开机启动，避免将来它与手动启动的 screen 争抢端口：

```bash
systemctl disable kapai-api-prod
```

此时 `systemctl is-active kapai-api-prod` 显示 `inactive` 是预期的，改用 screen 会话、进程及健康接口判断 API。**如果任何一步失败，按第 5 节恢复 systemd，不要执行上面的 disable。**

这套 screen 启动方式没有自动重启或开机启动。服务器重启后，先确认 MySQL 和 Nginx 已运行，再重新执行本节的 screen 启动与健康检查。若需要无人值守地处理重启和崩溃，使用第 5 节恢复现成的 systemd 托管。

### 3.3 保留原有定时维护

API 改用 screen 不影响以下独立任务，应继续保留：

```bash
systemctl is-active kapai-api-prod-prune.timer kapai001-cert-renew.timer
systemctl list-timers --all --no-pager
```

前者每日清理过期会话等数据，后者维护现有 HTTPS 证书。screen 启动也继续使用服务端 `admin` 角色决定管理员及开发工具权限，无需另设开发者角色或资格开关。

## 4. screen 常用操作和日志

以下命令使用创建会话时的同一个 Linux 用户；本文 API 会话由 root 创建。

| 目的 | 操作 |
|---|---|
| 查看会话 | `screen -ls` |
| 进入 API 会话 | `screen -r kapai-api` |
| 显示 Attached 时接回 | 确认旧终端属于自己，再运行 `screen -d -r kapai-api` |
| 离开并保持运行 | 先 `Ctrl+A`，松开，再 `D` |
| 浏览历史输出 | `Ctrl+A` 后按 `[`；方向键或 PageUp 翻看，`Esc` 退出 |
| 查看文件日志 | `tail -f /var/log/kapai001-screen/api.log`；`Ctrl+C` 退出 tail |
| 清除已经死亡的会话记录 | 确认显示 Dead 后运行 `screen -wipe` |

API 会话直接运行服务，没有交互 shell。要停止 API，进入会话后按 `Ctrl+C`，等待 Uvicorn 完成关闭；不要把 `Ctrl+C` 当作后台保留操作。

长期运行应轮转日志。本机已安装 logrotate，可创建以下配置，使用系统的 logrotate 定时任务执行轮转：

```bash
cat > /etc/logrotate.d/kapai-screen <<'CONF'
/var/log/kapai001-screen/api.log {
    daily
    maxsize 10M
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    su root root
}
CONF
logrotate --debug /etc/logrotate.d/kapai-screen
```

`--debug` 只检查，不执行轮转；还需确认系统的 cron 或 logrotate 定时器正常运行。大小限制在定时检查时生效，并非日志文件的实时硬上限。`copytruncate` 无需重启 screen，但复制和截断之间可能漏少量日志，不适合作为审计记录的唯一保存方式。

## 5. 停止 screen，恢复原有 systemd 托管

如果 screen API 正在运行：

```bash
screen -r kapai-api
```

进入后按 `Ctrl+C`，等待服务正常退出并回到 SSH 终端。若会话已不存在，直接检查端口。

```bash
ss -lntp 'sport = :18445'
```

确认没有监听进程后恢复：

```bash
systemctl enable --now kapai-api-prod
curl --fail --max-time 10 http://127.0.0.1:18445/internal/ready
systemctl is-active kapai-mysql kapai-api-prod nginx
```

恢复使用原来的发布快照和生产库。无需重建数据库、重新创建管理员或改变浏览器地址。以后日志回到 `journalctl -u kapai-api-prod`。

## 6. 修改项目后怎样更新网页和 API

### 6.1 用 screen 执行较长的 Web 导出

日常启动已发布游戏无需重新导出。源码、图片或 Web 脚本有改动时，才构建新版本。导出前先检查空间和内存：

```bash
df -h /var/www/kapai001 /opt/kapai001
free -h
git -C /opt/kapai001 status --short
screen -S kapai-build
```

核对时本机内存约 1.8 GiB、磁盘可用约 1.9 GiB，当前单份 Web 构建约 277 MiB；导入缓存还会占用空间。只运行一份导出，预留工作空间并保留当前版本和回滚版本。不要直接在 `current` 指向的目录导出，也不要自动删除存档、美术或历史验证证据来腾空间。

首次导出前，在同一台服务器安装 Web 打包依赖：

```bash
python3.11 -m venv /opt/kapai-web-export-venv
/opt/kapai-web-export-venv/bin/python -m pip install -r /opt/kapai001/tools/requirements-web.txt
```

在 `kapai-build` 会话中运行：

```bash
(
    set -eu
    umask 022
    cd /opt/kapai001
    kapai_web_version="manual-$(date +%Y%m%d-%H%M%S)"
    kapai_web_output="/var/www/kapai001/staging/$kapai_web_version"
    mkdir -p "$kapai_web_output"

    timeout --signal=TERM --kill-after=30s 20m \
        godot --headless --editor --path . --import \
        > "$kapai_web_output/import.log" 2>&1
    KAPAI_BUILD_VERSION="$kapai_web_version" \
        PYTHON_BIN=/opt/kapai-web-export-venv/bin/python \
        timeout --signal=TERM --kill-after=30s 30m \
        sh tools/export_web.sh "$kapai_web_output" \
        > "$kapai_web_output/export.log" 2>&1

    test -s "$kapai_web_output/index.html"
    test -s "$kapai_web_output/index.pck"
    test -s "$kapai_web_output/index.wasm"
    test -s "$kapai_web_output/index.wasm.gz"
    test -s "$kapai_web_output/accounts.js"
    test -d "$kapai_web_output/game-assets/pack"
    printf '导出成功，待核对候选构建：%s\n' "$kapai_web_output"
)
```

使用 `Ctrl+A`、`D` 离开，稍后用 `screen -r kapai-build` 回来看结果。括号让失败停止本批后续步骤，同时保留 screen 中的终端。未输出“导出成功”时查看新目录内的日志，先修复失败。

**这台机器已有导出被内存中断、打包后等待退出的历史。** 超时或退出非零均按失败处理；目录里存在文件不代表构建成功，不据此发布。超时只是避免无限等待，不解决资源不足。

使用内测入口核对候选时，用内测 Nginx 配置 `/etc/nginx/conf.d/kapai-stage.nginx.conf` 的 `root` 指向新目录，并沿用仓库内测配置中的 `/game-assets/` 路由。资源块由 Nginx 发送预压缩文件或按客户端能力解压。先备份原配置，执行 `nginx -t` 通过后 `systemctl reload nginx`。通过 SSH 隧道访问内测：

```bash
# 在自己的电脑上运行，用户名替换为实际 SSH 账号。
ssh -N -L 18443:127.0.0.1:18443 你的SSH用户名@47.93.245.237
```

浏览器打开 `https://localhost:18443/`，按[启动指南](程序启动指南.md)信任内测证书。至少验证中文主菜单、账号和游客入口、新局、地图、首战、刷新继续，以及本次修改涉及的页面。内测登录使用内测账号和内测数据库。

### 6.2 发布已经验证的 Web 构建

公网是游戏运行改动的默认交付入口。替换为实际生成并完成相关路径验证的版本号，候选包可使用本机或内测入口核对。静态网页切换沿用当前账号服务；涉及后端不兼容变更时，同步完成相应迁移与 API 验证。[公网交付约定](../agent.md)

```bash
(
    set -eu
    kapai_web_version='替换为已验证的版本号'
    kapai_web_source="/var/www/kapai001/staging/$kapai_web_version"
    kapai_web_target="/var/www/kapai001/releases/$kapai_web_version"
    test -s "$kapai_web_source/index.html"
    test -s "$kapai_web_source/accounts.js"
    test -d "$kapai_web_source/game-assets/pack"
    test ! -e "$kapai_web_target"
    test ! -e /var/www/kapai001/.current-next
    test ! -L /var/www/kapai001/.current-next
    nginx -t

    # 记录旧指向，保留原目录，以便回滚。
    readlink -f /var/www/kapai001/current > /etc/kapai001/web-previous-release
    cp -al "$kapai_web_source" "$kapai_web_target"
    # 构建日志保留在 staging，不放到公网目录。
    rm -f "$kapai_web_target/import.log" "$kapai_web_target/export.log"
    mkdir -p /var/www/kapai001/game-assets
    cp -aln "$kapai_web_target/game-assets/." /var/www/kapai001/game-assets/
    ln -s "$kapai_web_target" /var/www/kapai001/.current-next
    mv -Tf /var/www/kapai001/.current-next /var/www/kapai001/current
    systemctl reload nginx
)
curl --fail --head --max-time 10 https://47.93.245.237/
```

保持原来的协议、地址和端口，浏览器本地进度才能沿用同一个站点。发布后在正式地址再次验证；回滚网页使用刚记录的旧目录：

```bash
(
    set -eu
    kapai_web_previous=$(cat /etc/kapai001/web-previous-release)
    test -s "$kapai_web_previous/index.html"
    test ! -e /var/www/kapai001/.current-rollback
    test ! -L /var/www/kapai001/.current-rollback
    ln -s "$kapai_web_previous" /var/www/kapai001/.current-rollback
    mv -Tf /var/www/kapai001/.current-rollback /var/www/kapai001/current
    nginx -t
    systemctl reload nginx
)
```

发布的 `index.html` 是游戏运行入口，属于既有 Web 导出范围。不要重新生成或上传已删除的局外 HTML 预览、评审页或镜像参考页，也不要将整个仓库作为公网根目录。

### 6.3 更新后端时的区别

仅修改游戏界面或图片时，无需重启 API。后端改动按[账号服务说明](../server/README.md)和[发布记录](plans/2026-11-21-production-accounts-release.md)准备新快照、依赖与验证：

1. 将已经验证的 `server/` 内容复制到新的 `/opt/kapai-api/releases/<版本>`，确保低权限账号可读取；不要覆盖运行中的旧快照。记录旧目录和依赖版本。
2. 有新迁移时先备份，再以生产迁移配置运行 Alembic。API 日常使用应用账号。当前生产库已是 `0005_feedback`，单纯重启无需再次迁移。
3. screen 模式：正常停止 API，把 `/etc/kapai001/screen-api-release` 改成新快照的绝对路径，再执行第 3.2 节的 screen 启动及检查。无需重新从旧 systemd 配置生成该文件。
4. systemd 模式：调整服务 `WorkingDirectory`，运行 `systemctl daemon-reload`、`systemctl restart kapai-api-prod`，再检查 `/internal/ready`。
5. 同步每日清理服务 `kapai-api-prod-prune.service` 的 `WorkingDirectory`，执行 `systemctl daemon-reload`；它是独立进程，不会跟着 screen 自动换目录。

后端回滚时，恢复对应的 API 与清理服务路径及依赖版本。数据库结构已经升级时，先确认旧代码是否兼容；不要把恢复 SQL 备份作为一般网页回滚步骤，否则会覆盖备份之后的玩家数据。

## 7. 备份与日常检查

在 root 私有终端执行，命令使用服务器已有的 MySQL 客户端配置，不展示密码：

```bash
(
    set -eu
    umask 077
    kapai_backup_dir="/var/backups/kapai001/manual-$(date +%Y%m%d-%H%M%S)"
    mkdir -m 0700 -p "$kapai_backup_dir"
    mysqldump --defaults-extra-file=/etc/kapai001/mysql-root.cnf \
        --socket=/run/kapai-mysql/mysql.sock \
        --single-transaction --no-tablespaces --databases kapai_prod \
        > "$kapai_backup_dir/kapai_prod.sql"
    tar -C / -czf "$kapai_backup_dir/config.tgz" \
        etc/kapai001 etc/nginx/conf.d/kapai001.conf \
        etc/systemd/system/kapai-api-prod.service
    readlink -f /var/www/kapai001/current > "$kapai_backup_dir/web-release.txt"
    printf '备份完成：%s\n' "$kapai_backup_dir"
)
```

备份前确认磁盘足够。备份包含账号和私有配置，应加密保存到服务器之外并定期做隔离库恢复演练；生成 SQL 文件本身不证明可以恢复。保留所需的后端/Web 版本和 screen 启动脚本，不能只保留目录名。

MySQL 备份覆盖服务端账号、记录和云存档，游客档及尚未同步的账号进度仍在各自浏览器中；管理员文本覆盖和测试文件也保存在本设备。需要迁移时单独导出/备份，不能用服务器数据库备份替代。不要清除浏览器站点数据来处理普通部署故障。

日常检查：

```bash
screen -ls
systemctl is-active kapai-mysql nginx
curl --fail --max-time 10 http://127.0.0.1:18445/internal/ready
df -h /var/www/kapai001
free -h
du -sh /var/log/kapai001-screen /var/backups/kapai001
```

公网安全组保持 80/443 和受限的 SSH 入口即可。18445、18444、18443 均为本机入口，MySQL 通过 socket 使用，不需要向公网新增 API 或数据库端口。HTTPS 证书继续由现有续期任务维护。

旧回环网页预览 18080 与 Mihomo 监控接口 9090 已停用。需要核对候选时使用回环 HTTPS 18443 和现有 SSH 隧道。[变更与回滚](plans/2026-11-27-player-run-statistics.md)

## 8. 常见问题

| 现象 | 处理 |
|---|---|
| 关闭 SSH 后不确定游戏是否继续运行 | 检查正式网址及 `/internal/ready`；screen 模式再看 `screen -ls` |
| `screen -r` 提示没有会话 | 核对 Linux 用户；API 退出或服务器重启后会话可能消失，查看日志并重新启动 |
| `Address already in use` | 用 `ss -lntp 'sport = :18445'` 查监听来源，保留单一托管方式 |
| screen 刚启动就消失 | `tail -n 80 /var/log/kapai001-screen/api.log`；检查快照路径、依赖、环境配置及 MySQL |
| 网页正常但登录或云存档失败 | 检查 18445 就绪入口及 Nginx `/api/v1/` 转发；网页能打开不代表 API 正常 |
| `origin_rejected` | `KAPAI_ORIGIN` 要与页面协议、主机和端口完全相同；正式站沿用现有配置 |
| `database_not_migrated` | 检查是否连接到预期生产库及其迁移版本，不要删除数据库重建 |
| 网站 502 | 检查 API 是否在 18445 运行及 `/var/log/nginx/error.log`；screen 模式不能用 systemd 的 inactive 单独判断故障 |
| 构建被 Killed、超时或一直不退出 | 查看构建日志及内存/空间；失败产物不发布，现有站点继续使用旧版本 |
| 服务器重启后 screen 不见了 | 按第 3 节重新启动 API，或按第 5 节恢复自动启动的 systemd 托管 |
| 无法访问公网，但本机检查正常 | 检查 Nginx、80/443 安全组、服务器防火墙及证书；不通过开放数据库端口解决 |

本指南的实查范围是已安装工具、运行路径、端口、服务状态、API 健康响应和本机通过正式证书访问首页。screen 接管、生产重启、新版本发布、备份恢复及新构建的完整浏览器流程未在本次文档任务中执行，不作为新的 G0–G8 验收。其他开发启动和管理员命令见[程序启动指南](程序启动指南.md)。
