"""Build a review page only from actual Godot captures and original asset metadata."""
import argparse
from collections import defaultdict
import html
import json
from pathlib import Path
import re

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/enemy-roster-20261115"
RAW = ROOT / "output/imagegen/enemy-roster-20261115"
FONT = "C:/Windows/Fonts/msyh.ttc"
POSES = {"neutral": "静止", "action": "出手", "hit": "受击", "guard": "防御",
         "enter": "入场", "depart": "离场", "phase": "阶段切换"}


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def portrait_previews(entries, probe, review):
    directory = review / "portraits"
    directory.mkdir(exist_ok=True)
    crops = {}
    for entry in entries:
        frames, bounds = {}, []
        for pose in POSES:
            with Image.open(probe / f'{entry["id"]}-{pose}.png') as source:
                frame = source.convert("RGB")
                frames[pose] = frame.copy()
                difference = ImageChops.difference(frame, Image.new("RGB", frame.size, "#e6dfd1"))
                red, green, blue = difference.split()
                maximum = ImageChops.lighter(ImageChops.lighter(red, green), blue)
                box = maximum.point(lambda value: 255 if value > 65 else 0).getbbox()
                if box:
                    bounds.append(box)
        crop = (max(0, min(box[0] for box in bounds) - 28), max(0, min(box[1] for box in bounds) - 28),
                min(frame.width, max(box[2] for box in bounds) + 28),
                min(frame.height, max(box[3] for box in bounds) + 28))
        crops[entry["id"]] = list(crop)
        for pose, frame in frames.items():
            frame.crop(crop).save(directory / f'{entry["id"]}-{pose}.png')
    return directory, crops


