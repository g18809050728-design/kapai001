"""Offline review of version 8 and preserved version 7, using real engine captures."""
from collections import defaultdict
import hashlib
import json
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from build_actor_party_review import FULL_LABELS, NAMES, PROPS

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-proportions-20261115"
OLD = ROOT / "artifacts/verification/actor-party-20261115"
OUT = EV / "review"


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def url(path):
    return Path(os.path.relpath(path, OUT)).as_posix()


def collect(folder, role, inputs):
    report = read(folder / "report.json")
    if report["failures"] or report.get("character") != role or not report.get("fullbody_frames"):
        raise ValueError("Incomplete or failed actual capture: " + str(folder))
    inputs[(folder / "report.json").relative_to(ROOT).as_posix()] = sha(folder / "report.json")
    sequences = defaultdict(lambda: {"frames": []})
    for frame in report["fullbody_frames"]:
        sequence = sequences[frame["sequence"]]
        sequence.update(label=FULL_LABELS[frame["sequence"]], kind="受控全身试镜")
        sequence["frames"].append({"file": url(folder / frame["file"]), "ms": frame["elapsed_ms"]})
    for frame in report["frames"]:
        key = frame["sequence"]
        sequence = sequences[key]
        label = {"idle": "实际战斗 · 持续待机", "motion-action-effective4": "受控战斗试镜 · 出手 ×4",
                 "motion-hit-effective4": "受控战斗试镜 · 受击 ×4", "motion-guard-effective4": "受控战斗试镜 · 防护 ×4",
                 "motion-depart-effective4": "受控战斗试镜 · 离场 ×4", "motion-action-authored1-slow": "受控战斗试镜 · 出手拆解 ×1",
                 "motion-hit-authored1-slow": "受控战斗试镜 · 受击拆解 ×1"}.get(key, key)
        if key.startswith("command-"):
            step = int(key.split("-")[-1])
            command = next(c for c in report["commands"] if c["step"] == step)
            label = f"真实命令 {step + 1} · " + ("出牌" if command["input"]["type"] == "play_card" else "结束回合")
        sequence.update(label=label, kind="真实发布命令" if key.startswith("command-") else "实际战斗待机" if key == "idle" else "受控战斗试镜")
        sequence["frames"].append({"file": url(folder / frame["file"]), "ms": frame["elapsed_ms"]})
    result = {"name": NAMES[role], "prop": PROPS[role], "sequences": dict(sequences), "checks": len(report["checks"]),
              "foot_error": report["anatomy_geometry"]["max_foot_error"],
              "poses": {pose: url(folder / f"anatomy-full-{pose}.png") for pose in ("neutral", "action", "hit", "guard")},
              "screens": {name: url(folder / file) for name, file in {
                  "normal": "battle-1280-100.png", "small": "battle-960-150.png",
                  "reduced": "anatomy-reduced-motion-1280.png", "result": "after-real-battle.png"}.items()},
              "commands": [{"step": c["step"] + 1, "input": json.dumps(c["input"], ensure_ascii=False),
                            "events": ", ".join(dict.fromkeys(e["type"] for e in c["published_events"])), "equal": c["equal"]}
                           for c in report["commands"]]}
    paths = set(result["poses"].values()) | set(result["screens"].values())
    for sequence in sequences.values():
        assert all(a["ms"] <= b["ms"] for a, b in zip(sequence["frames"], sequence["frames"][1:]))
        paths.update(f["file"] for f in sequence["frames"])
    for relative in paths:
        path = (OUT / relative).resolve()
        if not path.is_file():
            raise FileNotFoundError(path)
        inputs[path.relative_to(ROOT).as_posix()] = sha(path)
    return result


