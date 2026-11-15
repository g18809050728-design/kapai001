"""Review actual V8/V11 P04 motion captures alongside the retained selected cast."""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

import build_actor_proportions_review as base

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-motion-20261115"
OUT = EV / "review"
base.OUT = OUT


def comparisons():
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 27)
    figures = []
    for file, crop, caption in (
        ("p04-action-before-after.jpg", None, "出手全身：肩肘联动与承重前后对照"),
        ("p04-shoulder-before-after.jpg", (430, 340, 930, 800), "肩袖与手臂：肩头保持连接，肘部向前展开"),
    ):
        board = Image.new("RGB", (1200, 780), "#e6dfd1")
        draw = ImageDraw.Draw(board)
        for col, (version, label) in enumerate((("v8", "V8 · 原动作"), ("v11", "V11 · 动作修正"))):
            image = Image.open(EV / "poses-final" / (version + "-action.png")).convert("RGB")
            if crop:
                image = image.crop(crop)
            image.thumbnail((600, 700), Image.Resampling.LANCZOS)
            board.paste(image, (col * 600 + (600 - image.width) // 2, 60))
            draw.text((col * 600 + 160, 12), label, font=font, fill="#243842")
        board.save(OUT / file, quality=97)
        figures.append(f'<figure><a href="{file}"><img src="{file}" alt="{caption}"></a><figcaption>{caption}。同一画布与42%动作时刻，左 V8、右 V11。</figcaption></figure>')
    return "".join(figures)


def inspection_sheets():
    folder = EV / "p04-final-02"
    report = base.read(folder / "report.json")
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 20)
    records = []
    for sequence in ("fullbody-action-x1", "fullbody-hit-x1"):
        frames = [f for f in report["fullbody_frames"] if f["sequence"] == sequence]
        full = Image.new("RGB", (1400, 1740), "#e6dfd1")
        close = Image.new("RGB", (1800, 1740), "#e6dfd1")
        selected = []
        for i in range(16):
            frame = frames[round(i * (len(frames) - 1) / 15)]
            image = Image.open(folder / frame["file"]).convert("RGB")
            small = image.resize((343, 400), Image.Resampling.LANCZOS)
            x, y = i % 4 * 350, i // 4 * 435
            full.paste(small, (x, y + 32))
            ImageDraw.Draw(full).text((x + 100, y + 4), str(frame["elapsed_ms"]) + " ms", font=font, fill="#263943")
            upper = image.crop((430, 350, 880, 750))
            x, y = i % 4 * 450, i // 4 * 435
            close.paste(upper, (x, y + 33))
            ImageDraw.Draw(close).text((x + 135, y + 4), str(frame["elapsed_ms"]) + " ms", font=font, fill="#263943")
            selected.append({"file": (folder / frame["file"]).relative_to(ROOT).as_posix(), "ms": frame["elapsed_ms"]})
        full_file = EV / ("p04-" + sequence + "-inspection.jpg")
        close_file = EV / ("p04-upper-" + sequence + "-inspection.jpg")
        full.save(full_file, quality=96)
        close.save(close_file, quality=97)
        records.append({"sequence": sequence, "full_sheet": full_file.relative_to(ROOT).as_posix(),
                        "upper_sheet": close_file.relative_to(ROOT).as_posix(), "samples": selected})
    (EV / "inspection-sheets.json").write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    inputs, versions = {}, {}
    for version in ("v11", "v8"):
        versions[version] = {}
        for role in base.NAMES:
            family = EV if version == "v11" and role == "P04" else ROOT / "artifacts/verification/actor-rebuild-20261115" if role == "P03" else ROOT / "artifacts/verification/actor-proportions-20261115"
            capture_name = "p04-final-02" if family == EV else role.lower() + "-final"
            record = base.collect(family / capture_name, role, inputs)
            record["captured_this_revision"] = version == "v11" and role == "P04"
            versions[version][role] = record
    comparison = comparisons()
    inspection_sheets()
    lineup = Image.new("RGB", (1800, 840), "#e6dfd1")
    draw = ImageDraw.Draw(lineup)
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 27)
    for col, role in enumerate(base.NAMES):
        image = Image.open((OUT / versions["v11"][role]["poses"]["neutral"]).resolve()).convert("RGB")
        image.thumbnail((590, 765))
        lineup.paste(image, (col * 600 + (600 - image.width) // 2, 48))
        label = {"P02": " V8", "P03": " V10", "P04": " V11"}[role]
        draw.text((col * 600 + 160, 10), base.NAMES[role] + label, font=font, fill="#243842")
    lineup.save(OUT / "lineup.jpg", quality=96)
    cards = "".join(f'<button class="character-card" type="button" data-role="{role}" aria-pressed="{str(role == "P04").lower()}" aria-label="查看{name}完整人物与动作"><img src="{versions["v11"][role]["poses"]["neutral"]}" alt="{name}当前完整站姿"><strong>{name}</strong><span>{base.PROPS[role]}</span></button>' for role, name in base.NAMES.items())
    page = (ROOT / "tools/actor_party_review.html").read_text(encoding="utf-8")
    replacements = {
        "三位主角制作 · 2026-11-15 · 以林序 V5 为形体与动作基准": "唐以宁动作修正 · 2026-11-15 · V11",
        "<h1>许知微、沈见章与唐以宁</h1>": "<h1>唐以宁 · 肩肘、持板与重心动作修正</h1>",
        "先看完整人物，再看连续动作。三人保留各自的服装、发型与持物，使用独立关节和动作节奏。下方图片和连续帧均来自本轮 Godot 实际渲染。": "保留唐以宁V8形象和比例，修正肩袖整片翘起、过量抬肩、双膝一起折弯及持板晃动。先看前后对照，再慢放连续动作。沈见章保留V10、许知微保留V8、林序保留原V5；两位未改角色沿用对应版本的实际截图。",
        '<a href="#motion">连续动作</a>': '<a href="#comparison">动作前后对照</a><a href="#motion">连续动作</a>',
        '<section id="motion">': '<section id="comparison"><h2>唐以宁 · 同尺度出手对照</h2><p class="muted small">同一Godot画布、采样姿态、缩放与脚底基线。点击查看大图。</p><div class="grid">' + comparison + '</div></section>\n<section id="motion">',
        '<label>角色<select': '<label>唐的动作<select id="version"><option value="v11">本轮修正 V11</option><option value="v8">原动作 V8</option></select></label>\n<label>角色<select',
        "docs/plans/2026-11-15-actor-party-design.md": "docs/plans/2026-11-15-actor-motion-design.md",
        "本次完成三位主角，其他敌怪与全量资源仍按原计划推进。": "本轮只修正唐以宁动作；其他角色保持已选版本。动作自然度仍请查看慢放后判断。",
        "const data=JSON.parse": "const versions=JSON.parse",
        "let role='P02'": "let version='v11',data=versions[version];\nlet role='P04'",
        "d.name+' · 连续动作'": "d.name+' · '+(role==='P04'?(version==='v11'?'动作修正 V11':'原动作 V8'):role==='P03'?'保留 V10':'保留 V8')+' · 连续动作'",
        "for(const button of document.querySelectorAll('.character-card'))button.setAttribute('aria-pressed',String(button.dataset.role===role));": "for(const button of document.querySelectorAll('.character-card')){button.setAttribute('aria-pressed',String(button.dataset.role===role));button.querySelector('img').src=data[button.dataset.role].poses.neutral;}",
        "-Character ${role}`": "-Character ${role} -Version ${role==='P04'?version.toUpperCase():role==='P03'?'V10':'V8'}`",
        "$('character').onchange=": "$('version').onchange=()=>{version=$('version').value;data=versions[version];chooseRole(role)};\n$('character').onchange=",
    }
    for old, new in replacements.items():
        assert old in page, old
        page = page.replace(old, new)
    for token, value in {"__DATA__": json.dumps(versions, ensure_ascii=False).replace("</", "<\\/"), "__ROSTER__": cards, "__BATCH__": "0", "__TOTAL__": "38"}.items():
        assert token in page, token
        page = page.replace(token, value)
    (OUT / "index.html").write_text(page, encoding="utf-8")
    for path in list(OUT.glob("*.jpg")) + list((EV / "poses-final").glob("*.png")):
        inputs[path.relative_to(ROOT).as_posix()] = base.sha(path)
    manifest = {"all_media_are_real_godot_captures": True, "versions": ["v11", "v8"], "default_character": "P04",
                "captures_reused": {"P02": "V8", "P03": "V10", "v8_comparison": "P04 retained V8"},
                "inputs": inputs, "api_successful_this_revision": 0, "api_successful_cumulative": 38,
                "user_final_visual_acceptance": "pending"}
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"review": str(OUT / "index.html"), "exact_media_and_reports": len(inputs)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