def sheet(entries, paths, output, columns=4):
    cw, ch = 350, 380
    image = Image.new("RGB", (cw * columns, ch * ((len(entries) + columns - 1) // columns)), "#e6dfd1")
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(FONT, 18)
    for i, (entry, path) in enumerate(zip(entries, paths)):
        x, y = (i % columns) * cw, (i // columns) * ch
        with Image.open(path) as source:
            thumbnail = ImageOps.contain(source.convert("RGB"), (cw - 12, ch - 45))
        image.paste(thumbnail, (x + (cw - thumbnail.width) // 2, y + 4))
        draw.text((x + 12, y + ch - 37), entry["id"] + " · " + entry["name"], fill="#253d48", font=font)
    image.save(output, quality=95)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--probe", required=True)
    parser.add_argument("--game", required=True)
    parser.add_argument("--sequences", required=True)
    args = parser.parse_args()
    review = EV / "review"
    review.mkdir(exist_ok=True)
    roster = read(RAW / "roster.json")["entries"]
    registry = read(ROOT / "assets/art/enemies/roster.json")["enemies"]
    entries = [x for x in roster if x["id"] in registry]
    probe, game, sequences = [EV / x for x in (args.probe, args.game, args.sequences)]
    portraits, portrait_crops = portrait_previews(entries, probe, review)
    sheets = []
    for start in range(0, len(entries), 12):
        chunk = entries[start:start + 12]
        for pose in ("neutral", "action"):
            name = f"enemies-{start // 12 + 1}-{pose}.jpg"
            sheet(chunk, [portraits / (x["id"] + "-" + pose + ".png") for x in chunk], review / name)
            sheets.append(name)
    bosses = [e for e in entries if e["id"].startswith("FY_")]
    if bosses:
        sheet(bosses, [portraits / (x["id"] + "-neutral.png") for x in bosses], review / "bosses.jpg")
    game_report = read(game / "report.json")
    normal = [game / (id_ + "-battle-1280-100.png") for id_ in ("P01", "P02", "P03", "P04")]
    montage = Image.new("RGB", (1280, 800))
    for i, path in enumerate(normal):
        with Image.open(path) as source:
            montage.paste(source.resize((640, 400), Image.Resampling.LANCZOS), ((i % 2) * 640, (i // 2) * 400))
    montage.save(review / "normal-battle.jpg", quality=95)
    grouped = defaultdict(list)
    for frame in read(sequences / "sequences.json")["frames"]:
        grouped[frame["id"]].append(frame)
    animations = []
    for id_, frames in grouped.items():
        images, durations = [], []
        bounds = []
        for i, frame in enumerate(frames):
            with Image.open(sequences / frame["file"]) as image:
                frame_image = image.convert("RGB")
                images.append(frame_image.copy())
                difference = ImageChops.difference(frame_image, Image.new("RGB", image.size, "#e6dfd1"))
                box = difference.convert("L").point(lambda value: 255 if value > 48 else 0).getbbox()
                if box:
                    bounds.append(box)
            if i + 1 < len(frames) and frames[i + 1]["pose"] == frame["pose"]:
                durations.append(max(25, frames[i + 1]["elapsed_ms"] - frame["elapsed_ms"]))
            else:
                durations.append(110)
        filename = id_ + "-motion.webp"
        crop = (max(0, min(x[0] for x in bounds) - 25), max(0, min(x[1] for x in bounds) - 25),
                min(images[0].width, max(x[2] for x in bounds) + 25),
                min(images[0].height, max(x[3] for x in bounds) + 25))
        preview_frames = []
        for image in images:
            preview = Image.new("RGB", (500, 500), "#e6dfd1")
            foreground = ImageOps.contain(image.crop(crop), (500, 500), Image.Resampling.LANCZOS)
            preview.paste(foreground, ((500 - foreground.width) // 2, (500 - foreground.height) // 2))
            preview_frames.append(preview)
        preview_frames[0].save(review / filename, save_all=True, append_images=preview_frames[1:], duration=durations,
                       loop=0, quality=88, method=4)
        animations.append({"id": id_, "file": filename, "frames": len(images), "constant_union_crop": list(crop)})
    total = len(registry)
    checks, commands = len(game_report["checks"]), len(game_report["commands"])
    cards = []
    for entry in entries:
        id_ = entry["id"]
        cards.append(f'<article data-search="{html.escape(id_ + " " + entry["name"])}"><a class="portrait" href="../{args.probe}/{id_}-neutral.png" target="_blank"><img loading="lazy" data-id="{id_}" src="portraits/{id_}-neutral.png" alt="{html.escape(entry["name"])}"></a><strong>{html.escape(entry["name"])}</strong><small>{id_} · {entry.get("family", "原 V4")} · V{registry[id_]["version"]}</small></article>')
    motion_cards = "".join(f'<figure><img loading="lazy" src="{x["file"]}" alt="{x["id"]} 真实连续动作"><figcaption>{x["id"]} · 待机→出手→受击 · {x["frames"]} 帧</figcaption></figure>' for x in animations)
    encounter_cards = []
    for entry in game_report["encounters"]:
        id_ = entry["encounter"]
        encounter_cards.append(f'<a href="../{args.game}/encounter-{id_}.png" target="_blank"><img loading="lazy" src="../{args.game}/encounter-{id_}.png" alt="{id_} 实际战斗界面"><span>{id_}</span></a>')
    pending = [x["id"] for x in roster if x["id"] not in registry]
    content = """<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>敌怪形象与动作评审</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#172731;color:#f4eedf;font:16px/1.7 "Microsoft YaHei",sans-serif}main{max-width:1420px;margin:auto;padding:32px 24px 80px}h1{font-size:30px;margin:0 0 12px}h2{font-size:24px;margin:36px 0 14px}p{max-width:1050px;color:#ccd8d9}a{color:#efd19b}img{max-width:100%;display:block}button,input,select{font:inherit;min-height:44px;background:#263f4c;border:1px solid #78978e;color:#fff;padding:6px 14px;border-radius:5px}input{min-width:240px}nav{display:flex;gap:12px;flex-wrap:wrap;position:sticky;top:0;background:#172731ed;padding:12px 0;z-index:2}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(245px,1fr));gap:16px}.grid article{background:#e6dfd1;border-radius:8px;overflow:hidden;color:#253d48;padding-bottom:15px}.grid article strong,.grid article small{display:block;padding:0 15px}.grid article img{width:100%;aspect-ratio:1;object-fit:contain}.grid article[hidden]{display:none}.wide{border-radius:6px;width:100%}.motion{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:18px}.motion figure{margin:0}.encounters{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:16px}.encounters a{background:#213a46;border-radius:5px;overflow:hidden;text-decoration:none}.encounters span{padding:6px 12px;display:block}.note{padding:16px 20px;background:#263e49;border-left:4px solid #c9a86b}.links{display:flex;gap:18px;flex-wrap:wrap}
</style><main>
"""
    content += f'<h1>敌怪形象与动作评审 · {total}/60</h1><p>当前四学年全部启用任务按精确 ID 配置。N01沿用已核对 V4，其余使用新绘主体、独立攻击部件和辅件，并接入原生二维骨架与加权网格。下列立绘、姿态、连续帧与战斗画面均由 Godot 实际图形渲染。</p>'
    content += f'<p class="note">实机专项 {checks} 项检查，{commands} 条正常局真实命令 A/B；另以公开、隔离的测试房间配置遍历 {len(game_report["encounters"])} 个遭遇。测试房间和固定姿态属于明确标注的受控验证，不能等同自然四年通关。此页供最终美术查看；二维局部形变仍有幅度限制。</p>'
    if pending:
        content += '<p class="note">尚未制作：' + html.escape(", ".join(pending)) + '</p>'
    content += '<div class="links"><a href="#catalog">独立敌怪图鉴</a><a href="#motion">连续动作</a><a href="#game">实战画面</a><a href="../../../../docs/plans/2026-11-15-enemy-roster-design.md">制作与验证记录</a><a href="../../../../output/imagegen/enemy-roster-20261115/asset-manifest.json">来源、模型及提示词索引</a></div>'
    content += '<h2 id="catalog">逐种形象与六类动作</h2><nav><input id="search" type="search" placeholder="按名字或 ID 查找" aria-label="筛选敌怪"><select id="pose" aria-label="查看动作姿态">' + "".join(f'<option value="{key}">{value}</option>' for key, value in POSES.items()) + '</select><span id="count"></span></nav><div class="grid">' + "".join(cards) + '</div>'
    content += '<h2 id="motion">实际连续动作</h2><p>1×骨架速度，保留独立待机循环；正式战斗继续叠加当前基础×4与用户倍速。以下为实际帧转成的动画，原帧与时间记录保留。</p><div class="motion">' + motion_cards + '</div>'
    content += f'<h2 id="game">正常入口与战斗</h2><a href="normal-battle.jpg" target="_blank"><img class="wide" src="normal-battle.jpg" alt="正常四角色战斗"></a><p>下面通过公开测试房间逐遭遇配置，使用与正式游戏相同的 BattleScreen 和敌怪路由；点击放大。</p><div class="encounters">' + "".join(encounter_cards) + '</div>'
    content += r"""
<script>
const articles=[...document.querySelectorAll('article')],pose=document.querySelector('#pose'),search=document.querySelector('#search');
function filter(){let count=0;const text=search.value.trim().toLowerCase();articles.forEach(a=>{a.hidden=!a.dataset.search.toLowerCase().includes(text);if(!a.hidden)count++});document.querySelector('#count').textContent=count+' 种'}
search.addEventListener('input',filter);pose.addEventListener('change',()=>{articles.forEach(a=>{const img=a.querySelector('img');const file=img.src.replace(/-(neutral|action|hit|guard|enter|depart|phase)\.png$/,'-'+pose.value+'.png');img.src=file;img.parentElement.href=img.parentElement.href.replace(/-(neutral|action|hit|guard|enter|depart|phase)\.png$/,'-'+pose.value+'.png')})});filter();
</script></main></html>
"""
    (review / "index.html").write_text(content, encoding="utf-8")
    (review / "review-inputs.json").write_text(json.dumps({"probe": args.probe, "game": args.game,
        "sequences": args.sequences, "portrait_union_crops": portrait_crops, "sheets": sheets, "animations": animations}, ensure_ascii=False, indent=2), encoding="utf-8")
    links = re.findall(r'(?:href|src)="([^"]+)"', content)
    broken = [s for s in links if not s.startswith("#") and not (review / s).resolve().is_file()]
    if broken:
        raise SystemExit("Broken review links: " + repr(broken))
    print(json.dumps({"enemies": total, "sheets": len(sheets), "animations": len(animations),
        "encounters": len(encounter_cards), "review": str(review / "index.html")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
