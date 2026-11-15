"""Full-body v4/v5 review from actual, timestamped Godot frames."""
from pathlib import Path
from collections import Counter
import argparse
import hashlib
import html
import json
import re

from PIL import Image, ImageDraw, ImageFont

import build_actor_motion_review as media
from build_actor_drawings_review import LABELS

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-anatomy-20261115"
BEFORE = ROOT / "artifacts/verification/actor-rig-drawings-20261115/render-04"
OUT = EV / "review"
FONT = "C:/Windows/Fonts/msyh.ttc"


def load(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def paired_crop(after, box, out, title, scale=2.4):
    size = [round((box[i + 2] - box[i]) * scale) for i in range(2)]
    canvas = Image.new("RGB", (size[0] * 2 + 60, size[1] + 125), "#152a33")
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(FONT, 21)
    draw.text((20, 13), title, font=font, fill="#f1d7a6")
    for i, (label, folder) in enumerate([("修改前 v4", BEFORE), ("本轮 v5", after)]):
        with Image.open(folder / "battle-1280-100.png") as source:
            bitmap = source.convert("RGB").crop(box).resize(size, Image.Resampling.LANCZOS)
        x = 20 + i * (size[0] + 20)
        draw.text((x, 51), label, font=font, fill="white")
        canvas.paste(bitmap, (x, 88))
    canvas.save(out, quality=96)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", default="render-04")
    args = parser.parse_args()
    after_dir = EV / args.run
    before, after = load(BEFORE / "report.json"), load(after_dir / "report.json")
    assert after["anatomy"] and not after["failures"]
    OUT.mkdir(parents=True, exist_ok=True)
    media.OUT = OUT
    data, clips = {}, []
    for name in dict.fromkeys(f["sequence"] for f in after["frames"]):
        data[name] = {"label": LABELS[name],
            "before": [{"ms": f["elapsed_ms"], "file": "../../actor-rig-drawings-20261115/render-04/" + f["file"]} for f in media.sequence(before, name)],
            "after": [{"ms": f["elapsed_ms"], "file": f"../{args.run}/" + f["file"]} for f in media.sequence(after, name)]}
        clips.append(media.actual_timing_gif(after, name, after_dir))
        media.keyframe_sheet(after, name, after_dir)
    paired_crop(after_dir, (140, 200, 345, 481), OUT / "fullbody-comparison.jpg", "相同战场、相同裁切：完整人物", 2.6)
    paired_crop(after_dir, (155, 325, 275, 481), OUT / "legs-comparison.jpg", "腰胯与双腿：实际战斗裁切", 3.2)
    media.side_by_side([
        ("修改前 v4 · 原比例与旧腿", BEFORE / "battle-1280-100.png"),
        ("本轮 v5 · 连贯腰胯与正常站姿", after_dir / "battle-1280-100.png"),
        ("本轮 v5 · 减少动态，完全静止", after_dir / "anatomy-reduced-motion-1280.png"),
        ("本轮 v5 · 960×600 / 150% 字号", after_dir / "battle-960-150.png"),
    ], OUT / "comparison.jpg")
    # Reuse the proven offline player/CSS only. The content is rebuilt around
    # complete anatomy, and every sequence points at this batch's actual frames.
    template = (ROOT / "artifacts/verification/actor-rig-drawings-20261115/review/index.html").read_text(encoding="utf-8")
    css = re.search(r"<style>(.*?)</style>", template, re.S)[1]
    script = re.findall(r"<script>(.*?)</script>", template, re.S)[-1]
    start, end = script.index("function panel("), script.index("\nasync function draw()")
    script = script[:start] + """function panel(ctx,img){const mode=$('crop').value;if(mode==='stage'){ctx.canvas.width=1190;ctx.canvas.height=390;ctx.drawImage(img,0,0)}else if(mode==='hero'||mode==='enemy'){ctx.canvas.width=320;ctx.canvas.height=355;ctx.drawImage(img,mode==='hero'?55:680,0,320,355,0,0,320,355)}else if(mode==='legs'){ctx.canvas.width=320;ctx.canvas.height=210;ctx.drawImage(img,55,145,320,210,0,0,320,210)}else{ctx.canvas.width=600;ctx.canvas.height=355;ctx.fillStyle='#15262e';ctx.fillRect(0,0,600,355);ctx.drawImage(img,70,0,270,355,0,0,270,355);ctx.drawImage(img,680,0,320,355,280,0,320,355)}}""" + script[end:]
    choices = "".join(f'<option value="{name}"' + (' selected' if name == 'command-00' else '') + f'>{label}</option>' for name, label in LABELS.items())

    def figure(file, caption, lazy=True):
        safe = html.escape(file, quote=True)
        return f'<figure><a href="{safe}"><img src="{safe}" {"loading=lazy" if lazy else ""} alt="{html.escape(caption)}"></a><figcaption>{caption}</figcaption></figure>'

    portraits = "".join(figure(f"../{args.run}/anatomy-full-{pose}.png", caption) for pose, caption in [
        ("neutral", "完全静止全身 · 同一Godot人物资源放大实渲"),
        ("action", "受控出手峰值 · 连续腰胯、膝盖与鞋底"),
        ("hit", "受控受击 · 回收不再过伸"),
        ("guard", "受控防御 · 上身动作与双腿支撑"),
    ])
    screen_html = ""
    for screen in after["screens"]:
        name = screen.get("file", screen.get("name", ""))
        if not name.endswith(".png"):
            name += ".png"
        screen_html += figure(f"../{args.run}/{name}", html.escape(name) + " · " + str(screen["kind"]))
    clip_html = "".join(figure(f'{clip["name"]}-strip.jpg', f'{LABELS[clip["name"]]} · {clip["frames"]}帧 · <a href="{clip["file"]}">独立GIF</a>') for clip in clips)
    geometry = after["anatomy_geometry"]
    page = f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>P01 人物形体修正 · 完整人物与双腿评审</title><style>{css}
.body-first{{display:block;max-width:1000px;margin:18px auto}}.body-first img{{width:100%;height:auto}}.portrait-grid img{{max-height:780px;object-fit:contain;background:#e6dfd1}}.code-wrap{{overflow-wrap:anywhere}}nav a{{padding:4px 0}} .controls label.stack{{max-width:100%}}select{{min-width:0}}
</style></head><body><main><p class="tag">P01 林序 · 人物形体修正 v5 · 2026-11-15</p>
<h1>先看静止站姿，再看连续动作</h1>
<p>本轮优先修正上下身比例、腰胯连接和画面左侧腿。左边是修改前，右边是新版本；两边为同一战斗场景的实际渲染，采用相同裁切和放大比例。</p>
<nav><a href="#fullbody">完整人物</a><a href="#legs">腰胯与双腿</a><a href="#viewer">前后动作</a><a href="#detail">放大全身</a><a href="#results">实际验证与后续计划</a></nav>
<section id="fullbody"><h2>完整人物：头身与上下身比例</h2><a class="body-first" href="fullbody-comparison.jpg"><img src="fullbody-comparison.jpg" alt="v4与v5完整人物相同战场裁切对照"></a>
<p>头部与上身统一校准，增加下身应有的体量；裤腰、骨盆、裆部与两条腿使用同一幅连续绘图。右侧人物站稳后仍保留胸口呼吸、眨眼与手部动作。</p></section>
<section id="legs"><h2>腰胯与双腿</h2><a class="body-first" href="legs-comparison.jpg"><img loading="lazy" src="legs-comparison.jpg" alt="相同裁切的腰胯、膝盖和双脚对照"></a>
<p>重新绘制画面左侧腿，使髋、膝、踝接近同一自然支撑方向。腿部按照图内关节绑定；鞋子独立保持鞋底方向，出手和受击时不再把已倾斜的旧裤管重复扭弯。</p></section>
<section id="viewer"><h2>连续动作：默认完整人物取景</h2><div class="controls"><label class="stack">场景<select id="sequence">{choices}</select></label><button id="play" type="button">暂停</button><button id="replay" type="button">重播</button><label>查看速度<select id="speed"><option value="1">采集原速 · 1×</option><option value="0.25">慢放 · 0.25×</option></select></label><label>取景<select id="crop"><option value="hero" selected>完整人物</option><option value="legs">腰胯与双腿</option><option value="stage">完整战斗区</option><option value="enemy">纸怪</option><option value="close">人物与纸怪</option></select></label><div class="timeline"><input id="seek" aria-label="逐时刻查看实渲" type="range" min="0" max="1200" step="1" value="0"><output id="time">0 / 1200 ms</output></div></div><p id="status" role="status"></p>
<div class="grid"><figure><p class="badge">修改前 v4 · 旧腿与原比例</p><canvas id="before" width="320" height="355" aria-label="修改前完整人物动作"></canvas><figcaption id="before-label"></figcaption></figure><figure><p class="badge">本轮 v5 · 连贯腰胯与正常双腿</p><canvas id="after" width="320" height="355" aria-label="修正后完整人物动作"></canvas><figcaption id="after-label"></figcaption></figure></div>
<p class="muted">真实出牌、结束回合与最后一击来自实际命令。受控试镜单独标明，慢放不改变游戏基础×4与用户倍速。两次采集各按实际时间戳播放，起始采样有少量间隔差异。画面回读不作为性能成绩。</p></section>
<section id="detail"><h2>完整人物大图：检查连接与腿形</h2><div class="grid portrait-grid">{portraits}</div><p>以上为相同原生人物资源在独立视口中的Godot放大实渲，用于造型检查；真实战斗画面见下方。点击图片查看原图。</p></section>
<section id="still"><h2>真实战斗与小窗口</h2><a href="comparison.jpg"><img loading="lazy" src="comparison.jpg" alt="战斗前后、减少动态及960窗口对照" style="width:100%;height:auto"></a></section>
<section id="results"><h2>实际结果与下一步</h2><p>本轮 {len(after['checks'])} 项定向检查、0失败；5条真实命令的领域、RNG、revision和事件一致。保存 {len(after['screens'])} 张PNG、{len(after['frames'])} 帧。双腿总骨长为 {geometry['leg_lengths'][0]:.1f} / {geometry['leg_lengths'][1]:.1f}，静止绑定误差 {geometry['neutral_bind_error']:.4f}，检查关节、膝向、可达范围及鞋底方向；这些数字只证明几何和行为，最终形体仍需看图判断。</p>
<p>本轮API编辑成功3张：全身参考1张，下半身首版1张，针对左腿返工1张。累计15/200张，选用第二版下半身；金额未由服务返回。上臂改为随自身骨骼转动，并去除躯干图里重复的袖管，改善出手时的拉扯。</p>
<p class="note">当前交付为人物形体修正版。站姿、腰胯和左腿已按本次反馈修正并实渲；大角度转身、极端袖片与手指透视仍需继续美术打磨。其他体型和全量生产继续留在代表人物通过后的阶段，最终视觉是否符合要求由本轮查看结果决定。</p>
<p>后续顺序：先核收本轮静止全身和真实动作中的腿形；再精修更大角度的肩肘与持物透视；之后分别验证伙伴、非纸片精英和多阶段Boss，依据实际返工工时决定小批生产。当前未启用默认入口。</p>
<p><a href="../{args.run}/report.json">本轮实渲报告</a> · <a href="../verification-summary.json">完整验证汇总</a> · <a href="../api-ledger.json">图片记录</a> · <a href="../../../../docs/plans/2026-11-15-actor-anatomy-design.md">实施与可行计划</a> · <a href="../raw-contact.jpg">3张原图</a> · <a href="../parts-contact-final.jpg">实际拆件</a> · <a href="../../actor-rig-polish-20261114/resource-review.md">此前官方连续动作参考</a></p>
<p class="code-wrap">独立试玩：<code>powershell -NoProfile -ExecutionPolicy Bypass -File tools/start_actor_anatomy.ps1</code></p></section>
<details><summary>全部两尺寸、三字号、静止与受控姿态实渲</summary><div class="grid">{screen_html}</div></details>
<details><summary>连续样本关键帧与独立GIF</summary><div class="grid">{clip_html}</div></details>
<script id="motion-data" type="application/json">{json.dumps(data, ensure_ascii=False).replace('</', '<' + chr(92) + '/')}</script><script>{script}</script></main></body></html>'''
    (OUT / "index.html").write_text(page, encoding="utf-8")
    media.save_json(OUT / "sequences.json", clips)
    media.save_json(OUT / "manifest.json", {"before": BEFORE.relative_to(ROOT).as_posix(), "after": after_dir.relative_to(ROOT).as_posix(),
        "sequence_counts": dict(Counter(frame["sequence"] for frame in after["frames"])), "clips": clips,
        "before_report_sha256": digest(BEFORE / "report.json"), "after_report_sha256": digest(after_dir / "report.json"),
        "all_media_are_real_godot_capture": True, "playback": "actual timestamps; 1x/0.25x viewer, unchanged game speed"})
    print(json.dumps({"review": str(OUT), "sequences": len(clips), "frames": len(after["frames"])}, ensure_ascii=False))


if __name__ == "__main__":
    main()
