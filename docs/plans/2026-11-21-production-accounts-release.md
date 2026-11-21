# 账号与游客版公网发布

当前 §0.20.52 已重做紧凑身份入口和游戏记录视觉，静态构建为 `20261121-account-records-polish-v2`；后端及数据库沿用原服务。[当前视觉与验证](2026-11-21-account-records-polish.md)

§0.20.51 已整理独立游戏记录、存档同步与管理员统计，并分离退出游戏与退出登录。[入口与行为](2026-11-21-menu-account-layout.md)

后续 §0.20.49 已将管理员登录更新为用户名或邮箱加密码，§0.20.50 进一步统一管理员与开发者权限，当批静态构建位于 `20261121-admin-developer-tools` 目录。[管理员登录更新](2026-11-21-admin-password-login.md) · [开发者权限更新](2026-11-21-admin-developer-tools.md)

用户授权将当前内测版发布为主程序。发布源为 `20261121-guest-logout`，公网地址沿用 `https://47.93.245.237/`。发布目录为 `/var/www/kapai001/releases/20261121-accounts-main`，后端快照位于 `/opt/kapai-api/releases/20261121-accounts-main`。

生产 API 通过 `kapai-api-prod.service` 在本机 18445 端口运行，Nginx 同源代理 `/api/v1/`。数据库为 `kapai_prod`，从 `0002_retention` 升级到 `0004_direct_signup`。注册继续使用用户名和密码，生产邮件服务尚未配置。

发布前配置和数据库备份放在服务器 `/var/backups/kapai001/20261121-accounts-main/`，发布检查证据位于 `artifacts/verification/production-accounts-20261121/`。备份目录权限为 0700，SQL 备份权限为 0600。

## 生产服务

正式站使用独立生产库，玩家可在正式站创建账号。游客读取原公网域下的本机档。生产 API 从版本目录加载源码，正式数据库凭据由 `/etc/kapai001/prod-app.env` 注入，API 功能配置来自 `/etc/kapai001/prod-api.env`。

`kapai-api-prod.service` 和 `kapai-api-prod-prune.timer` 已开机启用。就绪检查返回 `0004_direct_signup`。公网功能开启账号、注册、云存档和管理权限校验，邮件密码找回待 SMTP 配置。发布时生产库的管理员数量为 0。[就绪检查](../../artifacts/verification/production-accounts-20261121/production-ready.json) · [公网功能](../../artifacts/verification/production-accounts-20261121/public-features.json)

## 验证

公网 HTTPS 接口实测注册后取得安全 Cookie、退出、用户名登录、CSRF 拦截、越权拒绝、普通账号访问管理统计被拒绝、对局与终局去重、云快照上传和读取、重复请求以及修订冲突。测试账号及其对局、云版本已通过删除账号接口清理。[公网 API 结果](../../artifacts/verification/production-accounts-20261121/public-api-result.json)

桌面 Chromium 使用公网地址和受信任证书加载主菜单，真实注册账号后进入选角并开局。账号本机档与云快照的校验和一致，MySQL 返回一条开局记录。首轮浏览器脚本在开局步骤超时，增加选角画面和会话响应等待后复测通过。复测完成所有业务断言及测试账号清理，浏览器关闭时收到终止信号。运行中的脚本错误数为 0。[公网主菜单](../../artifacts/verification/production-accounts-20261121/01-public-desktop-entry.png) · [真实账号开局](../../artifacts/verification/production-accounts-20261121/02-public-account-run.png) · [浏览器结果](../../artifacts/verification/production-accounts-20261121/browser-desktop-result.json)

手机横屏模拟使用 844×390 触屏窗口，通过公网主菜单完成游客登录和退出登录。脚本错误数为 0，进程退出 0。最终核对生产服务、数据库迁移和测试账号清理，结果见[发布终检](../../artifacts/verification/production-accounts-20261121/production-final.json)。手机真机及 Windows 原生发行沿用原验收范围。[公网游客菜单](../../artifacts/verification/production-accounts-20261121/04-public-mobile-guest.png) · [手机尺寸结果](../../artifacts/verification/production-accounts-20261121/browser-mobile-result.json)

发布目录的 16 个运行文件与内测版逐文件哈希一致，后端快照与已验证源码一致。80 端口返回 308 跳转到 HTTPS，公网内部健康路径返回 404，生产和内测 API 各自使用回环端口。[构建核对](../../artifacts/verification/production-accounts-20261121/promoted-build-check.log)

## 回滚

发布前主程序目录为 `/var/www/kapai001/releases/20261121-touch-web`。需要恢复旧页面时，在服务器上恢复网关配置并原子切换构建指向。

```sh
cp /var/backups/kapai001/20261121-accounts-main/kapai001.nginx.conf /etc/nginx/conf.d/kapai001.conf
nginx -t
ln -s /var/www/kapai001/releases/20261121-touch-web /var/www/kapai001/.current-rollback
mv -Tf /var/www/kapai001/.current-rollback /var/www/kapai001/current
systemctl reload nginx
```

生产数据库和账号数据按原库保留，后续恢复账号版时继续使用。恢复 SQL 备份需先单独备份上线后产生的数据，并按实际故障选择恢复范围。
