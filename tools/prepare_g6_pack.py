"""Build the G6 planning pack; never generates images or edits selected assets."""

from __future__ import annotations

import csv
import hashlib
from html import escape
import io
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "assets/g6"
DESIGN = "docs/交大四年_DDL战争_统一设计文档.md"
STYLE = (
    "现代中国大学校园题材的二维手绘插画，干净深青墨线、柔和水粉铺色、轻微纸张颗粒；"
    "米白、深青、鼠尾草绿为主，少量暖黄与砖红作强调；温暖克制、有生活感。"
    "人物为成年大学生或成年助教，比例自然，服装日常；不同格保持相同画法、光照与完成度。"
    "这是首轮候选风格，尚未人工核图确认。"
)

PORTRAITS = [
    ("P01", "林序·系统拆解者", "短外套、带无字贴纸的电脑；思考中的系统拆解者，手持电脑，专注而略显拘谨", "character"),
    ("P04", "唐以宁·小组协调者", "无字社团工牌、课程便签；手持小组资料的协调者，可靠而亲和", "character"),
    ("F01", "热心室友", "宽松卫衣、双肩包，热心同学护在旁边的姿态", "unit"),
    ("F02", "忙碌学霸", "厚笔记、无字计时表，忙碌但专注的同学", "unit"),
    ("F03", "耐心助教", "文件夹、记号笔，耐心讲解的成年助教", "unit"),
    ("F04", "可靠组长", "无字分工清单，组织协作的可靠同学，手势清楚自然", "unit"),
]

CARDS = [
    ("K01", "写", "一只手用笔在练习纸上书写，整齐的抽象笔迹，没有可读文字"),
    ("K02", "暂时休息", "书桌旁放松的肩膀、舒适靠垫和一杯温水，短暂休息"),
    ("K03", "寻找思路", "数张便签从杂乱变成有序连接，微小灯光象征找到思路，无文字"),
    ("K04", "查资料", "摊开的参考书与电脑检索界面，页面仅抽象线块，无可读文字"),
    ("K05", "细心写", "手持笔仔细核对整齐的练习纸，尺子和清晰的结构线，无文字"),
    ("K06", "潦草急就", "急促书写的手、略歪的纸张与快速笔触，表达赶工，无文字"),
    ("K07", "复盘", "摊开的旧笔记、回看用的圆形箭头与重新整理的便签，无文字"),
    ("K08", "运动", "校园步道上的跑鞋与运动水壶，轻快有活力，不突出特定人物"),
    ("K10", "熬夜", "深夜台灯照亮的电脑与咖啡杯，窗外暗蓝，屏幕无可读文字"),
    ("K12", "转换思路", "两组不同颜色的便签交换位置，分叉路径转向新的方向，无文字"),
    ("K13", "编译", "电脑中的抽象代码线经齿轮转成整齐模块，编程工具意象，无文字"),
    ("K14", "打印Hello", "电脑终端中简短输出化作明亮色块，表达程序成功输出，不画打印机，不写Hello或代码"),
    ("K15", "循环练习", "练习纸与重复的环形箭头、逐步整齐的勾形图案，无文字数字"),
    ("K16", "调试", "放大镜检查电脑屏幕中一个不协调的色块，代码仅抽象线条"),
    ("K19", "版本控制", "三个笔记版本沿分支线汇入一个整齐版本，文件与分支示意，无文字"),
    ("K59", "临时抱佛脚", "一摞重点讲义、沙漏和快速翻页的手，临近截止的紧张复习，无文字数字"),
    ("K60", "检查卷面", "笔尖逐项核对整洁答卷，放大镜和简单勾形标记，无文字数字"),
    ("X01", "分心消息", "手机弹出多个无字通知气泡，让视线离开桌面练习纸，无可读界面"),
]

