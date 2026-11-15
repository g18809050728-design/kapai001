"""Show v5/v6 controlled poses and timestamped live Godot sequences."""
import argparse
from collections import Counter
import hashlib
import html
import json
from pathlib import Path
import re

from PIL import Image, ImageDraw, ImageFont

import build_actor_motion_review as media
from build_actor_drawings_review import LABELS

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-seams-20261115"
BEFORE = EV / "baseline-v5-final"
OUT = EV / "review"


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def paired(after, file, box, name, title):
    width = min(720, round((box[2] - box[0]) * 1.5))
    height = round((box[3] - box[1]) * width / (box[2] - box[0]))
    canvas = Image.new("RGB", (width * 2 + 48, height + 96), "#172b34")
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 20)
    draw.text((16, 9), title + " · 同一姿势/时刻与相同裁切", font=font, fill="#f1d7a6")
    for index, (label, directory) in enumerate([("修改前 v5", BEFORE), ("本轮 v6", after)]):
        x = 16 + index * (width + 16)
        draw.text((x, 42), label, font=font, fill="white")
        with Image.open(directory / file) as image:
            canvas.paste(image.convert("RGB").crop(box).resize((width, height), Image.Resampling.LANCZOS), (x, 80))
    canvas.save(OUT / name, quality=96)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", required=True)
    args = parser.parse_args()
    after_dir = EV / args.run
    before, after = load(BEFORE / "report.json"), load(after_dir / "report.json")
    assert after["seams"] and not after["failures"]
    OUT.mkdir(parents=True, exist_ok=True)
    media.OUT = OUT
    paired(after_dir, "anatomy-full-action.png", (350, 200, 970, 590), "shoulder-comparison.jpg", "出手肩肘与袖管")
    paired(after_dir, "anatomy-full-neutral.png", (390, 160, 700, 380), "collar-comparison.jpg", "静止领口衔接")
    paired(after_dir, "anatomy-full-hit.png", (390, 150, 730, 440), "collar-hit-comparison.jpg", "受击领口衔接")
    paired(after_dir, "anatomy-full-neutral.png", (595, 448, 880, 615), "wrist-comparison.jpg", "托电脑手腕")
    paired(after_dir, "anatomy-full-neutral.png", (230, 35, 960, 1300), "fullbody-neutral-comparison.jpg", "完整静止人物")
    paired(after_dir, "anatomy-full-action.png", (260, 35, 1000, 1300), "fullbody-action-comparison.jpg", "完整出手人物")
    data, clips = {}, []
    for name in dict.fromkeys(frame["sequence"] for frame in after["frames"]):
        data[name] = {"label": LABELS[name],
            "before": [{"ms": f["elapsed_ms"], "file": "../baseline-v5-final/" + f["file"]} for f in media.sequence(before, name)],
            "after": [{"ms": f["elapsed_ms"], "file": f"../{args.run}/" + f["file"]} for f in media.sequence(after, name)]}
        clips.append(media.actual_timing_gif(after, name, after_dir))
        media.keyframe_sheet(after, name, after_dir)
    template = (ROOT / "artifacts/verification/actor-anatomy-20261115/review/index.html").read_text(encoding="utf-8")
    css = re.search(r"<style>(.*?)</style>", template, re.S)[1]
    script = re.findall(r"<script>(.*?)</script>", template, re.S)[-1]
    choices = "".join(f'<option value="{name}">{label}</option>' for name, label in LABELS.items())

    def figure(file, caption):
        safe = html.escape(file, quote=True)
        return f'<figure><a href="{safe}"><img loading="lazy" src="{safe}" alt="{html.escape(caption)}"></a><figcaption>{caption}</figcaption></figure>'

    portraits = "".join(figure(f"../{args.run}/anatomy-full-{pose}.png", caption) for pose, caption in [
        ("neutral", "静止全身"), ("action", "出手 .42"), ("hit", "受击 .16"), ("guard", "防护 .40")])
    screens = []
    for screen in after["screens"]:
        name = screen.get("file", screen.get("name", ""))
        if not name.endswith(".png"):
            name += ".png"
        screens.append(figure(f"../{args.run}/{name}", name + " · " + str(screen["kind"])))
    clip_html = "".join(figure(clip["name"] + "-strip.jpg", LABELS[clip["name"]] + f' · <a href="{clip["file"]}">独立GIF</a>') for clip in clips)
    page = f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>P01 肩袖与领口 / 手腕小修</title><style>{css}
