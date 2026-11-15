"""Reviewer-facing comparisons made exclusively from actual Godot captures."""
import argparse
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[1]
EV=ROOT/'artifacts/verification/actor-lin-polish-20261115'
FONT='C:/Windows/Fonts/msyh.ttc'

def panels(items,dest,cell=(800,1100),crop=None):
    result=Image.new('RGB',(cell[0]*len(items),cell[1]+64),'#e6dfd1')
    d=ImageDraw.Draw(result);f=ImageFont.truetype(FONT,24)
    for i,(label,path) in enumerate(items):
        im=Image.open(path).convert('RGB')
        if crop:im=im.crop(crop)
        im.thumbnail(cell,Image.Resampling.LANCZOS)
        result.paste(im,(cell[0]*i+(cell[0]-im.width)//2,64))
        d.text((cell[0]*i+24,18),label,fill='#26353e',font=f)
    result.save(dest,quality=96)

def main():
    p=argparse.ArgumentParser();p.add_argument('probe');a=p.parse_args()
    source=EV/a.probe;out=EV/'review';out.mkdir(exist_ok=True)
    panels([('原 V5 · Godot 放大',source/'v5-face-enlarged.png'),('精修 V12 · Godot 放大',source/'v12-face-enlarged.png')],
        out/'face-before-after.jpg',(900,1150),(150,150,1050,1300))
    panels([('林序 原 V5',source/'v5-face-enlarged.png'),('林序 精修 V12',source/'v12-face-enlarged.png'),('沈见章 V10 · 画风参照',source/'shen-face-enlarged.png')],
        out/'style-comparison.jpg',(660,850),(150,150,1050,1300))
    panels([('原 V5 · 完整人物',source/'v5-neutral.png'),('精修 V12 · 完整人物',source/'v12-neutral.png'),('沈见章 V10 · 画风参照',source/'shen-neutral.png')],
        out/'fullbody.jpg',(600,840))
    panels([('原 V5 · 衣领/手部',source/'v5-neutral.png'),('精修 V12 · 衣领/手部',source/'v12-neutral.png')],
        out/'garment-before-after.jpg',(850,800),(270,190,970,750))
    panels([(pose,source/f'v12-{pose}.png') for pose in ['neutral','action','hit','guard','phase','enter','depart']],
        out/'poses.jpg',(360,480))
    (out/'index.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>林序精修 V12</title><style>body{margin:0;background:#20292b;color:#f4ead5;font:17px/1.7 system-ui}main{max-width:1300px;margin:auto;padding:24px}img{max-width:100%;height:auto}a{color:#dac78b}figure{margin:24px 0}figcaption{margin:10px 0}button{padding:10px 20px;font:inherit;background:#d8c996;border:0;border-radius:6px}p{max-width:900px}</style><main><h1>林序 · 精修 V12</h1><p>以林序原 V5 为身份、体态和动作基准，沈见章 V10 为画风参照。以下对比全部来自 Godot 实际渲染；点击原图可放大。其余三位角色资源保持。</p><figure><figcaption>先看脸、眼镜、发丝和颈部：左为原版，右为精修。</figcaption><a href="face-before-after.jpg"><img src="face-before-after.jpg"></a></figure><figure><figcaption>与沈见章的画风对照。</figcaption><a href="style-comparison.jpg"><img src="style-comparison.jpg"></a></figure><figure><figcaption>完整人物比例与站姿。</figcaption><a href="fullbody.jpg"><img src="fullbody.jpg"></a></figure><figure><figcaption>衣领、拉链、衣褶和手部细节。</figcaption><a href="garment-before-after.jpg"><img src="garment-before-after.jpg"></a></figure><figure><figcaption>六类动作与中立姿态。2D局部绘图短过渡仍可能看出换面，不把它宣称为三维连续转体。</figcaption><a href="poses.jpg"><img src="poses.jpg"></a></figure><p><a href="../game-final-01/P01-setup-1280-100.png">正式选角</a> · <a href="../game-final-01/P01-battle-1280-100.png">正式战斗</a> · <a href="../verification-summary.json">验证记录</a></p></main></html>''',encoding='utf-8')
    print(out.relative_to(ROOT))

if __name__=='__main__':main()
