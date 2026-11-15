"""Make a local review index from retained Godot screenshots, without altering game assets."""
from html import escape
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / 'artifacts/verification/compendium-20261115'


def main():
    review = EV / 'review'
    review.mkdir(exist_ok=True)
    manifest = json.loads((EV / 'capture-verified/manifest.json').read_text(encoding='utf-8'))
    font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 16)
    sheet = Image.new('RGB', (1600, 1560), '#070b11')
    draw = ImageDraw.Draw(sheet)
    monsters = [item for item in manifest['captures'] if item['kind'] == 'monster-detail']
    for index, item in enumerate(monsters):
        with Image.open(EV / 'capture-verified' / item['file']) as image:
            # The image is a real window capture; this crop only makes the review sheet.
            crop = image.convert('RGB').crop((32, 210, 405, 650))
            crop.thumbnail((150, 215))
            left, top = index % 10 * 160, index // 10 * 260
            sheet.paste(crop, (left + (160 - crop.width) // 2, top))
            label = item['ids'][0]
            label_font = font
            if draw.textlength(label, font=font) > 152:
                label_font = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 12)
                label = label.replace('FY_ROUTE_', 'FY_ROUTE_\n')
            draw.text((left + 4, top + 220), label, font=label_font, fill='#dcc599')
    sheet.save(review / 'all-monsters.jpg', quality=93)

    def figure(folder, name, caption):
        path = '../' + folder + '/' + name
        return f'<figure><a href="{escape(path)}" target="_blank"><img loading="lazy" src="{escape(path)}" alt="{escape(caption)}"></a><figcaption>{escape(caption)}</figcaption></figure>'

    groups = []
    highlights = [
        ('cards-1280-100.png', '卡牌画廊 · 1280×800 / 100%'),
        ('monsters-1280-100.png', '怪物画廊 · 1280×800 / 100%'),
        ('cards-960-150.png', '小窗口大字号：卡牌滚动浏览，固定返回/分页'),
        ('monster-detail-960-150.png', '大四首领：完整形象、分阶段说明及固定关闭'),
        ('monster-detail-bottom-960-150.png', '大四首领：长文滚动至最后阶段及来源'),
        ('menu-960-150.png', '主菜单：聚焦图鉴后自动滚入可见区域'),
    ]
    groups.append('<h2>实际画面</h2><div class="grid">' + ''.join(figure('render-verified', name, caption) for name, caption in highlights) + '</div>')
    for kind, title in [('cards', '全部卡牌分页'), ('monsters', '全部怪物分页'), ('monster-detail', '60 种怪物详情'), ('card-variant', '14 张考试牌的基础、升级与考试版本'), ('long-detail', '小窗口长文与版本详情')]:
        items = [item for item in manifest['captures'] if item['kind'] == kind]
        content = ''.join(figure('capture-verified', item['file'], ' / '.join(item['ids']) + (f' · 版本 {item["variant"]}' if item['variant'] >= 0 else '') + ' · ' + item['file']) for item in items)
        groups.append(f'<details><summary>{escape(title)}（{len(items)} 张实渲）</summary><div class="grid">{content}</div></details>')
    matrix = []
    for width in [1280, 960]:
        for scale in [100, 125, 150]:
            for key, label in [('cards', '卡牌画廊'), ('monsters', '怪物画廊'), ('card-detail', '卡牌详情'), ('monster-detail', '怪物详情')]:
                matrix.append(figure('render-verified', f'{key}-{width}-{scale}.png', f'{label} · {width} / {scale}%'))
    groups.append('<details><summary>双尺寸、三字号矩阵</summary><div class="grid">' + ''.join(matrix) + '</div></details>')
    html = '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>游戏内图鉴实渲</title><style>
body{margin:0 auto;padding:32px;max-width:1600px;background:#0a1017;color:#e9dfc9;font:17px/1.7 system-ui,"Microsoft YaHei",sans-serif}h1,h2,summary{color:#d9b878}h1{margin-bottom:8px}a{color:#efcf95}p{max-width:1000px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(330px,1fr));gap:20px}figure{margin:0 0 20px}img{width:100%;height:auto;display:block;border:1px solid #334651}figcaption{font-size:14px;overflow-wrap:anywhere;padding:8px 2px}details{border-top:1px solid #334651;padding:20px 0}summary{cursor:pointer;font-size:21px;margin-bottom:18px}.sheet{max-width:1600px}.note{border-left:3px solid #d9b878;padding-left:18px}
</style><h1>全卡牌与怪物图鉴</h1><p>在游戏主菜单点击“图鉴”。174 种卡牌、60 种怪物全部开放；支持搜索、分类筛选、分页，以及卡牌版本与怪物形象/动作/机制详情。以下均为 Godot 实际画面；本页只用于查看实施证据。</p><p><a href="../README.md">验证记录与运行命令</a> · <a href="../capture-verified/manifest.json">完整 ID 与截图清单</a></p><p class="note">画廊与详情沿用游戏卡框、费用符号、字体和导航。与归档二代图鉴相比，目前使用卡牌/怪物两页签；怪物详情以左右分栏及前后切换呈现，仍未复刻官方右侧连续怪物名单、完整动作目录及红色返回带。小窗口大字号下画廊需要纵向滚动。</p><h2>全部怪物形象</h2><a href="all-monsters.jpg" target="_blank"><img class="sheet" src="all-monsters.jpg" alt="60 种怪物的实际详情画面裁切总览"></a>'''
    html += ''.join(groups)
    html += '<details><summary>归档官方参考</summary><p>仅作构图对照，非本作资源。</p>' + figure('references', 'bestiary_available.jpg', '归档官方图鉴入口') + figure('references', 'bestiary-contact.jpg', '归档官方怪物详情与动作目录') + '</details></html>'
    (review / 'index.html').write_text(html, encoding='utf-8')
    print(json.dumps({'review': str(review / 'index.html'), 'monsters': len(monsters), 'captures': len(manifest['captures'])}, ensure_ascii=False))


if __name__ == '__main__':
    main()