.comparison{{display:block;width:100%;height:auto;margin:16px 0}}.portrait-grid img{{max-height:760px;object-fit:contain;background:#e6dfd1}}code{{overflow-wrap:anywhere}}section{{scroll-margin-top:16px}}
</style></head><body><main><p class="tag">P01 林序 · v5 / v6 · 2026-11-15</p>
<h1>肩袖与领口、手腕局部修整</h1><p>保留已认可的头身、腰胯和双腿，只修肩袖厚重与局部衔接。以下全部人物来自同一Godot骨架的实际渲染。左侧为修改前，右侧为本轮。</p>
<nav><a href="#shoulder">肩肘 / 袖管</a><a href="#contacts">领口 / 手腕</a><a href="#viewer">连续动作</a><a href="#fullbody">完整人物</a><a href="#results">实际验证</a></nav>
<section id="shoulder"><h2>出手肩肘与袖管</h2><a href="shoulder-comparison.jpg"><img class="comparison" src="shoulder-comparison.jpg" alt="同一出手时刻的肩袖前后对照"></a><p>上袖局部收窄，减少肘部重复袖口；降低过高抬臂并同步补偿前臂角度，保留朝向对手的出手方向。</p></section>
<section id="contacts"><h2>领口与托电脑手腕</h2><div class="grid">{figure('collar-comparison.jpg', '静止领口')}{figure('collar-hit-comparison.jpg', '受击领口')}{figure('wrist-comparison.jpg', '托电脑手腕：同一原图连续重叠')}</div><p>颈部补片向衣领内部延伸，边缘放在遮挡内；前臂与手掌使用同一原图、同一注册坐标及重叠区，电脑独立遮挡。</p></section>
<section id="viewer"><h2>连续动作前后对照</h2><div class="controls"><label class="stack">场景<select id="sequence">{choices}</select></label><button id="play" type="button">暂停</button><button id="replay" type="button">重播</button><label>查看速度<select id="speed"><option value="1">采集原速 · 1×</option><option value="0.25">慢放 · 0.25×</option></select></label><label>取景<select id="crop"><option value="hero" selected>完整人物</option><option value="legs">腰胯与双腿</option><option value="stage">完整战斗区</option><option value="enemy">纸怪</option><option value="close">人物与纸怪</option></select></label><div class="timeline"><input id="seek" aria-label="逐时刻查看实渲" type="range" min="0" max="1200" step="1" value="0"><output id="time">0 / 1200 ms</output></div></div><p id="status" role="status"></p><div class="grid"><figure><p class="badge">修改前 v5</p><canvas id="before" width="320" height="355" aria-label="修改前人物"></canvas><figcaption id="before-label"></figcaption></figure><figure><p class="badge">本轮 v6</p><canvas id="after" width="320" height="355" aria-label="修整后人物"></canvas><figcaption id="after-label"></figcaption></figure></div><p class="muted">真实命令与受控试镜分别标明；采集时间戳独立播放。慢放只影响此评审页，游戏基础×4与用户倍速保持。画面回读不作为性能成绩。</p></section>
<section id="fullbody"><h2>完整人物核对</h2><a href="fullbody-neutral-comparison.jpg"><img loading="lazy" class="comparison" src="fullbody-neutral-comparison.jpg" alt="完整静止人物前后对照"></a><a href="fullbody-action-comparison.jpg"><img loading="lazy" class="comparison" src="fullbody-action-comparison.jpg" alt="完整出手人物前后对照"></a><div class="grid portrait-grid">{portraits}</div><p>上述为相同资源在独立视口中的放大实渲。资源比对另行检查双腿、骨盆、鞋、骨架和原比例字段完全保留。</p></section>
<section id="results"><h2>本轮实际验证</h2><p>{len(after['checks'])}项定向检查、0失败；5条真实命令A/B领域、RNG、revision和事件一致。{len(after['screens'])}张PNG，{len(after['frames'])}帧连续实渲。行为检查与视觉查看分别记录。</p><p>本轮API新增0张，7张局部PNG为现有原图的本地派生；累计仍为15/200。N01保持原v4，默认入口保留。此轮仅完成这两类小修。</p><p><a href="../{args.run}/report.json">实渲报告</a> · <a href="../verification-summary.json">验证汇总</a> · <a href="../visual-review.json">实际视觉复核</a> · <a href="../../../../docs/plans/2026-11-15-actor-seams-design.md">设计及结果</a></p><p>试玩：<code>powershell -NoProfile -ExecutionPolicy Bypass -File tools/start_actor_seams.ps1</code></p></section>
<details><summary>全部两尺寸、三字号与姿态实渲</summary><div class="grid">{''.join(screens)}</div></details><details><summary>关键帧与连续GIF</summary><div class="grid">{clip_html}</div></details>
<script id="motion-data" type="application/json">{json.dumps(data, ensure_ascii=False).replace('</', '<' + chr(92) + '/')}</script><script>{script}</script></main></body></html>'''
    (OUT / "index.html").write_text(page, encoding="utf-8")
    media.save_json(OUT / "sequences.json", clips)
    media.save_json(OUT / "manifest.json", {"before": BEFORE.relative_to(ROOT).as_posix(), "after": after_dir.relative_to(ROOT).as_posix(),
        "before_report_sha256": digest(BEFORE / "report.json"), "after_report_sha256": digest(after_dir / "report.json"),
        "sequence_counts": dict(Counter(f["sequence"] for f in after["frames"])), "clips": clips,
        "all_media_are_real_godot_capture": True})
    print(json.dumps({"review": str(OUT), "frames": len(after['frames']), "sequences": len(clips)}))


if __name__ == "__main__":
    main()
