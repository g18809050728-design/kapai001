"""One-off G7 progress reconciliation; does not change frozen sources or gameplay."""
from pathlib import Path
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "artifacts/verification/g7-20261015-190810-503786"
changes = {}


def replace(path, old, new):
    text = changes.get(path, (ROOT / path).read_text(encoding="utf-8-sig"))
    if old not in text:
        raise ValueError(f"Missing expected text in {path}: {old[:100]}")
    changes[path] = text.replace(old, new)


plan = "实施计划与验收基线.md"
replace(plan, "版本：v1.8", "版本：v1.9")
replace(plan, "G7 本地界面实施中", "G7 本期界面已通过")
replace(plan, "G6 已完成本地资源交接，当前 G7 补全视觉/动作设计并实现 UI，最后 G8 进行完整用户路径与发布验收。", "G6 已完成本地资源交接，G7 本期视觉/动作设计及 UI 出口已通过，下一阶段 G8 进行完整生产用户路径与发布验收。")
replace(plan, "G7 UI 与剩余交付补全（当前实施）", "G7 UI 与剩余交付补全（本期已通过）")
replace(plan, "G7 设计见[界面与交互设计]", "G7 正式证据为 `artifacts/verification/g7-20261015-190810-503786/`：6 项功能检查、真实按钮六节点 fixture 路线、生产 K03 待选、动画开关完整状态/RNG 对照及 7 张渲染截图通过；设计见[界面与交互设计]")
replace(plan, "原有流程/存储验收不代表生产玩法、平衡或性能已通过", "流程/存储/UI 验收不代表完整生产玩法、平衡或性能已通过")

readme = "README.md"
replace(readme, "当前 G7 本地界面实施中、待验证", "G7 本期界面出口已通过，下一阶段为 G8")
replace(readme, "G7 尚未通过，完整生产玩法、平衡和可见用户路径尚未验收。", "启动已有可见菜单与局内页面；G7 的 fixture 六节点按钮路线与生产战斗待选已实测，完整生产用户路径、平衡、性能和发布打包留 G8。")
replace(readme, "本地 UI 正在实现和验证。", "本地 UI 已实现并通过 G7 出口。")
replace(readme, "& $env:GODOT_BIN --headless --path . --editor --quit\n& $env:GODOT_BIN --headless --path . --script res://tests/run_ui_tests.gd", "python tools/verify_g7.py --godot $env:GODOT_BIN")
replace(readme, "上面的命令是运行入口，不代表测试已经通过；实际退出码、日志、覆盖范围和剩余问题统一记录在[G7执行记录](docs/G7界面执行记录.md)。", "正式通过证据为 `artifacts/verification/g7-20261015-190810-503786/`，6 项功能检查与 7 张真实渲染截图已核对；覆盖范围和剩余问题见[G7执行记录](docs/G7界面执行记录.md)。")
replace(readme, "G7 页面、交互和事件表现已进入代码实施及验证，尚未通过阶段出口", "G7 页面冒烟、命令交接、待选保存策略及动画开关一致性已通过阶段出口")

tracking = "docs/G0需求追踪.md"
replace(tracking, "G6 制作包准备完成，待图片生成与资源核对", "G6 的 46 张选定素材已交接，G7 本期界面出口已通过，G8 未开始")
text = changes[tracking]
cells = {
    "ARCH-001": "G7 UI 依赖扫描无规则引擎/存储/私有状态命中；真实按钮只经 GameSession 提交，见 [G7记录](G7界面执行记录.md)",
    "BAT-001": "G3 隔离规则矩阵通过；G7 生产 P01 seed=0 的 K03 待选及结束回合动画开/关完整状态与 RNG 一致，见 [G7记录](G7界面执行记录.md)；生产行为缺口见 G2 记录",
    "UI-001": "G7 本期页面冒烟、稳定 UID、preview 门控、不可用原因及待选锁定通过；服务非法请求拒绝沿用 G3–G5 证据，见 [G7记录](G7界面执行记录.md)",
    "UI-DOC-001": "G0 文字登记已核查；G6 46 张选定素材映射 66 内容与 16 个 VIS/ACT 处理方式；G7 详细设计、实现、按钮测试及截图已对应，VIS-010/011 不适用；见 [G6记录](G6资源准备执行记录.md)、[G7记录](G7界面执行记录.md)。人工视觉和来源许可待 G8 发布前补齐",
}
lines = text.splitlines()
for i, line in enumerate(lines):
    for requirement, evidence in cells.items():
        if line.startswith(f"| {requirement} |"):
            columns = line.split("|")
            columns[-2] = " " + evidence + " "
            lines[i] = "|".join(columns)
