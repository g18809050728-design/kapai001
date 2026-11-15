"""Compare v3 and v4 with their actual timestamped Godot captures."""
from pathlib import Path
import argparse
from collections import Counter
import hashlib
import html
import json
import re

import build_actor_motion_review as media

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / "artifacts/verification/actor-rig-drawings-20261115"
BEFORE = ROOT / "artifacts/verification/actor-rig-refinement-20261115/render-03"
OUT = EV / "review"
LABELS = {
    "idle": "持续待机 · 呼吸 / 眨眼 / 纸页",
    "command-00": "真实出牌 · 完成量 6", "command-01": "真实再次出牌",
    "command-02": "真实结束回合 · 纸怪刺击 / 人物受击",
    "command-04": "真实最后一击 · 纸面受击 / 离场 / 奖励",
    "motion-action-effective4": "受控试镜 · 双方出手 · 默认有效 ×4",
    "motion-hit-effective4": "受控试镜 · 双方受击 · 默认有效 ×4",
    "motion-guard-effective4": "受控试镜 · 双方防御 · 默认有效 ×4",
    "motion-depart-effective4": "受控试镜 · 离场姿势 · 默认有效 ×4（非真实移除）",
    "motion-action-authored1-slow": "受控试镜 · 转体 / 伸手 / 合扇拆解 · 比默认慢 4 倍",
    "motion-hit-authored1-slow": "受控试镜 · 受击表情 / 折痕拆解 · 比默认慢 4 倍",
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", default="render-03")
    args = parser.parse_args()
    after_dir = EV / args.run
    before = json.loads((BEFORE / "report.json").read_text(encoding="utf-8"))
    after = json.loads((after_dir / "report.json").read_text(encoding="utf-8"))
    assert after["drawings"] and not after["failures"]
    OUT.mkdir(parents=True, exist_ok=True)
    media.OUT = OUT
    data, clips = {}, []
    for name in dict.fromkeys(f["sequence"] for f in after["frames"]):
        data[name] = {"label": LABELS[name],
            "before": [{"ms": f["elapsed_ms"], "file": "../../actor-rig-refinement-20261115/render-03/" + f["file"]} for f in media.sequence(before, name)],
            "after": [{"ms": f["elapsed_ms"], "file": f"../{args.run}/" + f["file"]} for f in media.sequence(after, name)]}
        clips.append(media.actual_timing_gif(after, name, after_dir))
        media.keyframe_sheet(after, name, after_dir)
    media.side_by_side([
        ("上一版 v3 · 关节与持物", BEFORE / "pose-action-1280.png"),
        ("本轮 v4 · 转体与笔尖出手", after_dir / "pose-action-1280.png"),
        ("本轮 v4 · 受击表情和纸面折痕", after_dir / "pose-hit-1280.png"),
        ("本轮 v4 · 960×600 / 150% 字号", after_dir / "battle-960-150.png"),
    ], OUT / "comparison.jpg")
    source = ROOT / "artifacts/verification/actor-rig-refinement-20261115/review/index.html"
    page = source.read_text(encoding="utf-8")
    page = re.sub(r"<title>.*?</title>", "<title>P01 / N01 · 第三轮动作补绘前后对照</title>", page)
    page = re.sub(r'<script id="motion-data" type="application/json">.*?</script>',
        lambda _: '<script id="motion-data" type="application/json">' + json.dumps(data, ensure_ascii=False).replace('</', '<\\/') + '</script>', page, flags=re.S)
    page = re.sub(r'<select id="sequence">.*?</select>', '<select id="sequence">' + ''.join(f'<option value="{name}"' + (' selected' if name == 'command-00' else '') + f'>{label}</option>' for name, label in LABELS.items()) + '</select>', page, flags=re.S)
    page = re.sub(r'<p class="tag">.*?<nav>', '''<p class="tag">GODOT 4.7.2 · P01 林序 / N01 课后习题 · 2026-11-15 第三轮精修</p>
<h1>让转身、出手和受击有自己的绘图</h1>
<p>左侧为上一版 v3，右侧为本轮 v4。人物补侧前蓄力、侧向出手、受击表情与伸笔手势；纸怪补合扇蓄力、水平刺击和受击折痕。两侧都是实际引擎连续帧，按各自采集时间播放。先看默认速度，再选人物或敌怪特写检查接缝与过渡。</p><nav>''', page, flags=re.S)
    page = page.replace("上一版 v2 · 第一轮动作精修", "上一版 v3 · 关节 / 手腕与持物 / 地面")
    page = page.replace("本轮 v3 · 关节 / 手腕与持物 / 眨眼 / 地面", "本轮 v4 · 转体 / 明确出手 / 受击表情 / 折痕")
    page = page.replace("2026-11-15-actor-refinement-design.md", "2026-11-15-actor-drawings-design.md")
    page = page.replace("受控试镜只展示骨架", "受控试镜展示局部绘图与骨架动作")
    page = re.sub(r'<section id="still">.*?</section>', '''<section id="still"><h2>全窗口动作与紧凑尺寸</h2><a href="comparison.jpg"><img src="comparison.jpg" alt="v3与v4同场动作以及小窗口对照" style="width:100%;height:auto"></a><p>HUD、脚点、目标命中区、手牌与教室沿用上一版。出手抬高并越过笔记本，避免像在屏幕后打字；托举手与笔记本的接触继续保留。受击折痕属于局部纸面绘图，夹子和散页仍由各自骨骼跟随。</p></section>''', page, flags=re.S)
    result = f'''<section id="results"><h2>这一轮的改善与仍有的差距</h2>
<table><thead><tr><th>部位</th><th>本轮变化</th><th>剩余限制</th></tr></thead><tbody>
<tr><td>转身与出手</td><td>侧前蓄力转为侧向专注；胸口和前臂替换绘图跟随原骨架，笔尖水平越过笔记本上方</td><td>只覆盖这套动作的中等角度转体；完整背身、走位和更大幅度姿势尚无绘图</td></tr>
<tr><td>表情与受击</td><td>人物短暂闭眼咬牙后恢复；纸怪眼形和正面折痕随实际受击切换</td><td>当前表情种类有限；极端袖片挤压和高速细节仍需美术继续核收</td></tr>
<tr><td>纸怪刺击</td><td>蓄力时合扇、作用时张开；笔尖朝向对手，回收与夹子、散页错峰</td><td>蓄力和作用正面绘图差异仍偏小；尚未覆盖非纸片敌怪和多阶段Boss</td></tr>
<tr><td>动作连续性</td><td>同一部件画布注册；局部短混合从实际状态接续，减少动态和结束动作立即恢复中立</td><td>局部图像混合在刻意慢放时仍可能看到轻微叠影；全量生产需要人工绘图与注册核收</td></tr></tbody></table>
<p class="note">实践判断：这一套原生二维骨架加局部替换绘图可以继续推进。当前改善了仅靠摆动造成的单一朝向和弱出手轮廓；还不能据此宣称已经达到《杀戮尖塔2》的最终美术水平，或代表全部角色/敌怪均已验证。</p>
<p class="stat">本轮 {len(after['checks'])} 项定向检查、零失败；5 条真实命令的领域 / RNG / revision / 事件一致；{len(after['screens'])} 张 PNG、{len(after['frames'])} 连续帧。实际回归见汇总；采集回读不是性能基准。</p>
<p><a href="../{args.run}/report.json">实渲报告</a> · <a href="../verification-summary.json">验证汇总</a> · <a href="../{args.run}.run.json">命令与输入 hash</a> · <a href="../api-ledger.json">API记录</a> · <a href="../parts-contact-final.jpg">16件派生图</a> · <a href="../raw-contact.jpg">6张API输出</a></p>
<p>本轮 API 编辑成功 6 张，5 张局部表接入，1 张头部首版保留为返工记录。累计 12 / 200 张；每次实际上传两张现有参考，费用未由服务返回。首轮339项行为通过后，画面检查发现手势被笔记本挡住，继续抬高手臂并修正层级；早期记录保留。本页引用最终批次，不把早期结果当作视觉完成。</p>
<p>独立启动：<code>powershell -NoProfile -ExecutionPolicy Bypass -File tools/start_actor_rig_drawings.ps1</code>。默认入口、旧资源与真实玩家存档保持原样；试玩使用独立存档。</p></section>'''
    page = re.sub(r'<section id="results">.*?</section>', lambda _: result, page, flags=re.S)
    clip_html = ''.join(f'<figure><a href="{c["file"]}"><img loading="lazy" src="{c["name"]}-strip.jpg" alt="{LABELS[c["name"]]}关键帧"></a><figcaption>{LABELS[c["name"]]} · {c["frames"]} 帧 · <a href="{c["file"]}">播放独立GIF</a></figcaption></figure>' for c in clips)
    screen_html = ''.join(f'<figure><a href="../{args.run}/{s["name"]}.png"><img loading="lazy" src="../{args.run}/{s["name"]}.png" alt="{html.escape(s["name"])}"></a><figcaption>{html.escape(s["name"])} · {"受控姿态" if s["kind"] == "controlled_pose_preview" else "真实战斗UI"}</figcaption></figure>' for s in after['screens'])
    page = re.sub(r'<details>.*?</details>', lambda _: '<details><summary>连续样本关键帧与独立GIF（受控试镜已标明）</summary><div class="grid">' + clip_html + '</div></details>', page, count=1, flags=re.S)
    page = re.sub(r'<details><summary>全部两尺寸、三字号与姿态实渲</summary>.*?</details>', lambda _: '<details><summary>全部两尺寸、三字号与姿态实渲</summary><div class="grid">' + screen_html + '</div></details>', page, flags=re.S)
    (OUT / 'index.html').write_text(page, encoding='utf-8')
    media.save_json(OUT / 'sequences.json', clips)
    media.save_json(OUT / 'manifest.json', {'before': BEFORE.relative_to(ROOT).as_posix(), 'after': after_dir.relative_to(ROOT).as_posix(),
        'source_template': source.relative_to(ROOT).as_posix(), 'sequence_counts': dict(Counter(f['sequence'] for f in after['frames'])), 'clips': clips,
        'all_media_are_real_godot_capture': True, 'playback': 'actual timestamps; 1x and 0.25x viewer; game effective speed remains 4',
        'before_report_sha256': hashlib.sha256((BEFORE / 'report.json').read_bytes()).hexdigest(),
        'after_report_sha256': hashlib.sha256((after_dir / 'report.json').read_bytes()).hexdigest()})
    print(json.dumps({'review': str(OUT), 'clips': len(clips), 'frames': len(after['frames'])}, ensure_ascii=False))


if __name__ == '__main__':
    main()
