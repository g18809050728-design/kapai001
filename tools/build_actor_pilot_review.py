"""Build an offline evidence gallery, actual-timing GIFs and a production inventory."""
from pathlib import Path
from collections import Counter
import csv
import hashlib
import html
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "artifacts/verification/actor-rig-pilot-20261114"
RENDER = EVIDENCE / "render-05"
OUT = EVIDENCE / "review"
REF = ROOT / "ui-plan/references/slay-the-spire-2"
RAW = ROOT / "output/imagegen/actor-rig-pilot-20261114"


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def font(size):
    return ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", size)


def labeled_tiles(items, destination, columns=2, width=640):
    tiles = []
    for label, path in items:
        im = Image.open(path).convert("RGB")
        im.thumbnail((width, 440))
        tile = Image.new("RGB", (width + 24, 485), "#152932")
        tile.paste(im, ((tile.width - im.width)//2, 38))
        ImageDraw.Draw(tile).text((12, 7), label, fill="#f2ddaf", font=font(17))
        tiles.append(tile)
    sheet = Image.new("RGB", ((width+24)*columns, 485*((len(tiles)+columns-1)//columns)), "#152932")
    for i, tile in enumerate(tiles):
        sheet.paste(tile, ((i % columns)*tile.width, (i//columns)*tile.height))
    sheet.save(destination)


def inventory():
    manifest_path = ROOT / "data/four_year/manifests/campus_four_year.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    rows = []
    for kind, file in [("character", "characters"), ("unit", "units"), ("task", "tasks")]:
        definitions = json.loads((ROOT / f"data/four_year/definitions/{file}.json").read_text(encoding="utf-8-sig"))
        for item in definitions:
            if item["id"] not in manifest["enabled"][kind]:
                continue
            rig = "native-human" if kind in ["character", "unit"] else "pending-art-family-review"
            status = "tested-pilot" if item["id"] in ["P01", "N01"] else "not-produced"
            rows.append({"kind": kind, "id": item["id"], "name_key": item.get("name_key", ""),
                "task_kind": item.get("kind", ""), "phase_count": len(item.get("phases", [])) or 1,
                "phase_keys": "|".join(p.get("phase_key", "") for p in item.get("phases", [])),
                "proposed_rig_family": "native-paper" if item["id"] == "N01" else rig,
                "status": status})
    write_json(EVIDENCE / "rollout-inventory.json", {"manifest": manifest_path.relative_to(ROOT).as_posix(),
        "manifest_sha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
        "counts": dict(Counter(r["kind"] for r in rows)),
        "task_kinds": dict(Counter(r["task_kind"] for r in rows if r["kind"] == "task")),
        "task_phases": sum(r["phase_count"] for r in rows if r["kind"] == "task"), "items": rows})
    with (EVIDENCE / "rollout-inventory.csv").open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    report = json.loads((RENDER / "report.json").read_text(encoding="utf-8"))
    if report["failures"]:
        raise SystemExit("Do not publish a failed capture as final evidence")
    inventory()
    api_images = []
    for path in RAW.glob("*.png"):
        im = Image.open(path)
        api_images.append({"file": path.relative_to(ROOT).as_posix(), "size": list(im.size),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    write_json(EVIDENCE / "api-usage.json", {"authorized_ceiling": 200, "successful_api_images": len(api_images),
        "remaining_ceiling": 200-len(api_images), "derived_parts_not_api_calls": 18, "images": api_images,
        "cost": "provider billing amount not available; no price invented"})
    labeled_tiles([
        ("官方二代归档战斗参考", REF / "screenshot-0.jpg"),
        ("同一真实战斗 · 原在用图片", RENDER / "baseline-1280.png"),
        ("本批原生骨架 · 1280×800", RENDER / "battle-1280-100.png"),
        ("本批原生骨架 · 960×600 / 150%", RENDER / "battle-960-150.png"),
    ], OUT / "comparison.jpg")
    sequence_files = []
    for name in dict.fromkeys(f["sequence"] for f in report["frames"]):
        frames = [f for f in report["frames"] if f["sequence"] == name]
        images = [Image.open(RENDER / f["file"]).convert("RGB") for f in frames]
        durations = [max(20, frames[i+1]["elapsed_ms"]-f["elapsed_ms"]) if i+1 < len(frames) else 90 for i, f in enumerate(frames)]
        gif = OUT / f"{name}.gif"
        images[0].save(gif, save_all=True, append_images=images[1:], duration=durations, loop=0, optimize=True)
        sample_indices = sorted(set(round((len(frames)-1)*i/5) for i in range(6)))
        panels = []
        for i in sample_indices:
            panel = images[i].copy().resize((952, 312))
            canvas = Image.new("RGB", (976, 350), "#152932")
            canvas.paste(panel, (12,32))
            ImageDraw.Draw(canvas).text((12,4), f"{name} · {frames[i]['elapsed_ms']} ms · 连续实渲裁片", font=font(16), fill="#f2ddaf")
            panels.append(canvas)
        strip = Image.new("RGB", (976*2, 350*((len(panels)+1)//2)), "#152932")
        for i,panel in enumerate(panels): strip.paste(panel,((i%2)*976,(i//2)*350))
        strip.save(OUT / f"{name}-strip.jpg", quality=90)
        sequence_files.append({"name":name,"frame_count":len(frames),"recorded_span_ms":frames[-1]["elapsed_ms"]-frames[0]["elapsed_ms"],
            "gif":gif.name,"strip":f"{name}-strip.jpg","timing":"actual capture timestamps; readback is not realtime performance"})
    write_json(OUT / "sequences.json", sequence_files)
    cards = []
    for screen in report["screens"]:
        name = screen["name"]
        tag = "受控姿态预览" if screen["kind"] == "controlled_pose_preview" else "真实战斗 UI"
        cards.append(f'<figure><a href="../render-05/{name}.png"><img loading="lazy" src="../render-05/{name}.png"></a><figcaption>{html.escape(name)} · {tag}</figcaption></figure>')
    clips = []
    for sequence in sequence_files:
        clips.append(f'<figure><img loading="lazy" src="{sequence["gif"]}"><figcaption>{sequence["name"]} · {sequence["frame_count"]} 帧 · 按实际采集间隔播放 · <a href="{sequence["strip"]}">关键帧联系表</a></figcaption></figure>')
    page = f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Godot 人物 / 敌怪动作实践</title><style>
body{{background:#102129;color:#e7ece8;font:16px/1.65 "Microsoft YaHei",sans-serif;margin:0 auto;max-width:1440px;padding:24px}}h1,h2{{color:#efd4a0}}a{{color:#acd8f4}}.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(420px,1fr));gap:18px}}figure{{margin:0 0 24px;background:#1c323b;padding:12px}}img{{width:100%;height:auto}}figcaption{{padding-top:8px}}p{{max-width:1080px}}code{{background:#203b45;padding:3px 6px}}
</style><h1>Godot 原生骨架：人物与敌怪实践</h1>
<p>2026-11-14 · 实测 Godot 4.7.2 / GL Compatibility。P01 林序与 N01 课后习题，种子 32 的真实首战。当前为隔离技术样板；默认入口保留，尚未达到二代最终美术 / 动作品质。</p>
<p>{len(report['checks'])} 项定向检查通过；5 条真实命令与独立无骨架领域基准的状态、RNG、revision、事件记录一致。19 张实渲和 {len(report['frames'])} 帧连续样本。API 实际生成 {len(api_images)} / 200 张，部件抽取不再调用 API。</p>
<p><a href="../../../../docs/plans/2026-11-14-actor-rig-feasibility-plan.md">完整方案</a> · <a href="../render-05/report.json">实测记录</a> · <a href="../resource-review.md">资源核对</a> · <a href="../rollout-inventory.csv">71 个生产实体映射</a></p>
<h2>官方参考 / 原图 / 新骨架同场对照</h2><img src="comparison.jpg">
<p>已核对真实轮廓与动作关系。当前人物偏细长、画风细节偏密；肩肘接缝、面部 / 转体替换、场景地面承托以及大动作剪影仍需生产级美术与动画打磨。参考归档无最新构建号，本报告不冒充最新版本逐帧复现。</p>
<h2>持续待机与真实发布事件</h2>{''.join(clips)}
<p>以上为实际 Godot 渲染裁片；GIF 使用记录的采集间隔。命令输入 / 发布事件 / rig cue 数量可在实测记录中核对。截图回读、JPEG 写盘与 GPU 型号影响采样，不用这些样本宣称最低配置帧率。</p>
<h2>两尺寸、三字号与受控姿态</h2><div class="grid">{''.join(cards)}</div>
<h2>复现</h2><p>在项目根目录运行 <code>powershell -ExecutionPolicy Bypass -File tools/start_actor_rig_pilot.ps1</code>，用真实卡牌操作。验证 / 留证命令及阶段计划见完整方案。失败迭代保留在同级目录，没有把失败画面当作最终证据。</p></html>'''
    (OUT / "index.html").write_text(page, encoding="utf-8")
    print(json.dumps({"review":str(OUT),"sequences":sequence_files,"api_images":len(api_images)},ensure_ascii=False))


if __name__ == "__main__":
    main()