changes[tracking] = "\n".join(lines) + "\n"
replace(tracking, "可见提示留 G7", "G7 已实现并复核三步提示映射，摘要保存/重复保存真实按钮通过；本轮未重复六种可见故障注入，见 [G7记录](G7界面执行记录.md)")
replace(tracking, "视觉细节留待 G7，不以“详细记录待创建”判为当前缺口。", "G6 选定资源及 G7 详细设计、实现与实测证据已逐项关联，VIS-010/011 明确本期不适用。")
replace(tracking, "当前 G6 准备中，制作包与离线工具见[G6记录](G6资源准备执行记录.md)；图片、G7 UI/动画和 G8 生产完整路径、性能与打包尚未验证。", "G6 资源选定及 AI 视觉核对见[G6记录](G6资源准备执行记录.md)；G7 页面、真实按钮、待选、动画 A/B 及可见截图通过，见[G7记录](G7界面执行记录.md)。G8 生产完整路径、性能、平衡与打包尚未验证，人工视觉签收及来源许可待发布前补齐。")

ledger = "动作或者图片描述/需求台账.md"
replace(ledger, "G7 本期条目已有代码实现，当前统一标为 **已实现，待验证**。", "G7 本期条目的页面冒烟及核心交互已通过，当前标为 **已验证（G7 范围）**。")
replace(ledger, "G7 尚未通过，实际测试结果与剩余问题以", "逐项实际覆盖及留待 G8 的分支以")
text = changes[ledger]
lines = text.splitlines()
for i, line in enumerate(lines):
    if line.startswith(("| VIS-", "| ACT-")):
        lines[i] = line.replace("已实现，待验证", "[已验证（G7 范围）](../docs/G7界面执行记录.md)")
changes[ledger] = "\n".join(lines) + "\n"
replace(ledger, "“已实现，待验证”只表示对应代码已落盘，不表示每项验收已经通过。后续通过项应链接实际运行证据并保留未通过项；", "“已验证（G7 范围）”对应执行记录中的实际输入及结果，不表示生产内容、可见故障或极端分支已穷举；这些边界随 G8 继续验证。")

ui_readme = "动作或者图片描述/README.md"
replace(ui_readme, "已实施项待实际验证，G7 尚未通过。", "本期界面出口已通过，逐项覆盖及剩余边界见执行记录。")
replace(ui_readme, "当前本期条目标为“已实现，待验证”", "当前本期条目标为“已验证（G7 范围）”")
replace(ui_readme, "G7 实测结果由执行记录补入，当前不声称 G7 已通过。", "G7 实测结果已记入执行记录，生产完整用户路径、性能和发布打包留 G8。")

spec = "动作或者图片描述/G7界面与交互设计.md"
replace(spec, "主体区滚动，提示区常驻，按钮支持键盘焦点及悬停原因。", "主体区滚动，提示区常驻，按钮支持键盘焦点及悬停原因。战斗去掉顶部大插画，资源栏与两行操作置顶；任务/单位与选择/状态分别使用 190 高独立滚动列，手牌区高 220 并横向滚动，保障 960×640 下核心操作可见。卡面以 15 号文字并列显示专注与精力代价，零值照常显示；效果两行、悬停查看全文。")
replace(spec, "按 run_id/revision/index 去重。", "按 run_id/revision/index 去重；来源/目标文字取同批日志标签快照，不显示内部实例编号。")

