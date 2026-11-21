# 登录后进入游戏与免邮件注册

后续 §0.20.45 恢复了游客登录。账号登录验证与免邮件注册沿用本文方案。[恢复游客登录](../../实施计划与验收基线.md)

2026-11-21 · 内测版本 `20261121-login-gate`。从主菜单选项区登录或创建账号。服务端会话确认后，才出现「继续冒险」和「新的四年」。进入选角、正式开局或续玩前重新确认会话。会话失效时回到登录入口，账号服务暂不可用时可重新连接。

新账号使用用户名和密码注册，注册成功后浏览器确认新会话并显示冒险入口。已有账号仍可通过原邮箱登录或使用已验证邮箱找回密码。以前在本机创建的游客进度仍可从「账号 → 云存档」导入。

开发库接口集成验证了无邮件服务的注册和会话、用户名唯一、旧账号邮箱登录和密码重置，以及对局、管理权限和云存档接口。内测库已迁移至 `0004_direct_signup`，核对所有原邮箱已验证账号均可继续登录。[接口集成日志](../../artifacts/verification/login-gate-20261121/api-integration.log) · [内测就绪](../../artifacts/verification/login-gate-20261121/stage-ready.json)

桌面 Chromium 1280×800 从主菜单打开登录和创建账号，注册后确认会话并返回已登录菜单。移除会话 Cookie 后，点击「新的四年」会回到登录入口。重新登录后，选角和正式开局均完成会话检查，实际对局事件入库。桌面脚本完成业务断言后在清理阶段收到终止信号，测试账号另行清理并核对。[未登录主菜单](../../artifacts/verification/login-gate-20261121/01-main-menu-locked.png) · [注册](../../artifacts/verification/login-gate-20261121/02-register.png) · [会话失效](../../artifacts/verification/login-gate-20261121/04-main-menu-session-expired.png) · [对局](../../artifacts/verification/login-gate-20261121/05-authenticated-run.png) · [桌面日志](../../artifacts/verification/login-gate-20261121/browser-desktop.log) · [清理记录](../../artifacts/verification/login-gate-20261121/browser-fixture-cleanup.log)

Chromium 844×390 手机横屏模拟从主菜单触屏打开登录和注册，验证注册表单宽度。Godot Web 导出和手机模拟退出码均为 0。本次部署范围为 HTTPS 内测。[手机横屏主菜单](../../artifacts/verification/login-gate-20261121/06-mobile-locked-menu.png) · [手机横屏注册](../../artifacts/verification/login-gate-20261121/07-mobile-register.png) · [构建校验](../../artifacts/verification/login-gate-20261121/stage-build.sha256)