def compare(versions):
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 28)
    images = []
    for role in NAMES:
        board = Image.new("RGB", (1200, 780), "#e6dfd1")
        draw = ImageDraw.Draw(board)
        for column, (version, label) in enumerate((("v7", "上一版"), ("v8", "比例修正版"))):
            image = Image.open((OUT / versions[version][role]["poses"]["neutral"]).resolve()).convert("RGB")
            # Identical image size / fit / foot baseline. No independent auto-fit.
            image = image.resize((600, 700), Image.Resampling.LANCZOS)
            board.paste(image, (column * 600, 55))
            draw.text((column * 600 + 180, 12), NAMES[role] + " · " + label, font=font, fill="#243842")
        file = role.lower() + "-before-after.jpg"
        board.save(OUT / file, quality=96)
        images.append(f'<figure><a href="{file}"><img src="{file}" alt="{NAMES[role]}同尺度、同脚底前后对照"></a><figcaption>{NAMES[role]} · 左：上一版，右：本轮修正版</figcaption></figure>')
    lineup = Image.new("RGB", (1800, 840), "#e6dfd1")
    draw = ImageDraw.Draw(lineup)
    for column, role in enumerate(NAMES):
        image = Image.open((OUT / versions["v8"][role]["poses"]["neutral"]).resolve()).convert("RGB")
        image.thumbnail((590, 765))
        lineup.paste(image, (column * 600 + (600 - image.width) // 2, 48))
        draw.text((column * 600 + 180, 10), NAMES[role], font=font, fill="#243842")
    lineup.save(OUT / "lineup.jpg", quality=96)
    return "".join(images)


def inspection_sheets():
    """Timestamped samples for full-body support and the independently moving neck."""
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 20)
    records = []
    for role in NAMES:
        folder = EV / (role.lower() + "-final")
        report = read(folder / "report.json")
        for sequence in ("fullbody-action-x1", "fullbody-hit-x1"):
            frames = [f for f in report["fullbody_frames"] if f["sequence"] == sequence]
            sheet = Image.new("RGB", (1400, 1740), "#e6dfd1")
            draw = ImageDraw.Draw(sheet)
            selected = []
            for index in range(16):
                frame = frames[round(index * (len(frames) - 1) / 15)]
                image = Image.open(folder / frame["file"]).convert("RGB")
                image.thumbnail((350, 400))
                x, y = (index % 4) * 350, (index // 4) * 435
                sheet.paste(image, (x, y + 32))
                draw.text((x + 95, y + 5), f'{frame["elapsed_ms"]} ms', font=font, fill="#263943")
                selected.append({"file": (folder / frame["file"]).relative_to(ROOT).as_posix(), "ms": frame["elapsed_ms"]})
            output = EV / (role.lower() + "-" + sequence + "-inspection.jpg")
            sheet.save(output, quality=95)
            records.append({"file": output.relative_to(ROOT).as_posix(), "role": role, "sequence": sequence, "samples": selected})
            if role == "P03":
                close = Image.new("RGB", (1800, 1545), "#e6dfd1")
                draw = ImageDraw.Draw(close)
                for index, sample in enumerate(selected[:12]):
                    image = Image.open(ROOT / sample["file"]).convert("RGB").crop((390, 150, 840, 630))
                    x, y = (index % 4) * 450, (index // 4) * 515
                    close.paste(image, (x, y + 33))
                    draw.text((x + 135, y + 4), f'{sample["ms"]} ms', font=font, fill="#263943")
                close.save(EV / ("p03-neck-" + sequence + "-inspection.jpg"), quality=97)
    (EV / "inspection-sheets.json").write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    inputs = {}
    versions = {version: {role: collect(folder / (role.lower() + "-final"), role, inputs) for role in NAMES}
                for version, folder in (("v8", EV), ("v7", OLD))}
    comparisons = compare(versions)
    inspection_sheets()
    cards = "".join(f'<button class="character-card" type="button" data-role="{role}" aria-pressed="{str(role == "P02").lower()}" aria-label="查看{name}完整人物与动作"><img src="{versions["v8"][role]["poses"]["neutral"]}" alt="{name}修正版完整站姿"><strong>{name}</strong><span>{PROPS[role]}</span></button>' for role, name in NAMES.items())
    # Keep the exercised timestamp player and its stale-frame protection.
    page = (ROOT / "tools/actor_party_review.html").read_text(encoding="utf-8")
    page = page.replace("三位主角制作 · 2026-11-15", "三人比例与沈见章颈部修正 · 2026-11-15 · V8")
    page = page.replace("先看完整人物，再看连续动作。三人保留各自的服装、发型与持物，使用独立关节和动作节奏。下方图片和连续帧均来自本轮 Godot 实际渲染。", "三人下肢从髋到踝缩短约 22%，保留上身、服装、道具与鞋子自身比例；沈见章重做短颈与领口衔接。下方可切换本轮修正版与上一版，完整人物、战斗和连续动作均为各版本的 Godot 实渲。")
    page = page.replace('<a href="#motion">连续动作</a>', '<a href="#comparison">前后对照</a><a href="#motion">连续动作</a>')
    page = page.replace('<section id="motion">', '<section id="comparison"><h2>完整人物 · 同尺度前后对照</h2><p class="muted small">同一画布、同一缩放和脚底基线；上身没有压扁。点击可放大。</p><div class="grid">' + comparisons + '</div></section>\n<section id="motion">')
    page = page.replace('<label>角色<select', '<label>版本<select id="version"><option value="v8">本轮修正版 V8</option><option value="v7">上一版 V7</option></select></label>\n<label>角色<select')
    page = page.replace("docs/plans/2026-11-15-actor-party-design.md", "docs/plans/2026-11-15-actor-proportions-design.md")
    page = page.replace('本次完成三位主角，其他敌怪与全量资源仍按原计划推进。', '本次修正三人的比例与沈见章颈部；原版 V5 和其他角色范围保持。')
    page = page.replace("const data=JSON.parse", "const versions=JSON.parse")
    page = page.replace("let role='P02'", "let version='v8',data=versions[version];\nlet role='P02'")
    page = page.replace("d.name+' · 连续动作'", "d.name+' · '+(version==='v8'?'修正版':'上一版')+' · 连续动作'")
    page = page.replace("for(const button of document.querySelectorAll('.character-card'))button.setAttribute('aria-pressed',String(button.dataset.role===role));", "for(const button of document.querySelectorAll('.character-card')){button.setAttribute('aria-pressed',String(button.dataset.role===role));button.querySelector('img').src=data[button.dataset.role].poses.neutral;}")
    page = page.replace("-Character ${role}`", "-Character ${role} -Version ${version==='v8'?'V8':'V7'}`")
    page = page.replace("$('character').onchange=", "$('version').onchange=()=>{version=$('version').value;data=versions[version];chooseRole(role)};\n$('character').onchange=")
    for token, value in {"__DATA__": json.dumps(versions, ensure_ascii=False).replace("</", "<\\/"),
                         "__ROSTER__": cards, "__BATCH__": "1", "__TOTAL__": "28"}.items():
        page = page.replace(token, value)
    (OUT / "index.html").write_text(page, encoding="utf-8")
    record = {"all_media_are_real_godot_captures": True, "versions": ["v8", "v7"], "inputs": inputs,
              "sequence_counts": {version: {role: {s: len(v["frames"]) for s, v in data["sequences"].items()}
                                            for role, data in roles.items()} for version, roles in versions.items()},
              "api_successful_this_revision": 1, "api_successful_cumulative": 28, "user_final_visual_acceptance": "pending"}
    (OUT / "manifest.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"review": str(OUT / "index.html"), "actual_capture_files": len(inputs)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