TASKS = [
    ("N01", "课后习题", "一叠基础习题纸和铅笔，抽象数学图形，无可读题目"),
    ("N02", "英语小作文", "稿纸、钢笔与表达构思的对话泡泡，纸面仅抽象短线，无字母"),
    ("N03", "C语言练习", "笔记本电脑与流程图卡片，屏幕为抽象代码线，无可读程序"),
    ("N04", "实验预习", "实验讲义、简洁仪器和安全护目镜，表达实验准备，无文字"),
    ("Q01", "随堂小测", "单张测验纸、铅笔与小计时器，简洁而稍有紧迫感，无文字数字"),
    ("B01", "大一上·高数期末", "厚数学试卷、几何曲线草图与沙漏，庄重的期末考试意象，无公式文字数字"),
]

RELICS = [
    ("A01", "好用的笔", "一支手感可靠的日常签字笔，单一清楚轮廓"),
    ("A04", "小组通讯录", "小型通讯录与数个头像圆点，无可读姓名或号码"),
    ("A05", "老妈的饭", "装有家常菜的便当盒，温暖朴实"),
    ("A07", "课堂笔记", "夹有彩色标签的课堂笔记本，内页没有可读文字"),
    ("A08", "咖啡杯", "一杯温热咖啡，杯身无标志"),
    ("A11", "计划本", "带空白方格和小勾图形的计划本，无文字日期数字"),
    ("A15", "校园卡", "一张通用校园卡，含抽象头像和图案，无校徽、校名、姓名和号码"),
    ("A18", "室友零食", "一小包分享用的零食，包装无品牌和文字"),
]

BACKGROUNDS = [
    ("campus", "校园公共背景", "大学校园步道、树荫与教学楼，清晨，整体低对比，适合主菜单与地图共用", ["VIS-001", "VIS-004", "VIS-007"]),
    ("classroom", "教室与战斗背景", "空旷但有生活感的大学教室、桌椅与黑板，黑板无文字，适合战斗底图", ["VIS-009", "VIS-013"]),
    ("home", "自家书桌", "暖台灯、木书桌与家常饭，安稳的家中学习角落，主体不贴边", ["VIS-007", "VIS-008", "VIS-013"]),
    ("dorm", "宿舍", "四人宿舍桌面、床帘和公共无字便签，室内略暗但物体清晰，可叠加断电状态", ["VIS-007", "VIS-008", "VIS-013"]),
    ("study", "自习室", "桌椅队列、留白与安静氛围，无字标识；可共用于选课咨询的学习场所底图", ["VIS-007", "VIS-008", "VIS-013"]),
    ("shop", "校园商店", "校园小卖部柜台、文具与便当，商品包装没有品牌与文字，陈列简洁", ["VIS-006"]),
    ("success", "学期完成摘要背景", "阳光照亮已经收好的笔记和书桌，轻松的学期完成氛围，不画成绩或奖状文字", ["VIS-012"]),
    ("failure", "未完成摘要背景", "柔和阴天光线下尚未收好的练习纸与书桌，克制的暂停氛围，不加入惩罚叙事或文字", ["VIS-012"]),
]


def refs(*pairs: tuple[str, str]) -> list[dict]:
    return [{"kind": kind, "id": id_} for kind, id_ in pairs]