contract = "docs/界面层契约.md"
replace(contract, "当前只按[UI 图片与动作需求](../动作或者图片描述/README.md)登记战斗画面、状态变体、出牌选目标、待选确认和事件演出的需求；见[需求台账](../动作或者图片描述/需求台账.md)的 `VIS-013`、`ACT-002`、`ACT-003`。不在 G0–G5 制作战斗 UI 或决定分镜时长。G6 核对所需 AI 图片后，G7 实施前再补齐事件类型、前后画面、顺序、时序、关闭/加速表现和异常反馈，并将记录推进到“设计已确认”。表现回调不得推进规则；实施后按记录与动画不变性测试双重验收。", "战斗画面、交互和事件表现已关联[需求台账](../动作或者图片描述/需求台账.md)中的 `VIS-013`、`ACT-002`、`ACT-003`，具体布局、事件提示、时序、关闭/加速表现和异常反馈见[G7 详细设计](../动作或者图片描述/G7界面与交互设计.md)。G0–G5 仅登记需求，G6 资源交接后才实施 G7；实际页面测试、生产 K03 待选、动画开关一致性及截图证据见[G7 记录](G7界面执行记录.md)。表现回调不得推进规则。")
replace(contract, "具体位置、颜色、字号及零值呈现留待 G7 视觉设计确认", "位置、颜色、字号及零值呈现见[G7 详细设计](../动作或者图片描述/G7界面与交互设计.md)")
replace(contract, "### 15.8 验收场景（建议测试名）", "### 15.8 实际验收入口")
replace(contract, "覆盖待选锁、非法确认、目标选择与取消、单位槽换班及动画不变性。", "覆盖生产 K03 待选锁与确认、K14 目标预选与取消、公开牌堆、非出牌 preview 及动画不变性。单位槽换班等未在本轮生产 UI 用例逐项穷举，规则层覆盖见 G3。")
replace(contract, "测试使用锁定 Godot 版本的 headless 入口；启动命令和实际结果在工程建立后登记到 README。", "测试使用锁定 Godot 版本的 headless 入口；启动命令见 README，实际通过结果与覆盖边界见[G7 记录](G7界面执行记录.md)。")

batch = "动作或者图片描述/G6批量生图任务单.md"
replace(batch, "本任务单完成不代表 G6 通过。退出仍需要实际图片、人工核对和选定版本映射；G7 UI 尚未开始。", "本任务单保留为生图排程的历史输入。当前 6 张源图与 46 张选定切片已交接，见[G6 记录](../docs/G6资源准备执行记录.md)；G7 本期 UI 出口已通过，见[G7 记录](../docs/G7界面执行记录.md)。最终人工视觉签收和来源许可仍须在 G8 发布前补齐，不以任务单、AI 核图或 UI 通过替代。")

for path, text in changes.items():
    (ROOT / path).write_text(text, encoding="utf-8")

pattern = r"BattleEngine|RunService|SaveStore|FileAccess|\.catalog|\._state|\._battle_engine|\._run_service|\._save_store"
argv = ["rg", "-n", pattern, "src/ui"]
result = subprocess.run(argv, cwd=ROOT, capture_output=True)
(EVIDENCE / "boundary-review.stdout.txt").write_bytes(result.stdout)
(EVIDENCE / "boundary-review.stderr.txt").write_bytes(result.stderr)
boundary = {"command": argv, "exit_code": result.returncode,
            "no_forbidden_dependency_matches": result.returncode == 1,
            "scope": "Text dependency scan plus UI button integration tests; not a complete static type proof"}
(EVIDENCE / "boundary-review.json").write_text(json.dumps(boundary, indent=2), encoding="utf-8")
assert result.returncode == 1, "Unexpected dependency matches or rg failure"
visual = EVIDENCE / "visual"
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
capture = json.loads((visual / "capture.json").read_text(encoding="utf-8"))
assert len(capture["screens"]) == 7 and all(item["save_error"] == 0 for item in capture["screens"])
review = {
    "reviewer": "AI", "human_signoff": False, "status": "reviewed",
    "command": [r"F:\GoDot\Godot_v4.7.2-stable_win64_console.exe", "--path", ".", "--script",
                "res://tools/capture_g7.gd", "--", "--output=res://" + visual.relative_to(ROOT).as_posix()],
    "capture_exit_code": int((EVIDENCE / "visual_capture.exit_code.txt").read_text(encoding="utf-8-sig")),
    "capture_script_sha256": sha(ROOT / "tools/capture_g7.gd"),
    "screenshots": {p.name: sha(p) for p in sorted(visual.glob("*.png"))},
    "observations": ["Chinese text renders correctly", "Core battle controls and hand visible at 1280x800 and 960x640",
                     "Choice and tasks scroll independently", "Setup and map scroll vertically",
                     "Choice locks non-choice controls", "Event text uses label snapshots"],
    "scope_note": "7 engine-rendered screens reviewed; not a complete production user-path or human art signoff",
}
(visual / "review.json").write_text(json.dumps(review, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"Updated {len(changes)} progress documents; recorded boundary scan and 7 screenshot reviews.")
