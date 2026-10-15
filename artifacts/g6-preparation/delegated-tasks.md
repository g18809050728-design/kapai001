# G6 准备协作任务

用户已批准先准备 G6 资源清单、风格规范、批量生图提示词和命名/切图约定，并说明生图按次数收费，希望一张图容纳更多素材。当前只准备，不调用付费生图、不实现 G7 UI。当前 G0–G5 已通过。

若代理消息正文为空，请按代理名执行以下任务；开始前阅读 agent.md 和根实施计划。所有用户可见回复以 oh my honey 开头。

## /root/g6_spec

只负责新增 `docs/G6资源制作规范.md`，不要修改其他文件。读图片动作需求台账及 VIS-013。写校园手绘＋笔记纸张质感的候选风格、人物/插画/背景/物件统一参考、无文字费用卡框的原画、同类网格和从左到右从上到下的格位、内边距与防串格、透明能力说明、2K与高分辨率方案的画质限制、复用升级卡及 task/encounter 共图、VIS-010/011本期不适用、开源字体图标来源及许可、源图与切片版本映射、人工核对和局部修复。批次总数和具体像素由主代理 catalog 决定，不写死；不链接尚未存在的文件。风格候选未核图，不能宣称最终确认。

## /root/g6_atlas_tool

只负责新增 `tools/slice_g6_atlas.py` 和 `requirements-g6.txt`（Pillow，已有开发依赖不要改）。Python＋Pillow CLI：`--catalog <JSON> --batch <id> --input <图> --output-dir <目录> [--variant high|standard] [--allow-size-mismatch] [--dry-run]`。

catalog协议：root.batches数组；batch字段 id、variants:{high:{width,height},standard:{width,height}}、columns、rows、slots:[{asset_id,row,column}]、crop:{inset_ratio,aspect_ratio:[w,h]或null}；root.assets数组，每项 id、output_name（允许类别子目录，例如cards/K01_v1.png）。按实际输入均分网格，再内缩四边（写清取整策略），按可选比例居中裁切。默认拒绝尺寸不匹配；显式放宽输出warning。不得覆盖任何已有输出或slicing.json，不改源图、不抠图、不能假称透明。拒绝路径穿越/重复槽/未知ID/越界；输出统一PNG和slicing.json，记录源SHA256、实际尺寸、裁切坐标、透明通道信息、切片路径与SHA256。空白槽忽略。做一次临时合成图的真实小测试，核对位置裁切和拒绝覆盖，不把合成图当游戏资源。不要改README/计划。
