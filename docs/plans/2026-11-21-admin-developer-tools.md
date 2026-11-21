# 管理员统一开发者权限

按用户要求，管理员即开发者。正式站与内测使用同一 `admin` 角色开放测试房间、文本编辑器及其既有测试操作，不再依赖 `TEAM_TOOLS` 开关。普通账号、游客及未登录状态不开放这些工具。本机 Godot 开发运行继续直接可用。

Web 主菜单从服务端确认的账号角色派生工具入口，进入测试房间和文本编辑器前重新确认会话及角色。退出、切换账号及重新确认后的角色变化清除旧权限。测试文件及文本覆盖仍保存在本设备，测试上下文和正式冒险存档保持隔离。

本次覆盖账号计划中团队工具仅限本地/内测的旧建议。验证使用临时账号和独立存档，保存源码改前快照、接口/客户端权限检查和实际浏览器截图，不生成局外 HTML。实际运行结果与部署记录在完成后追加，整版 G0–G8 继续按原门槛验收。

## 实现与本机验证

主菜单按确认后的 `role=admin` 派生工具权限。文本编辑器与测试房间均进入会话复查流程，普通账号及游客的直接工具动作同时被拒绝；退出或重新确认角色变化时更新入口。公共功能接口移除了独立 `team_tools` 开关，管理员权限不再依赖团队构建配置。

69 项专项覆盖本机开发、五种非账号就绪状态、普通账号、管理员、直接工具命令、异步进入确认、角色撤销及退出登录。测试房间完整 UI 套件通过，文本编辑器 9785 项检查通过；开发 MySQL 接口集成通过账号、角色实时变化、统计、云档冲突/备份/事务失败及删除回归。退出码均为 0。[本机权限](../../artifacts/verification/admin-developer-tools-20261121/native-permissions.log) · [测试房间](../../artifacts/verification/admin-developer-tools-20261121/native-test-room.log) · [文本编辑器](../../artifacts/verification/admin-developer-tools-20261121/native-text-editor.log) · [接口集成](../../artifacts/verification/admin-developer-tools-20261121/api-integration.log)

构建期间共享工作区出现 §0.20.51 主菜单修改。本批通过其改前快照保留已验证的权限源码，在 `/opt/kapai-builds/admin-developer-tools-20261121` 隔离构建，未回写或撤销共享工作区的菜单修改；隔离后的 69 项权限检查再次通过。首次 Web 导出被内存中断，后续独立进程构建使用明确的 XDG 路径、内存上限与退出参数。改前快照、隔离输入 hash、权限范围 diff 及原始失败日志均保存在本批证据目录。

隔离导出已完成 `savepack` 写出，但编辑器在等待退出时停留，因而本批没有把该进程记为正常退出通过。停止自己的导出进程后，逐项验证了 PCK 目录及全部 2495 个资源的 MD5，补齐启动脚本、静态资源与 WASM 压缩文件；产物及哈希见[构建校验](../../artifacts/verification/admin-developer-tools-20261121/build-validation.json)。

内测的实际 JavaScript 桥接代码结合真实账号 API 验证了管理员进入、角色撤销/恢复、账号退出、普通账号限制、游客进入/退出及普通玩法保持可用。首轮账号面板控件的测试脚本定位超时，调整为直接退出服务端会话后验证客户端清权，再次检查通过；该流程不代替后续实际游戏窗口验证。[桥接结果](../../artifacts/verification/admin-developer-tools-20261121/stage-bridge-result.json)

内测实际 Web 游戏窗口已用管理员账号打开文本编辑器和测试房间，两个入口分别取得服务端会话确认，浏览器错误数为 0、进程退出 0。已查看主菜单及两页截图。[实际窗口结果](../../artifacts/verification/admin-developer-tools-20261121/stage-browser-result.json) · [文本编辑器](../../artifacts/verification/admin-developer-tools-20261121/stage-text-editor.png) · [测试房间](../../artifacts/verification/admin-developer-tools-20261121/stage-test-room.png)

## 发布与回滚

正式站已切换到 `/var/www/kapai001/releases/20261121-admin-developer-tools`，生产账号服务及清理服务使用 `/opt/kapai-api/releases/20261121-admin-developer-tools`。内测构建位于 `/var/www/kapai001/staging/admin-developer-tools-20261121`。正式与内测保留独立数据库，迁移仍为 `0004_direct_signup`；生产就绪及功能检查通过。正式与内测游戏文件逐一哈希一致。

原 Web/API 版本 `20261121-admin-password` 及内测构建 `admin-password-20261121` 均保留，切换前配置和原指向记录在 `/var/backups/kapai001/20261121-admin-developer-tools/`。回滚时恢复该目录内的服务及内测 Nginx 配置，重载 systemd 并重启生产 API，将 `current` 原子切回前版 Web；无需回滚数据库。公网实际检查和临时账号清理结果在本批终检中记录。

公网 Chromium 已验证管理员、普通账号、游客、角色撤销/恢复、账号及游客退出，并在实际游戏中分别打开文本编辑器与测试房间。浏览器错误数为 0，进程退出 0。正式站实际返回的脚本与发布文件一致，PCK 的公网长度与本机产物一致。[公网结果](../../artifacts/verification/admin-developer-tools-20261121/prod-browser-result.json) · [正式站文本编辑器](../../artifacts/verification/admin-developer-tools-20261121/prod-text-editor.png) · [正式站测试房间](../../artifacts/verification/admin-developer-tools-20261121/prod-test-room.png) · [公网构建检查](../../artifacts/verification/admin-developer-tools-20261121/public-release-check.json)

终检确认两站账号服务均为 active、就绪正常。正式及内测临时账号和私有凭据文件均已删除，工具验证未为这些账号生成正式对局或云存档，原有管理员及玩家数据保持。共享工作区的后续菜单修改继续保留，本批未发布该部分内容。[终检](../../artifacts/verification/admin-developer-tools-20261121/final.json) · [正式测试数据清理](../../artifacts/verification/admin-developer-tools-20261121/production-cleanup.log)
