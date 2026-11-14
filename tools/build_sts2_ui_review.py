"""Build the offline UI review from real Godot captures, never mock screenshots."""
import html
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "artifacts/verification/sts2-ui-rebuild-20261114"
OUT = ROOT / "output/sts2-ui-rebuild-20261114"


def main():
    entries = json.loads((EVIDENCE / "screens-responsive/capture.json").read_text(encoding="utf-8"))
    OUT.mkdir(parents=True, exist_ok=True)
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 16)
    for group in range((len(entries) + 11) // 12):
        sheet = Image.new("RGB", (1280, 702), "#14232e")
        draw = ImageDraw.Draw(sheet)
        for index, entry in enumerate(entries[group * 12:(group + 1) * 12]):
            x, y = index % 4 * 320, index // 4 * 234
            with Image.open(EVIDENCE / "screens-responsive" / (entry["name"] + ".png")) as source:
                source.thumbnail((316, 198))
                sheet.paste(source, (x + 2, y + 27))
            draw.text((x + 8, y + 5), entry["name"], font=font, fill="#e5d5b0")
        sheet.save(EVIDENCE / f"contact-{group + 1}.jpg", quality=92)

    options = "".join(f'<option value="{html.escape(e["name"])}">{html.escape(e["name"])}</option>' for e in entries)
    page = r'''<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#14232e"><title>二代 UI 重做 · 实机对照</title>
<style>
:root{color-scheme:dark;font:16px/1.65 "Microsoft YaHei",sans-serif;color:#ece4d3;background:#14232e}
*{box-sizing:border-box}body{margin:0 auto;padding:28px;max-width:1800px}h1{font-size:28px;color:#ead09a;margin:0 0 8px}h2{font-size:18px;color:#ead09a}p{max-width:1000px;color:#c4ced0}
a{color:#e7c77e}a:focus-visible,button:focus-visible,select:focus-visible{outline:3px solid #ffd67c;outline-offset:4px}
button,select{font:inherit;background:#2c4555;color:#f9efd9;border:1px solid #899397;border-radius:3px;min-height:44px;padding:6px 12px;touch-action:manipulation}button{cursor:pointer}button:hover{background:#405e70}button[aria-pressed="true"]{border:2px solid #e8bf69}
nav{display:flex;align-items:center;flex-wrap:wrap;gap:12px;margin:22px 0}select{max-width:100%}.compare{display:grid;grid-template-columns:1fr 1fr;gap:20px;align-items:start}.compare figure{margin:0;min-width:0}img{display:block;width:100%;height:auto;background:#0b1620;border:1px solid #5d717b}figcaption{padding:8px 0;color:#c4ced0}summary{cursor:pointer;color:#e5ca8c}details{margin:24px 0}.skip{position:absolute;left:-10000px}.skip:focus{left:12px;top:12px;background:#203746;padding:10px}
@media(max-width:900px){body{padding:16px}.compare{grid-template-columns:1fr}}
</style>
<a class="skip" href="#main">跳到实机画面</a>
<h1>按《杀戮尖塔2》重做 UI</h1>
<p>2026-11-14 · 左侧为本作真实 Godot 渲染，右侧为已归档的官方参考。可切换窗口尺寸及页面。人物使用原占位，人物资源工作仍暂停；背景和卡图沿用校园素材。</p>
<nav aria-label="选择实机画面"><label for="screen">页面与尺寸</label><select id="screen" name="screen">OPTIONS</select><button type="button" data-width="1280" aria-pressed="true">1280 × 800</button><button type="button" data-width="960" aria-pressed="false">960 × 600</button></nav>
<main id="main"><div class="compare"><figure><h2 id="actual-label">本作实渲</h2><a id="full" target="_blank" rel="noopener"><img id="actual" width="1280" height="800" alt="本作战斗界面实机截图"></a><figcaption id="caption" aria-live="polite"></figcaption></figure><figure><h2>官方参考 · 研究归档</h2><img id="reference" width="1280" height="800" alt="杀戮尖塔2官方战斗参考"><figcaption id="ref-caption">以实际场景构图、卡面层级和操作区位置对照。</figcaption></figure></div>
<details open><summary>本批变化与差异</summary><p>已重做窄顶栏、同构战场、底部扇形手牌、独立费用徽章、专注/牌堆/结束回合、暖纸路线、中央奖励、同场商品价签、侧方事件/休息选项及公共弹层。长文仍可停留阅读及 I 固定。官方参考不用于本作运行资产。</p><p>人物、任务图的正式造型仍未完成；原校园水彩场景与卡图在绘画语言、光照和材质细节上仍与二代有差异。行为测试通过不能代表视觉已完全一致。本页展示实际结果，供直接对照。</p></details>
<p><a href="../../docs/杀戮尖塔2_UI重做实施记录_20261114.md">实施与验证记录</a> · <a href="../../ui-plan/references/slay-the-spire-2/README.md">官方参考来源</a></p></main>
<script>
const select=document.querySelector('#screen'),actual=document.querySelector('#actual'),reference=document.querySelector('#reference');
function show(){const name=select.value;const url='../../artifacts/verification/sts2-ui-rebuild-20261114/screens-responsive/'+name+'.png';actual.src=url;actual.alt='本作实机截图 '+name;document.querySelector('#full').href=url;document.querySelector('#actual-label').textContent=name;document.querySelector('#caption').textContent='点击原图放大 · '+name;let ref='screenshot-0.jpg';if(name.startsWith('map')||name.startsWith('battle-map'))ref='map_qol.jpg';else if(name.startsWith('menu'))ref='mainmenu_qol.jpg';else if(name.startsWith('setup'))ref='screenshot-2.jpg';else if(name.includes('event'))ref='screenshot-5.jpg';else if(name.includes('shop')||name.startsWith('reward')||name.startsWith('grand')||name.startsWith('relic'))ref='merchant-cards-sequence.jpg';else if(name.includes('rest'))ref='map-rest-sequence.jpg';reference.src='../../ui-plan/references/slay-the-spire-2/'+ref;reference.alt='杀戮尖塔2官方参考 '+ref;document.querySelector('#ref-caption').textContent='已归档官方材料：'+ref;for(const b of document.querySelectorAll('[data-width]'))b.setAttribute('aria-pressed',String(name.endsWith('-'+b.dataset.width)));history.replaceState(null,'','#'+encodeURIComponent(name));}
select.addEventListener('change',show);for(const b of document.querySelectorAll('[data-width]'))b.addEventListener('click',()=>{const name=select.value.replace(/-\d+$/,'-'+b.dataset.width);if([...select.options].some(o=>o.value===name)){select.value=name;show();}});const requested=decodeURIComponent(location.hash.slice(1));select.value=[...select.options].some(o=>o.value===requested)?requested:'battle-1280';show();
</script></html>'''.replace("OPTIONS", options)
    (OUT / "preview.html").write_text(page, encoding="utf-8")
    print(json.dumps({"screens": len(entries), "contacts": (len(entries) + 11) // 12, "preview": str(OUT / "preview.html")}))


if __name__ == "__main__":
    main()
