"""Publish a self-contained, timestamped review from three successful Godot runs."""
import argparse
from collections import defaultdict
import hashlib
import html
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-party-20261115"
OUT = EV / "review"
NAMES = {"P02": "许知微", "P03": "沈见章", "P04": "唐以宁"}
PROPS = {"P02": "论文夹与笔 · 研究组织者", "P03": "论证卡片与笔 · 论证与追问", "P04": "分工板与便签 · 小组协调者"}
FULL_LABELS = {"fullbody-idle-x1": "受控全身 · 呼吸与眨眼", "fullbody-action-x4": "受控全身 · 出手 · 游戏默认速度 ×4", "fullbody-action-x1": "受控全身 · 出手拆解 · 比默认慢四倍", "fullbody-hit-x1": "受控全身 · 受击拆解 · 比默认慢四倍", "fullbody-guard-x4": "受控全身 · 防护 · 游戏默认速度 ×4"}


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def lineup(data, pose, destination):
    canvas = Image.new("RGB", (1800, 840), "#e6dfd1")
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 25)
    for i, (role, d) in enumerate(data.items()):
        im = Image.open((OUT / d["poses"][pose]).resolve()).convert("RGB")
        im.thumbnail((590, 765))
        canvas.paste(im, (i * 600 + (600 - im.width) // 2, 48))
        draw.text((i * 600 + 150, 10), role + " " + d["name"], font=font, fill="#243842")
    canvas.save(destination, quality=95)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--p02", default="p02-final")
    parser.add_argument("--p03", default="p03-final")
    parser.add_argument("--p04", default="p04-final")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    data, inputs, paths = {}, {}, set()
    for role, name in NAMES.items():
        run = getattr(args, role.lower())
        folder = EV / run
        report = read(folder / "report.json")
        if report["failures"] or report.get("character") != role or not report.get("fullbody_frames"):
            raise SystemExit(f"Cannot publish failed, mismatched or incomplete captures: {run}")
        inputs[(folder / "report.json").relative_to(ROOT).as_posix()] = sha(folder / "report.json")
        sequences = defaultdict(lambda: {"frames": []})
        for f in report["fullbody_frames"]:
            s = sequences[f["sequence"]]
            s.update(label=FULL_LABELS[f["sequence"]], kind="受控全身试镜")
            s["frames"].append({"file": f"../{run}/{f['file']}", "ms": f["elapsed_ms"]})
        for f in report["frames"]:
            key = f["sequence"]
            s = sequences[key]
            label = {"idle": "实际战斗 · 持续待机", "motion-action-effective4": "受控战斗试镜 · 出手 ×4", "motion-hit-effective4": "受控战斗试镜 · 受击 ×4", "motion-guard-effective4": "受控战斗试镜 · 防护 ×4", "motion-depart-effective4": "受控战斗试镜 · 离场 ×4", "motion-action-authored1-slow": "受控战斗试镜 · 出手拆解 ×1", "motion-hit-authored1-slow": "受控战斗试镜 · 受击拆解 ×1"}.get(key)
            if key.startswith("command-"):
                step = int(key.split("-")[-1])
                command = next(c for c in report["commands"] if c["step"] == step)
                label = f"真实命令 {step + 1} · " + ("出牌" if command["input"]["type"] == "play_card" else "结束回合")
            s.update(label=label or key, kind="真实发布命令" if key.startswith("command-") else "实际战斗待机" if key == "idle" else "受控战斗试镜")
            s["frames"].append({"file": f"../{run}/{f['file']}", "ms": f["elapsed_ms"]})
        d = {"name": name, "prop": PROPS[role], "sequences": dict(sequences), "checks": len(report["checks"]),
             "foot_error": report["anatomy_geometry"]["max_foot_error"],
             "poses": {pose: f"../{run}/anatomy-full-{pose}.png" for pose in ["neutral", "action", "hit", "guard"]},
             "screens": {"normal": f"../{run}/battle-1280-100.png", "small": f"../{run}/battle-960-150.png", "reduced": f"../{run}/anatomy-reduced-motion-1280.png", "result": f"../{run}/after-real-battle.png"},
             "commands": [{"step": c["step"] + 1, "input": json.dumps(c["input"], ensure_ascii=False), "events": ", ".join(dict.fromkeys(e["type"] for e in c["published_events"])), "equal": c["equal"]} for c in report["commands"]]}
        for s in sequences.values():
            assert all(a["ms"] <= b["ms"] for a, b in zip(s["frames"], s["frames"][1:])), "Frame timestamps must be monotonic"
            paths.update(f["file"] for f in s["frames"])
        paths.update(d["poses"].values())
        paths.update(d["screens"].values())
        data[role] = d
    for relative in paths:
        path = (OUT / relative).resolve()
        if not path.is_file():
            raise SystemExit("Missing real capture: " + relative)
        inputs[path.relative_to(ROOT).as_posix()] = sha(path)
    manifest = read(ROOT / "output/imagegen/actor-party-20261115/asset-manifest.json")
    cards = "".join(f'<button class="character-card" type="button" data-role="{role}" aria-pressed="{str(role == "P02").lower()}" aria-label="查看{name}完整人物与动作"><img src="{data[role]["poses"]["neutral"]}" alt="{name}完整静止站姿"><strong>{name}</strong><span>{PROPS[role]}</span></button>' for role, name in NAMES.items())
    page = (ROOT / "tools/actor_party_review.html").read_text(encoding="utf-8")
    for token, value in {"__DATA__": json.dumps(data, ensure_ascii=False).replace("</", "<\\/"), "__ROSTER__": cards, "__BATCH__": str(manifest["successful_this_batch"]), "__TOTAL__": str(manifest["cumulative_successful"])}.items():
        page = page.replace(token, value)
    (OUT / "index.html").write_text(page, encoding="utf-8")
    lineup(data, "neutral", OUT / "lineup.jpg")
    lineup(data, "action", OUT / "action-lineup.jpg")
    record = {"all_media_are_real_godot_captures": True, "runs": vars(args), "inputs": inputs, "sequence_counts": {role: {s: len(v["frames"]) for s, v in d["sequences"].items()} for role, d in data.items()}, "api_successful": manifest["cumulative_successful"], "user_final_visual_acceptance": "pending"}
    (OUT / "manifest.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"review": str(OUT / "index.html"), "roles": list(data), "real_capture_files": len(inputs)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
