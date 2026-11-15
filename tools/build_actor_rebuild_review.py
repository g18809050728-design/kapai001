"""Compare P03 V9/V10 using engine captures and retain the other selected figures."""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

import build_actor_proportions_review as base

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-rebuild-20261115"
OLD = ROOT / "artifacts/verification/actor-proportions-20261115"
OUT = EV / "review"
base.OUT = OUT


def comparisons():
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 27)
    figures = []
    for file, crop, caption in (
        ("p03-before-after.jpg", None, "完整站姿：从新立绘重建全部沈见章组件"),
        ("neck-before-after.jpg", (400, 140, 800, 620), "头颈近景：同源头颈、肩胸与衣领"),
    ):
        board = Image.new("RGB", (1200, 780), "#e6dfd1")
        draw = ImageDraw.Draw(board)
        for col, (version, label) in enumerate((("v9", "V9 · 已否决旧组件"), ("v10", "V10 · 整套重新生成"))):
            image = Image.open(EV / "poses-final" / (version + "-neutral.png")).convert("RGB")
            if crop:
                image = image.crop(crop)
            image = image.resize((600, 720 if crop else 700), Image.Resampling.LANCZOS)
            board.paste(image, (col * 600, 55))
            draw.text((col * 600 + 165, 10), label, font=font, fill="#243842")
        board.save(OUT / file, quality=97)
        figures.append(f'<figure><a href="{file}"><img src="{file}" alt="{caption}"></a><figcaption>{caption}。左 V9（用户已否决），右 V10（本轮重制）。</figcaption></figure>')
    return "".join(figures)


