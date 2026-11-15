"""Publish version 2 versus version 3 using real timestamped Godot frames."""
from pathlib import Path
from collections import Counter
import hashlib
import html
import json
import re

import build_actor_motion_review as media

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "artifacts/verification/actor-rig-refinement-20261115"
BEFORE = ROOT / "artifacts/verification/actor-rig-polish-20261114/render-04"
AFTER = EVIDENCE / "render-03"
OUT = EVIDENCE / "review"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    media.OUT = OUT
    before = json.loads((BEFORE / "report.json").read_text(encoding="utf-8"))
    after = json.loads((AFTER / "report.json").read_text(encoding="utf-8"))
    assert not before["failures"] and not after["failures"] and after["refinement"]
    labels = {
        "idle": "持续待机 · 呼吸 / 眨眼 / 纸页", "command-00": "真实出牌 · 完成量 6",
        "command-01": "真实再次出牌", "command-02": "真实结束回合 · 纸怪行动 / 人物受击",
        "command-04": "真实最后一击 · 受击 / 离场 / 奖励",
        "motion-action-effective4": "受控试镜 · 双方出手 · 实际有效 ×4",
        "motion-hit-effective4": "受控试镜 · 双方受击 · 实际有效 ×4",
        "motion-guard-effective4": "受控试镜 · 双方防御 · 实际有效 ×4",
        "motion-depart-effective4": "受控试镜 · 离场姿势 · 实际有效 ×4（非真实移除）",
        "motion-action-authored1-slow": "受控试镜 · 出手拆解 · 比默认慢 4 倍",
        "motion-hit-authored1-slow": "受控试镜 · 受击拆解 · 比默认慢 4 倍",
    }
    data, clips = {}, []
    for name in dict.fromkeys(f["sequence"] for f in after["frames"]):
        data[name] = {"label": labels[name],
            "before": [{"ms": f["elapsed_ms"], "file": "../../actor-rig-polish-20261114/render-04/" + f["file"]} for f in media.sequence(before, name)],
            "after": [{"ms": f["elapsed_ms"], "file": "../render-03/" + f["file"]} for f in media.sequence(after, name)]}
        clips.append(media.actual_timing_gif(after, name, AFTER))
        media.keyframe_sheet(after, name, AFTER)
    media.side_by_side([
        ("上一版 v2 · 地面与持物尚未修整", BEFORE / "battle-1280-100.png"),
        ("本轮 v3 · 关节 / 持物 / 地面", AFTER / "battle-1280-100.png"),
        ("本轮 v3 · 出手峰值（受控试镜）", AFTER / "pose-action-1280.png"),
        ("本轮 v3 · 960×600 / 150% 字号", AFTER / "battle-960-150.png"),
    ], OUT / "comparison.jpg")
    source_page = ROOT / "artifacts/verification/actor-rig-polish-20261114/review/index.html"
    page = source_page.read_text(encoding="utf-8")
    page = re.sub(r'<script id="motion-data" type="application/json">.*?</script>',
        lambda _: '<script id="motion-data" type="application/json">' + json.dumps(data, ensure_ascii=False).replace('</', '<\\/') + '</script>', page, flags=re.S)
    choices = ''.join(f'<option value="{name}">{label}</option>' for name, label in labels.items())
    page = re.sub(r'<select id="sequence">.*?</select>', '<select id="sequence">'+choices+'</select>', page, flags=re.S)
    page = re.sub(r'<p class="tag">.*?<nav>', '''<p class="tag">GODOT 4.7.2 · P01 林序 / N01 课后习题 · 2026-11-15 第二轮精修</p>
<h1>肩肘连贯，持物有跟随，角色站回地面</h1>
<p>这次比较的是上一版动作精修 v2 与本轮 v3。肩部使用连续权重，手掌、手腕与笔记本分开；新增轻微眨眼、纸扇弯曲和与站位一致的教室地面。先看正常速度，再切换人物特写检查关节与持物。</p><nav>''', page, flags=re.S)
    page = page.replace('精修前 · 首版原生骨架', '上一版 v2 · 第一轮动作精修')
    page = page.replace('精修后 · 蓄力 / 作用 / 回收 / 独立循环', '本轮 v3 · 关节 / 手腕与持物 / 眨眼 / 地面')
    page = page.replace('2026-11-14-actor-motion-polish-design.md', '2026-11-15-actor-refinement-design.md')
    page = page.replace('<option value="stage">完整战斗区</option>', '<option value="stage">完整战斗区</option><option value="hero">只看人物 / 持物</option><option value="enemy">只看纸怪 / 纸扇</option>')
    start = page.index('function panel(')
    end = page.index('\nasync function draw()', start)
    page = page[:start] + '''function panel(ctx,img){const mode=$('crop').value;if(mode==='stage'){ctx.canvas.width=1190;ctx.canvas.height=390;ctx.drawImage(img,0,0)}else if(mode==='hero'||mode==='enemy'){ctx.canvas.width=320;ctx.canvas.height=355;ctx.drawImage(img,mode==='hero'?55:680,0,320,355,0,0,320,355)}else{ctx.canvas.width=600;ctx.canvas.height=355;ctx.fillStyle='#15262e';ctx.fillRect(0,0,600,355);ctx.drawImage(img,70,0,270,355,0,0,270,355);ctx.drawImage(img,680,0,320,355,280,0,320,355)}}''' + page[end:]
    page = re.sub(r'<section id="still">.*?</section>', '''<section id="still"><h2>同场画面与实际窗口</h2><a href="comparison.jpg"><img src="comparison.jpg" alt="上一版与本轮角色精修及小窗口对照" style="width:100%;height:auto"></a><p>角色脚点、HUD、目标区与卡牌位置保持原样。新背景的墙地交界位于 y=342，角色脚下 y≈470 已是连续地板，并有接触与投射阴影。原API背景未按指定墙地比例输出，实际接入图经过分带重构，处理方法与原图均保留。</p></section>''', page, flags=re.S)
    result = f'''<section id="results"><h2>这一轮的实际改善与限制</h2>
<table><thead><tr><th>部位</th><th>本轮变化</th><th>仍待打磨</th></tr></thead><tbody>
<tr><td>肩肘与站姿</td><td>肩根保留连接，袖管随肘部连续弯曲；放松常驻含膝，重心移动时脚点保持</td><td>极限受击仍能看到袖片挤压；大角度转身需要替换绘图</td></tr>
<tr><td>手腕与笔记本</td><td>前臂、手掌、笔记本三件分开；托举与受击有独立跟随，接触点保留</td><td>目前只覆盖小角度；背面和完整手指动作尚未绘制</td></tr>
<tr><td>自然小动作</td><td>轻微眨眼与呼吸共存；减少动态立即恢复睁眼；纸扇尖端有独立弯曲</td><td>情绪表情和更多方向的攻击剪影仍不完整</td></tr>
<tr><td>场景融合</td><td>窗户/黑板退到背景，连续地面与阴影支撑原脚点</td><td>当前只制作这一处样板场景，其他房间需逐一核对</td></tr></tbody></table>
<p class="note">当前判断：Godot 原生二维骨架路线能继续实施。这一轮改善了肩肘断开、持物整片摆动和站位悬浮。与二代完整角色品质之间仍有替换绘图、动作剪影、表情和美术统一上的差距；本页交付评审，最终美术可行性由查看后的意见决定。</p>
<p class="stat">本轮 {len(after['checks'])} 项定向检查，零失败；5 条真实命令的领域 / RNG / revision / 事件一致；{len(after['screens'])} 张 PNG、{len(after['frames'])} 帧。旧 v1/v2 兼容与规则、完整 UI 回归见验证汇总。采集回读不是性能基准。</p>
<p><a href="../render-03/report.json">实渲报告</a> · <a href="../verification-summary.json">完整验证汇总</a> · <a href="../render-03.run.json">命令与输入 hash</a> · <a href="../api-ledger.json">API实际记录</a></p>
<p>本轮成功新增背景 1 张，累计 6 / 200 张。第一次生成请求被服务拒绝且无图片，随后以实际上传的旧教室图编辑成功；API未返回计费金额。角色新增拆件来自原PNG的本地编辑，未重绘身份。独立启动：<code>powershell -NoProfile -ExecutionPolicy Bypass -File tools/start_actor_rig_refinement.ps1</code>。默认入口与旧版本资源保留，存档隔离。</p></section>'''
    page = re.sub(r'<section id="results">.*?</section>', lambda _: result, page, flags=re.S)
    page = page.replace('../resource-review.md', '../../actor-rig-polish-20261114/resource-review.md')
    page = page.replace('../research/', '../../actor-rig-polish-20261114/research/')
    page = page.replace('本版参考这种层次关系', '前一版按这种层次关系实现独立循环；本轮继续沿用，并增加手腕、持物和纸扇尖端的次级跟随。原实现')
    page = page.replace('原实现，将', '原实现将')
    page = page.replace('../render-04/', '../render-03/')
    # Replace details with this run's real frame counts and screenshots.
    clip_html = ''.join(f'<figure><a href="{c["file"]}"><img loading="lazy" src="{c["name"]}-strip.jpg" alt="{labels[c["name"]]}关键帧"></a><figcaption>{labels[c["name"]]} · {c["frames"]} 帧 · <a href="{c["file"]}">播放独立GIF</a></figcaption></figure>' for c in clips)
    screen_html = ''.join(f'<figure><a href="../render-03/{s["name"]}.png"><img loading="lazy" src="../render-03/{s["name"]}.png" alt="{html.escape(s["name"])}"></a><figcaption>{html.escape(s["name"])} · {"受控姿态" if s["kind"] == "controlled_pose_preview" else "真实战斗UI"}</figcaption></figure>' for s in after['screens'])
    page = re.sub(r'<details>.*?</details>', lambda m: '<details><summary>连续样本关键帧与独立GIF（受控试镜已标明）</summary><div class="grid">'+clip_html+'</div></details>', page, count=1, flags=re.S)
    pattern = r'<details><summary>全部两尺寸、三字号与姿态实渲</summary>.*?</details>'
    page = re.sub(pattern, '<details><summary>全部两尺寸、三字号与姿态实渲</summary><div class="grid">'+screen_html+'</div></details>', page, flags=re.S)
    (OUT / 'index.html').write_text(page, encoding='utf-8')
    media.save_json(OUT / 'sequences.json', clips)
    media.save_json(OUT / 'manifest.json', {'before': BEFORE.relative_to(ROOT).as_posix(), 'after': AFTER.relative_to(ROOT).as_posix(),
        'source_template': source_page.relative_to(ROOT).as_posix(), 'sequence_counts':dict(Counter(f['sequence'] for f in after['frames'])),
        'clips':clips,'all_media_are_real_godot_capture':True,'playback':'actual capture timestamps; normal and 0.25x',
        'default_game_effective_speed':4,'before_report_sha256':hashlib.sha256((BEFORE/'report.json').read_bytes()).hexdigest(),
        'after_report_sha256':hashlib.sha256((AFTER/'report.json').read_bytes()).hexdigest()})
    print(json.dumps({'review':str(OUT),'clips':len(clips),'frames':len(after['frames'])},ensure_ascii=False))


if __name__ == '__main__':
    main()