def make_pack() -> dict:
    assets = []

    def add(id_: str, label: str, category: str, brief: str, vis: list[str], content: list[dict]) -> str:
        assets.append({
            "id": id_, "label": label, "category": category,
            "brief": brief, "output_name": f"{category}/{id_}_v1.png",
            "requirement_ids": vis, "content_refs": content,
            "status": "planned", "selected_version": None, "selected_file": None,
            "art_direction_status": "candidate_not_reviewed",
            "source": DESIGN if content else "动作或者图片描述/需求台账.md",
        })
        return id_

    portraits = []
    for id_, name, brief, kind in PORTRAITS:
        content = refs((kind, id_))
        if kind == "unit":
            content += refs(("card", {"F01": "K43", "F02": "K44", "F03": "K45", "F04": "K46"}[id_]))
        portraits.append(add(id_, name, "portraits", brief,
                            ["VIS-002", "VIS-005", "VIS-013"] if kind == "character" else ["VIS-005", "VIS-006", "VIS-013"], content))

    cards = [add(id_, name, "cards", brief, ["VIS-002", "VIS-005", "VIS-006", "VIS-008", "VIS-013"], refs(("card", id_)))
             for id_, name, brief in CARDS]
    tasks = [add(id_, name, "tasks", brief, ["VIS-004", "VIS-009", "VIS-013"], refs(("task", id_), ("encounter", id_)))
             for id_, name, brief in TASKS]
    relics = [add(id_, name, "relics", brief, ["VIS-002", "VIS-005", "VIS-006", "VIS-007", "VIS-013"], refs(("relic", id_)))
              for id_, name, brief in RELICS]

    backgrounds = []
    for id_, name, brief, vis in BACKGROUNDS:
        content = []
        if id_ in ["home", "dorm", "study"]:
            scene, card = {"home": ("L01", "K51"), "dorm": ("L02", "K52"), "study": ("L03", "K53")}[id_]
            content = refs(("scene", scene), ("card", card))
        events = {"campus": ["V01", "V10"], "dorm": ["V04"], "study": ["V03"]}.get(id_, [])
        content += refs(*[("event", event) for event in events])
        backgrounds.append(add("BG_" + id_, name, "backgrounds", brief, vis, content))

    def batch(id_: str, title: str, ids: list[str], cols: int, rows: int, ratio: list[int], inset: float, kind: str) -> dict:
        return {
            "id": id_, "title": title, "columns": cols, "rows": rows,
            "variants": {"high": {"width": 3840, "height": 2160}, "standard": {"width": 1920, "height": 1080}},
            "crop": {"inset_ratio": inset, "aspect_ratio": ratio},
            "slots": [{"asset_id": asset, "row": i // cols, "column": i % cols} for i, asset in enumerate(ids)],
            "kind": kind, "status": "prompt_ready_not_generated",
            "source_file_expected": f"sources/{id_}_v1.png",
            "reference_instruction": "G6-01 不要求另付费生成风格图；其余批次附上已选定的 G6-01，后续插画另附已选 G6-02。未经核对的图片不得称为选定参考。",
        }

    batches = [
        batch("G6-01", "六位人物半身像", portraits, 3, 2, [4, 5], 0.04, "portraits"),
        batch("G6-02", "十二张通用与编程牌插画", cards[:12], 4, 3, [1, 1], 0.04, "illustrations"),
        batch("G6-03", "六张牌与六张任务插画", cards[12:] + tasks, 4, 3, [1, 1], 0.04, "illustrations"),
        batch("G6-04", "八件饰品", relics, 4, 2, [1, 1], 0.06, "objects"),
        batch("G6-05", "校园教室自家宿舍背景", backgrounds[:4], 2, 2, [16, 9], 0.02, "backgrounds"),
        batch("G6-06", "自习室商店与摘要背景", backgrounds[4:], 2, 2, [16, 9], 0.02, "backgrounds"),
    ]

    baseline = json.loads((ROOT / "docs/baselines/g0.json").read_text(encoding="utf-8-sig"))
    scope = baseline["scope"]["enabled_by_kind"]
    coverage = []
    for kind, ids in scope.items():
        for id_ in ids:
            found = [asset["id"] for asset in assets if {"kind": kind, "id": id_} in asset["content_refs"]]
            if kind == "status":
                coverage.append({"kind": kind, "id": id_, "method": "vector_or_godot", "asset_ids": [], "status": "planned_G7"})
            elif kind == "ruleset":
                coverage.append({"kind": kind, "id": id_, "method": "no_image_needed", "asset_ids": [], "status": "not_applicable"})
            else:
                if not found:
                    raise ValueError(f"Missing art coverage: {kind}/{id_}")
                coverage.append({"kind": kind, "id": id_, "method": "ai_master_or_reuse", "asset_ids": found, "status": "planned"})
    frozen_pairs = {(kind, id_) for kind, ids in scope.items() for id_ in ids}
    for asset in assets:
        for ref in asset["content_refs"]:
            if (ref["kind"], ref["id"]) not in frozen_pairs:
                raise ValueError(f"Out-of-scope content reference: {ref}")
    assigned = [slot["asset_id"] for item in batches for slot in item["slots"]]
    if len(assigned) != len(set(assigned)) or set(assigned) != {asset["id"] for asset in assets}:
        raise ValueError("Each master must have exactly one batch slot")
    return {
        "schema_version": 1, "pack_id": "campus_mvp_g6.v1", "prepared_date": "2026-10-15",
        "status": "prepared_not_generated", "generation_calls_executed": 0,
        "platform": {"provider": None, "max_size_user_report": "approximately_4K", "billing": "per_image_or_call", "preferred_variant": "high", "price_per_call": None},
        "budget": {"planned_candidate_sheets": len(batches), "planned_master_images": len(assets), "first_round_sheets": ["G6-01", "G6-02"], "retries_included": False, "note": "每批请求一张图；尺寸、模型与平台实际计费仍须在提交前确认。6次是首次候选计划，不是总费用或成功保证。"},
        "style": {"status": "candidate_not_reviewed", "brief": STYLE, "palette_candidates": ["#F4EEDF", "#243E4A", "#78978E", "#DDA957", "#BD6B64"]},
        "sources": {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in [DESIGN, "docs/baselines/g0.json", "data/manifests/campus_mvp.json"]},
        "assets": assets, "batches": batches, "content_coverage": coverage,
        "non_ai_resources": [
            {"id": "FONT_BODY", "method": "open_source_font", "candidate": "Source Han Sans SC / 思源黑体", "source_url": "https://github.com/adobe-fonts/source-han-sans", "status": "not_downloaded", "license_file": None},
            {"id": "ICONS_COMMON", "method": "open_source_svg_or_godot", "candidate": "Lucide，统一线宽", "source_url": "https://lucide.dev/", "status": "not_downloaded", "license_file": None},
            {"id": "UI_COMPONENTS", "method": "godot_theme_stylebox_G7", "candidate": "按钮、卡框、面板、进度条、选中/禁用/升级状态", "status": "planned_G7"},
            {"id": "STATUS_ICONS", "method": "svg_or_godot_G7", "candidate": "7种状态及资源、节点语义图标", "status": "planned_G7"},
        ],
        "ui_coverage": [
            {"requirement_id": "VIS-001", "asset_ids": ["BG_campus"], "method": "background_plus_native_ui"},
            {"requirement_id": "VIS-002", "asset_ids": ["P01", "P04"], "method": "portraits_plus_reused_cards"},
            {"requirement_id": "VIS-003", "asset_ids": [], "method": "native_ui_no_generated_image"},
            {"requirement_id": "VIS-004", "asset_ids": ["BG_campus"], "method": "background_plus_vector_nodes"},
            {"requirement_id": "VIS-005", "asset_ids": [], "method": "reuse_card_and_relic_images"},
            {"requirement_id": "VIS-006", "asset_ids": ["BG_shop"], "method": "background_plus_reused_inventory"},
            {"requirement_id": "VIS-007", "asset_ids": ["BG_campus", "BG_dorm", "BG_study", "A15"], "method": "reuse_backgrounds; V10 optionally overlays A15 in G7"},
            {"requirement_id": "VIS-008", "asset_ids": ["BG_home", "BG_dorm", "BG_study"], "method": "reuse_backgrounds_and_card_images"},
            {"requirement_id": "VIS-009", "asset_ids": ["BG_classroom"], "method": "reuse_battle_background"},
            {"requirement_id": "VIS-010", "asset_ids": [], "method": "not_applicable_MVP"},
            {"requirement_id": "VIS-011", "asset_ids": [], "method": "not_applicable_MVP"},
            {"requirement_id": "VIS-012", "asset_ids": ["BG_success", "BG_failure"], "method": "background_plus_native_summary"},
            {"requirement_id": "VIS-013", "asset_ids": ["BG_classroom"], "method": "reuse_all_battle_content_plus_native_ui"},
            *[{"requirement_id": id_, "asset_ids": [], "method": "G7_native_interaction_or_animation_no_sprite_sequence_planned"} for id_ in ["ACT-001", "ACT-002", "ACT-003"]],
        ],
        "reuse_policy": ["所有升级牌沿用基础原画，升级和费用由G7界面叠加", "K43-K46复用F01-F04", "K51-K53复用L01-L03背景", "task与同ID encounter共图", "B01三个阶段共用一张原画，阶段信息由UI展示", "事件复用校园、宿舍、自习室背景；V10可叠校园卡", "不生成整页UI、文字、按钮状态或逐帧动画"],
    }


def crop_dimensions(batch: dict, variant: str) -> tuple[int, int]:
    size = batch["variants"][variant]
    cw, ch = size["width"] // batch["columns"], size["height"] // batch["rows"]
    inset = batch["crop"]["inset_ratio"]
    width, height = cw - 2 * math.ceil(cw * inset), ch - 2 * math.ceil(ch * inset)
    rw, rh = batch["crop"]["aspect_ratio"]
    if width * rh > height * rw:
        width = height * rw // rh
    else:
        height = width * rh // rw
    return width, height


def prompt_for(pack: dict, batch: dict, variant: str) -> str:
    size = batch["variants"][variant]
    inset = batch["crop"]["inset_ratio"]
    aspect = batch["crop"]["aspect_ratio"]
    crop_width, crop_height = crop_dimensions(batch, variant)
    index = {asset["id"]: asset for asset in pack["assets"]}
    instructions = [
        f"批次 {batch['id']}：{batch['title']}。本次只生成一张图片，包含全部指定格位。",
        f"输出尺寸 {size['width']}×{size['height']} 像素，{batch['columns']} 列 × {batch['rows']} 行的严格等分矩形网格；从左到右、从上到下排列。",
        STYLE,
        "各格是可独立裁切的游戏素材。格位编号、内容ID和名称仅用于理解指令，绝不印在画面上。",
        "各格没有额外标题条、外框、边线或格间距。素材不得跨格、遮住相邻格或合并场景；所有格都必须生成，不能自行换序。",
        f"每格四周各留至少 {inset:.0%} 的安全区。中央主体须适合裁为 {aspect[0]}:{aspect[1]}，不能把头、手或关键物件放在边缘。",
        f"每格最终只保留正中央约 {crop_width}×{crop_height} 像素；所有关键主体必须完整落在这个中央裁切框内，并在框内再留少量呼吸空间。框外只放可舍弃背景，裁切框本身不要画出来。",
        "全图无可读文字、字母、数字、费用、说明、卡框、按钮、品牌、校徽和水印。抽象短线、几何图形允许出现。",
    ]
    if batch["kind"] == "portraits":
        instructions.append("每格恰好一位独立的半身人物，正面或轻微侧身、视线水平；头顶至腰部完整，主要手势与道具位于中央较窄区域；背景统一浅米白。发型等未冻结细节可提出候选，但同一人物后续必须沿用选定参考。")
    elif batch["kind"] == "objects":
        instructions.append("每格一个完整的独立物件，大小统一、轮廓清楚；使用统一浅米白纯色背景，不画桌面或大场景。若平台明确支持真实alpha，可输出透明背景；否则保持浅米白，禁止画棋盘格冒充透明。")
    elif batch["kind"] == "backgrounds":
        instructions.append("每格是一幅完整的横向16:9环境插画，主体不贴边，保留可叠加信息的低细节区域；不预画任何界面布局。视角和色调统一，避免强烈高对比纹理。")
    else:
        instructions.append("每格一幅独立的方形主题插画，主体集中在中部，避免辨识度依赖小字、密集细节或不同角色的脸；没有装饰卡框。任务也用校园学习物件意象，不画怪物。")
    if batch["id"] != "G6-01":
        instructions.append("参考图使用说明：附已人工选定的G6-01作为统一画风参考；若已有选定的G6-02，另附作为插画画法参考。只借用画风与已定义人物外观，不把参考图内容复制进所有格。没有参考图时先沿用上述文字规格，仍须人工核对。")
    instructions += ["", "逐格内容："]
    for slot in batch["slots"]:
        asset = index[slot["asset_id"]]
        instructions.append(f"第{slot['row'] + 1}行第{slot['column'] + 1}列（{asset['id']}，{asset['label']}）：{asset['brief']}。")
    instructions += ["", "最终检查：数量与顺序正确；没有串格或文字；所有格均为独立可裁切素材；未遗漏、复制替代或新增主体。"]
    if variant == "standard":
        instructions.append("这是低分辨率备选：减少细小纹理、优先主体轮廓；结果主要用于试样或小尺寸显示，不承诺满足放大展示。")
    return "\n".join(instructions) + "\n"


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def main() -> None:
    pack = make_pack()
    write_text(DEST / "catalog.json", json.dumps(pack, ensure_ascii=False, indent=2) + "\n")
    index = {asset["id"]: asset for asset in pack["assets"]}
    for batch in pack["batches"]:
        for variant in ["high", "standard"]:
            write_text(DEST / "prompts" / variant / f"{batch['id']}.txt", prompt_for(pack, batch, variant))
        # SVGs are slot guides only, never candidate art or image-generation evidence.
        width, height = 960, 540
        cw, ch = width / batch["columns"], height / batch["rows"]
        labels = []
        crop_width, crop_height = crop_dimensions(batch, "high")
        guide_width, guide_height = crop_width / 4, crop_height / 4
        for slot in batch["slots"]:
            asset = index[slot["asset_id"]]
            x, y = slot["column"] * cw, slot["row"] * ch
            labels.append(f'<rect x="{x:g}" y="{y:g}" width="{cw:g}" height="{ch:g}" fill="#f4eedf" stroke="#243e4a"/>')
            labels.append(f'<rect x="{x + (cw - guide_width) / 2:g}" y="{y + (ch - guide_height) / 2:g}" width="{guide_width:g}" height="{guide_height:g}" fill="none" stroke="#78978e" stroke-dasharray="5 4"/>')
            labels.append(f'<text x="{x + cw / 2:g}" y="{y + ch / 2 - 10:g}" text-anchor="middle" font-size="22">{escape(asset["id"])}</text>')
            labels.append(f'<text x="{x + cw / 2:g}" y="{y + ch / 2 + 20:g}" text-anchor="middle" font-size="17">{escape(asset["label"])}</text>')
        write_text(DEST / "layouts" / f"{batch['id']}.svg", '<svg xmlns="http://www.w3.org/2000/svg" width="960" height="540" viewBox="0 0 960 540"><g font-family="Microsoft YaHei,sans-serif" fill="#243e4a">' + "".join(labels) + "</g></svg>\n")
    output = io.StringIO(newline="")
    writer = csv.writer(output)
    writer.writerow(["asset_id", "label", "batch", "row_1based", "column_1based", "planned_output", "content_refs", "requirement_ids", "status"])
    for batch in pack["batches"]:
        for slot in batch["slots"]:
            asset = index[slot["asset_id"]]
            writer.writerow([asset["id"], asset["label"], batch["id"], slot["row"] + 1, slot["column"] + 1, asset["output_name"], ";".join(f'{r["kind"]}/{r["id"]}' for r in asset["content_refs"]), ";".join(asset["requirement_ids"]), asset["status"]])
    path = DEST / "资源清单.csv"
    path.write_bytes(b"\xef\xbb\xbf" + output.getvalue().encode("utf-8"))
    print(f"Prepared {len(pack['assets'])} masters in {len(pack['batches'])} candidate sheets")
    print(f"Frozen content coverage: {len(pack['content_coverage'])}; actual image-generation calls: 0")
    print("High prompts: assets/g6/prompts/high/; slot guides: assets/g6/layouts/")


if __name__ == "__main__":
    main()
