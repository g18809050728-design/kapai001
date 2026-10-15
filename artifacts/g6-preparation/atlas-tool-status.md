# G6 离线切图工具交接

日期：2026-10-15。已完成 `tools/slice_g6_atlas.py`、`requirements-g6.txt`，未改 README、根计划或游戏代码。

CLI 按 delegated-tasks.md 协议实现，默认 `--variant high`。row/column 从 0 开始；未列出的格子及 asset_id 为 null/空字符串的格子不导出。均分网格使用 floor(index*size/count)；每侧 inset 向上取整；比例裁切向下取整并居中，奇数余量留在右侧/下侧。裁切坐标采用 Pillow 的左上包含、右下不包含格式。

默认拒绝尺寸不符；`--allow-size-mismatch` 显式警告并按实际像素切，不放大。默认不覆盖任何 PNG 或 slicing.json，拒绝目录越界、重复格位/ID、未知 ID、非法文件名及范围越界；失败时清理此次已创建文件。dry-run 不落盘。实际导出统一 PNG，记录源文件/catalog SHA256、尺寸、模式、原有 alpha/实际透明像素、各裁切坐标、切片 SHA256，所有资源状态为 candidate_unreviewed。RGB 源图保持 RGB，不抠图或假称透明。

真实临时合成图 smoke 已运行，退出 0：41×43 四色网格，2×2，inset=0.1、aspect=2:1，A/D 裁切框分别 `[2,6,18,14]` 与 `[23,28,38,35]`。核对裁切位置/输出像素/PNG 尺寸/SHA256/原图不变/不伪造 alpha；默认尺寸拒绝、显式放宽 warning、重复执行拒绝覆盖、重复槽/未知 ID/越界/路径穿越拒绝均通过。合成图全部使用 TemporaryDirectory 并已清除，不是游戏资源或 G6 图像验收。命令帮助入口也已运行，退出 0。

对接示例：`python tools/slice_g6_atlas.py --catalog <catalog.json> --batch <id> --input <图.png> --output-dir <全新候选目录> --variant high --dry-run`。检查裁切框后去掉 --dry-run 导出，最后人工核图；重新切同一批使用新的版本目录。
