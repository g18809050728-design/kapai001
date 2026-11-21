# 注册、登录与游客入口重做

2026-11-21 · HTTPS 内测构建 `20261121-account-entry`。从原内测地址 `https://localhost:18443/` 打开游戏，在主菜单右上角选择「登录」。远程内测通过现有 SSH 隧道访问。[内测运维说明](../../server/README.md)

- 登录表单收集用户名或邮箱和密码，提供密码显示、找回密码和账号创建入口。只有管理员在密码验证通过后看到动态码。桌面表单使用游戏内校园场景作为配图，短窗口为单列滚动表单。账号表单采用密码管理器的 `username`、`current-password`、`new-password` 和 `one-time-code` 字段。[Steam 登录](https://store.steampowered.com/login/) · [HTML autocomplete](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Attributes/autocomplete)
- 注册时设置并确认密码。验证邮件只需确认邮箱。用户名为 3–24 位字母、数字或下划线，首位为字母或数字，登录不区分大小写。迁移前验证邮件和已有邮箱账号继续可用，旧账号可补设一次登录用户名。
- 「以游客身份游玩」直接返回游戏主菜单。访客统计选择放入「设置与存档 → 隐私设置」，首次使用默认关闭。管理员看板继续单列游客浏览器统计。

## 验证

- 开发库与内测库迁移至 `0003_usernames`，内测就绪检查通过。MySQL 集成覆盖注册密码、唯一用户名、邮箱激活、用户名和邮箱登录、旧邀请和旧账号补设、密码重置撤销会话。对局、管理统计、云存档和账号删除的接口回归通过。[迁移版本](../../artifacts/verification/account-entry-20261121/stage-migration.log) · [接口集成](../../artifacts/verification/account-entry-20261121/api-integration.log)
- Chromium 1280×800 使用内测构建实测 Tab 焦点、密码显示、两次密码不一致、邮箱激活前的登录提示、激活后用户名登录、找回密码、邮箱登录和删除测试账号。[桌面登录](../../artifacts/verification/account-entry-20261121/01-desktop-login.png) · [桌面注册](../../artifacts/verification/account-entry-20261121/02-desktop-registration.png) · [桌面浏览器日志](../../artifacts/verification/account-entry-20261121/browser-desktop.log)
- Chromium 手机模拟使用 844×390 与 390×844。横屏登录的游客按钮无需滚动，150% 字号的注册表单可滚动至提交。游客返回游戏主菜单后可进入隐私设置，核对默认关闭、开启时访客事件返回 200、再次关闭。[手机横屏登录](../../artifacts/verification/account-entry-20261121/03-mobile-landscape-login.png) · [手机竖屏注册](../../artifacts/verification/account-entry-20261121/05-mobile-portrait-registration.png) · [隐私设置](../../artifacts/verification/account-entry-20261121/08-mobile-privacy.png) · [手机模拟日志](../../artifacts/verification/account-entry-20261121/browser-mobile.log)
- Godot Web 导出退出 0。内测经 Nginx 提供，公网仍指向 `20261121-touch-web`。邮箱通过内测本机邮件目录验证，正式邮件投递和手机真机待验收。[Web 导出](../../artifacts/verification/account-entry-20261121/web-export.log) · [构建校验](../../artifacts/verification/account-entry-20261121/stage-build.sha256)
