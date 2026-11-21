# 恢复游客登录

2026-11-21 · HTTPS 内测版本 `20261121-guest-login`。首进时，主选项区提供「登录」「创建账号」「游客登录」。确认账号会话或明确选择游客后开放冒险入口。账号服务不可用时，可从主选项区选择游客。

浏览器在当前标签页记录游客选择，刷新后可继续使用同一个本机游客档。游客菜单显示「登录账号」，登录成功后切到对应账号的存档空间。游客对局使用本机保存。访客统计仍由隐私设置控制。

账号仍走服务器会话检查，注册继续使用用户名和密码。操作地址和原内测 SSH 访问方式见[运维说明](../../server/README.md)。

桌面 Chromium 实测主菜单显示三个身份入口。点击游客登录后阻断账号 API，依然可进入选角、开局并写入普通本机游客档。浏览器没有发出账号登录、对局或云存档写请求。[主菜单](../../artifacts/verification/guest-login-20261121/01-entry-options.png) · [游客菜单](../../artifacts/verification/guest-login-20261121/02-entered-as-guest.png) · [游客实际开局](../../artifacts/verification/guest-login-20261121/03-guest-adventure.png)

刷新后保留游客选择及原快照校验和。点击继续实际进入同一地图，开局和续玩截图逐字节相同。桌面脚本完成断言与截图后在关闭浏览器时收到终止信号。Godot Web 导出退出 0。[刷新后续玩](../../artifacts/verification/guest-login-20261121/04-resumed-guest-adventure.png) · [桌面日志](../../artifacts/verification/guest-login-20261121/browser-desktop.log) · [Web 导出日志](../../artifacts/verification/guest-login-20261121/export.log)

手机横屏模拟在账号 API 返回 503 时打开设置、返回主菜单并点选游客，进入游客菜单。内测构建继续使用原 HTTPS 地址。[手机横屏游客菜单](../../artifacts/verification/guest-login-20261121/06-mobile-guest-menu.png) · [手机模拟日志](../../artifacts/verification/guest-login-20261121/browser-mobile.log) · [构建校验](../../artifacts/verification/guest-login-20261121/stage-build.sha256)

## 游客退出登录

§0.20.46 将游客菜单的「登录账号」改为「退出登录」。退出清除当前标签页的游客状态并返回身份选择。仍在进行且可保存的冒险沿用保存并退出流程。模拟保存失败时，游客状态和当前对局保留。游客退出不调用账号接口。[退出逻辑测试](../../artifacts/verification/guest-logout-20261121/bridge.log)

版本 `20261121-guest-logout` 已部署到原 HTTPS 内测地址。桌面 Chromium 实测空档时退出、进行中的对局保存退出、重新选择游客并继续。退出前后的快照校验和一致，地图截图逐字节相同。Web 导出与浏览器测试均退出 0。[游客菜单](../../artifacts/verification/guest-logout-20261121/01-guest-exit-action.png) · [返回身份选择](../../artifacts/verification/guest-logout-20261121/02-returned-to-identity-selection.png) · [浏览器日志](../../artifacts/verification/guest-logout-20261121/browser-desktop.log)
