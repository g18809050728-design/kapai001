# 管理员密码登录

后续 §0.20.50 已将管理员与开发者权限统一，当前发布目录为 `20261121-admin-developer-tools`。本文保留密码登录批次的实测记录。[后续更新](2026-11-21-admin-developer-tools.md)

按用户要求，管理员使用用户名或邮箱加密码登录。登录表单直接建立账号会话，管理统计按服务器读取的当前角色校验权限。创建管理员时只需设置密码。

既有数据库中的验证器字段保留为兼容数据，现有管理员账号和会话继续可用。实现范围包括账号登录、会话读取、管理统计、管理员创建命令、Web 表单和启动指南。

开发库接口集成通过了管理员创建命令、密码登录、错误密码拒绝、历史验证器数据兼容、不同历史会话标记、管理统计访问和角色实时撤销，并回归账号、对局和云存档接口。[集成日志](../../artifacts/verification/admin-password-20261121/api-integration.log)

公网主程序与内测页面均更新为 `20261121-admin-password`。正式 Web 目录为 `/var/www/kapai001/releases/20261121-admin-password`，后端快照位于 `/opt/kapai-api/releases/20261121-admin-password`。生产 API 和清理服务指向该快照，内测 API 沿用项目源码入口。数据库继续使用 `0004_direct_signup`。

公网接口使用临时管理员实测了用户名登录、邮箱登录、错误密码返回 401、会话读取及管理统计访问。临时管理员经当前创建命令建立。[公网接口检查](../../artifacts/verification/admin-password-20261121/public-api-result.json)

公网 Chromium 实测登录表单仅提交用户名和密码，登录后打开「管理统计」并查询成功。浏览器错误数为 0，测试退出 0。临时管理员及其凭据文件已经清理，生产原有管理员账号继续保留。[网页检查](../../artifacts/verification/admin-password-20261121/browser-result.json) · [管理统计画面](../../artifacts/verification/admin-password-20261121/admin-statistics.png) · [上线终检](../../artifacts/verification/admin-password-20261121/production-final.json)
