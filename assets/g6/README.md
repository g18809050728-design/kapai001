# G6 资源制作包与选定资源

状态：2026-10-15，用户提供的 **6 张 3840×2160 图集已全部切分，46 个素材已完成 AI 视觉核对并选定为 G7 原型资源**。这不是人工签字或最终 UI 验收；G6/G7 的阶段状态以根实施计划为准。

## G7 接入入口

以 [selection.json](selection.json) 中每项 `selected_file` 为实际资源路径，选定图片位于 [assets/art/g6-v1](../art/g6-v1/)。`catalog.json` 是制作规划，不能代替实际选定清单。

| 类别 | 数量 | 选定目录 |
|---|---:|---|
| 人物半身像 | 6 | `assets/art/g6-v1/portraits/` |
| 卡图 | 18 | `assets/art/g6-v1/cards/` |
| 任务图 | 6 | `assets/art/g6-v1/tasks/` |
| 饰品图 | 8 | `assets/art/g6-v1/relics/` |
| 环境与结算背景 | 8 | `assets/art/g6-v1/backgrounds/` |

清单保留 66 个冻结内容 `(kind, id)` 的映射，以及 16 项 VIS/ACT 的资源处理方式。升级牌和重复场景复用原画；原生 UI、动画及本期不适用项分别记录，不要求为每个条目额外生图。

## 图片核对结果与显示限制

AI 实际查看了六张 contact sheet，覆盖全部 46 个裁片，并全尺寸查看边缘问题图及修正后的 K05/K06。记录见 [review.json](../../artifacts/g6-review/review.json)，总览见 [contact sheet](../../artifacts/g6-review/g6_contact_sheet.png)。校园手绘、米白纸纹、鼠尾草绿与暖黄的风格一致，当前可用于 G7 原型。

- 44 个素材原样复制；K05、K06 从 662×662 候选图以内裁坐标 `[8,8,654,654]` 导出 646×646，去掉顶边邻格残线，不缩放。源图与候选图全部保留。
- 所有选定图片均为 **RGB、不透明、带底图**，没有抠图或生成 alpha。G7 应使用插画卡/相框式展示，避免当成透明立绘。
- F03 右手与笔、F04 清单与左手有边缘截断；P01 电脑/前臂贴边。当前按半身肖像使用，避免再次填充裁切。
- A05 便当盒左沿轻微裁切；A01 笔尖及 A07/A11 笔记本边角贴边。单项说明已写入 `review_note`。
- 包装、稿纸和屏幕可能含抽象拟字笔迹；文字、数值和按钮名称由原生 UI 绘制。背景细节较多，文字区应有清楚的底板。

人工确认未提供；实际显示尺寸、文字可读性、交互与动画由 G7 验证。这次图片核对不证明游戏 UI 已通过验收。

## 来源与调用信息

六张源图位于 `assets/g6/sources/G6-01_v1.png` 至 `G6-06_v1.png`，尺寸均为 3840×2160；候选位于 `assets/g6/candidates/`。`selection.json` 保存源图、候选与选定文件的 SHA256、裁切坐标、版本、批次、需求 ID 和内容映射。

外部平台、模型、生成时间、实际提交提示词/参考图及付费调用次数未提供，按 `unknown` 或 `null` 记录。**代理执行生图调用为 0；6 张到手图集不代表外部平台只计费 6 次。** 提示词文件记录的是制作计划，未冒充实际提交记录。

## 制作与证据文件

| 文件 | 用途 |
|---|---|
| [selection.json](selection.json) | 6 个源图批次、46 项选定资源、66 内容映射和 16 项 VIS/ACT 处理方式 |
| [catalog.json](catalog.json)、[资源清单.csv](资源清单.csv) | 制作规划；JSON 行列从 0 开始，CSV 行列从 1 开始 |
| `prompts/high/` | 6 份首选提示词，3840×2160 |
| `prompts/standard/` | 6 份备选提示词，1920×1080 |
| `layouts/` | 6 张 SVG 格位示意，非游戏素材 |
| [批量任务单](../../动作或者图片描述/G6批量生图任务单.md)、[制作规范](../../docs/G6资源制作规范.md) | 制作内容、复用与命名约定；实际状态以本页与 selection 为准 |
| [切图脚本](../../tools/slice_g6_atlas.py) | 离线导出候选 PNG 和 `slicing.json` |
| [AI 核对报告](../../artifacts/g6-review/review.json)、[文件核查](../../artifacts/g6-review/selection-check.json) | 图片观察记录、来源和选定文件一致性证据 |
| [执行记录](../../docs/G6资源准备执行记录.md) | 准备历史、当前核对范围和交接边界 |

## 需要重新切图时

现有切片已完成，无需重复执行。以下命令在项目根目录运行，使用新的输出目录保护已有候选：

```powershell
python -m pip install -r requirements-g6.txt
python tools/slice_g6_atlas.py --catalog assets/g6/catalog.json --batch G6-01 --input assets/g6/sources/G6-01_v1.png --output-dir assets/g6/candidates/G6-01_v1_recrop --variant high --dry-run
```

确认坐标后去掉 `--dry-run`。每批使用独立的新目录；工具拒绝覆盖已有 PNG 或记录。切图不抠图，也不自动认可质量。未来替换素材应保留旧版本，并同步 `selection.json` 的真实路径与 SHA256。

`python tools/prepare_g6_pack.py` 仅重建 catalog、CSV、提示词和格位图，不生图，也不覆盖 selection。当前源图已固定，改变规划前应留存旧 catalog。`artifacts/g6-preparation/check_pack.py` 是准备阶段快照，含“selection 为空”的历史断言，不适用于当前选定阶段；不要用它覆盖当前核对结论。