def inspection_sheets():
    folder = EV / "p03-final"
    report = base.read(folder / "report.json")
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 20)
    records = []
    for sequence in ("fullbody-action-x1", "fullbody-hit-x1"):
        frames = [f for f in report["fullbody_frames"] if f["sequence"] == sequence]
        full = Image.new("RGB", (1400, 1740), "#e6dfd1")
        close = Image.new("RGB", (1800, 2060), "#e6dfd1")
        selected = []
        for i in range(16):
            frame = frames[round(i * (len(frames) - 1) / 15)]
            image = Image.open(folder / frame["file"]).convert("RGB")
            small = image.resize((343, 400), Image.Resampling.LANCZOS)
            x, y = i % 4 * 350, i // 4 * 435
            full.paste(small, (x, y + 32))
            ImageDraw.Draw(full).text((x + 100, y + 4), str(frame["elapsed_ms"]) + " ms", font=font, fill="#263943")
            neck = image.crop((390, 150, 840, 630))
            x, y = i % 4 * 450, i // 4 * 515
            close.paste(neck, (x, y + 33))
            ImageDraw.Draw(close).text((x + 135, y + 4), str(frame["elapsed_ms"]) + " ms", font=font, fill="#263943")
            selected.append({"file": (folder / frame["file"]).relative_to(ROOT).as_posix(), "ms": frame["elapsed_ms"]})
        full_file = EV / ("p03-" + sequence + "-inspection.jpg")
        neck_file = EV / ("p03-neck-" + sequence + "-inspection.jpg")
        full.save(full_file, quality=96)
        close.save(neck_file, quality=97)
        records.append({"sequence": sequence, "full_sheet": full_file.relative_to(ROOT).as_posix(),
                        "neck_sheet": neck_file.relative_to(ROOT).as_posix(), "samples": selected})
    (EV / "inspection-sheets.json").write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    inputs, versions = {}, {}
    for version in ("v10", "v9"):
        versions[version] = {}
        for role in base.NAMES:
            family = EV if version == "v10" and role == "P03" else ROOT / "artifacts/verification/actor-posture-20261115" if role == "P03" else OLD
            folder = family / (role.lower() + "-final")
            record = base.collect(folder, role, inputs)
            record["captured_this_revision"] = version == "v10" and role == "P03"
            versions[version][role] = record
    comparison = comparisons()
    inspection_sheets()
    lineup = Image.new("RGB", (1800, 840), "#e6dfd1")
    draw = ImageDraw.Draw(lineup)
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 27)
    for col, role in enumerate(base.NAMES):
        image = Image.open((OUT / versions["v10"][role]["poses"]["neutral"]).resolve()).convert("RGB")
        image.thumbnail((590, 765))
        lineup.paste(image, (col * 600 + (600 - image.width) // 2, 48))
        draw.text((col * 600 + 160, 10), base.NAMES[role] + (" V10" if role == "P03" else " V8"), font=font, fill="#243842")
    lineup.save(OUT / "lineup.jpg", quality=96)
    cards = "".join(f'<button class="character-card" type="button" data-role="{role}" aria-pressed="{str(role == "P03").lower()}" aria-label="查看{name}完整人物与动作"><img src="{versions["v10"][role]["poses"]["neutral"]}" alt="{name}当前完整站姿"><strong>{name}</strong><span>{base.PROPS[role]}</span></button>' for role, name in base.NAMES.items())
    page = (ROOT / "tools/actor_party_review.html").read_text(encoding="utf-8")
    replacements = {
        "三位主角制作 · 2026-11-15": "沈见章整套组件重制 · 2026-11-15 · V10",
        "<h1>许知微、沈见章与唐以宁</h1>": "<h1>沈见章 · 整套组件重新生成</h1>",
        "先看完整人物，再看连续动作。三人保留各自的服装、发型与持物，使用独立关节和动作节奏。下方图片和连续帧均来自本轮 Godot 实际渲染。": "重新绘制完整人物，以同源立绘制作头颈、肩胸、袖片、表情和持物组件，并重新注册身体与双腿。可切换 V10 和已被否决的 V9 对比。许知微、唐以宁保留 V8，林序保留原版 V5；两位未改角色的画面与动作沿用已核对的 V8 实渲。",
        '<a href="#motion">连续动作</a>': '<a href="#comparison">前后对照</a><a href="#motion">连续动作</a>',
        '<section id="motion">': '<section id="comparison"><h2>沈见章 · 同尺度前后对照</h2><p class="muted small">同一 Godot 画布、同一采样姿态、同一缩放与脚底基线。点击可看大图。</p><div class="grid">' + comparison + '</div></section>\n<section id="motion">',
        '<label>角色<select': '<label>版本<select id="version"><option value="v10">本轮整套重制 V10</option><option value="v9">已否决旧组件 V9</option></select></label>\n<label>角色<select',
        "docs/plans/2026-11-15-actor-party-design.md": "docs/plans/2026-11-15-actor-rebuild-design.md",
        "本次完成三位主角，其他敌怪与全量资源仍按原计划推进。": "本轮重新生成沈见章整套组件；其余角色保留已选形象。美术最终验收由用户查看后决定。",
        "const data=JSON.parse": "const versions=JSON.parse",
        "let role='P02'": "let version='v10',data=versions[version];\nlet role='P03'",
        "d.name+' · 连续动作'": "d.name+' · '+(version==='v10'?'整套重制 V10':'已否决 V9')+' · 连续动作'",
        "for(const button of document.querySelectorAll('.character-card'))button.setAttribute('aria-pressed',String(button.dataset.role===role));": "for(const button of document.querySelectorAll('.character-card')){button.setAttribute('aria-pressed',String(button.dataset.role===role));button.querySelector('img').src=data[button.dataset.role].poses.neutral;}",
        "-Character ${role}`": "-Character ${role} -Version ${version.toUpperCase()}`",
        "$('character').onchange=": "$('version').onchange=()=>{version=$('version').value;data=versions[version];chooseRole(role)};\n$('character').onchange=",
    }
    for old, new in replacements.items():
        assert old in page, old
        page = page.replace(old, new)
    for token, value in {"__DATA__": json.dumps(versions, ensure_ascii=False).replace("</", "<\\/"), "__ROSTER__": cards, "__BATCH__": "9", "__TOTAL__": "38"}.items():
        assert token in page, token
        page = page.replace(token, value)
    (OUT / "index.html").write_text(page, encoding="utf-8")
    for path in list(OUT.glob("*.jpg")) + list((EV / "poses-final").glob("*.png")):
        inputs[path.relative_to(ROOT).as_posix()] = base.sha(path)
    manifest = {"all_media_are_real_godot_captures": True, "versions": ["v10", "v9"], "default_character": "P03",
                "captures_reused": {"P02": "V8", "P04": "V8", "v9_comparison": "V9 rejected historical captures"},
                "inputs": inputs, "api_successful_this_revision": 9, "api_successful_cumulative": 38,
                "user_final_visual_acceptance": "pending"}
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"review": str(OUT / "index.html"), "exact_media_and_reports": len(inputs)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
