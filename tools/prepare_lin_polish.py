"""Record the accepted production baseline before P01's focused repaint."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import zipfile
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
EV = ROOT / 'artifacts/verification/actor-lin-polish-20261115'
RAW = ROOT / 'output/imagegen/actor-lin-polish-20261115'

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    EV.mkdir(parents=True, exist_ok=True)
    RAW.mkdir(parents=True, exist_ok=True)
    (RAW / '.gdignore').write_text('', encoding='utf-8')
    paths = ['agent.md', '实施计划与验收基线.md', 'docs/界面层契约.md',
             '动作或者图片描述/需求台账.md', 'src/ui/character_art.gd',
             'assets/art/characters/P01/neutral.png', 'assets/art/characters/P01/portrait.png',
             'assets/art/characters/source.json']
    with zipfile.ZipFile(EV / 'before.zip', 'x', zipfile.ZIP_DEFLATED) as z:
        for name in paths:
            z.write(ROOT / name, name)
    protected = {}
    for folder in ['src','data','tests','assets/art','tools']:
        for p in (ROOT / folder).rglob('*'):
            if p.is_file() and p.suffix in ['.gd','.gdshader','.tscn','.json','.png','.py','.ps1']:
                name = p.relative_to(ROOT).as_posix()
                if name not in paths:
                    protected[name] = sha(p)
    (EV / 'baseline.json').write_text(json.dumps({'created_utc': datetime.now(timezone.utc).isoformat(),
        'before_files': {p: sha(ROOT / p) for p in paths}, 'protected': protected,
        'api_successful_before': 38, 'api_limit': 200}, ensure_ascii=False, indent=2), encoding='utf-8')
    for hero in ['P01', 'P03']:
        old = Image.open(ROOT / f'assets/art/characters/{hero}/neutral.png').convert('RGBA')
        bg = Image.new('RGBA', (1024,1536), '#ff00ff')
        bg.alpha_composite(old, (0,68))
        bg.convert('RGB').save(RAW / f'{hero.lower()}-identity.png')
    lin = Image.open(ROOT / 'assets/art/characters/P01/neutral.png').convert('RGBA')
    shen = Image.open(ROOT / 'assets/art/characters/P03/neutral.png').convert('RGBA')
    for name, image, box in [('lin',lin,(400,35,680,345)),('shen',shen,(416,150,631,405))]:
        crop=image.crop(box); bg=Image.new('RGBA',crop.size,'#d9d7ce'); bg.alpha_composite(crop)
        bg.convert('RGB').resize((720,800),Image.Resampling.LANCZOS).save(EV/f'before-{name}-face.jpg',quality=96)
    paragraph = ('2026-11-15当前§0.20.26：按用户“林放大难看、与沈风格保持”的反馈精修P01。'
        '以P01原V5身份/已认可比例与P03V10画风为实际上传参考，制作独立V12，核对放大五官、眼镜/发丝、'
        '衣领/衣褶和手部，再接入正式人物路由与同源头像。P02V8/P03V10/P04V11及历史资源保留。'
        '本轮实施与证据见[精修设计](docs/plans/2026-11-15-actor-lin-polish-design.md)，'
        'API沿既有200张授权从38张起记；最终视觉待查看。')
    for name in ['agent.md','docs/界面层契约.md','动作或者图片描述/需求台账.md']:
        p=ROOT/name; old=p.read_bytes(); i=old.find(b'\n')+1
        text=paragraph if name=='agent.md' else paragraph.replace('(docs/plans/','(../docs/plans/')
        if name=='docs/界面层契约.md': text=text.replace('(../docs/plans/','(plans/')
        p.write_bytes(old[:i]+('\n'+text+'\n').encode('utf-8')+old[i:])
    p=ROOT/'实施计划与验收基线.md'; old=p.read_bytes()
    old=old.replace('版本：v1.84'.encode(), '版本：v1.85'.encode(), 1)
    section='''
### 0.20.26 2026-11-15 林序放大细节与画风精修

用户明确要求优化林的形象细节、与沈的风格保持，指出放大后难看。授权在§0.20.25正式四角色接入基础上，继续使用既有图像API（200张上限，累计38张起记）精修P01，保留黑发/眼镜、蓝绿色外套、浅衬衫、电脑与笔身份；已选V5整体比例、站姿与运动节奏作为基准。新母图/局部绘图另存version12，旧V5原字节保留；P02V8/P03V10/P04V11保持。

先存before.zip/hash与受保护输入，实际看P01/P03全身及放大裁图，限定G6参考/资源核查后进入G7生成、同源拆件注册和正式映射；对应G8须查看全身、放大脸/领口/手、出手/受击等实际Godot连续画面，以及正常选角/战斗/继续。机器尺寸/透明/hash与AI实际看图分别登记，不能用技术通过代替放大美术合格。保留API提示词、真实上传与输出、选用/返工及累计数。

只改变P01表现资源、角色版本映射及同源静态派生，必要验证工具另存。规则/数值、RNG、GameSession写口、存档schema、HUD/目标框、接触时点、基础×4/倍速/减少动态、终局和输入门控保持。验证只用隔离SaveStore；共享代码若变则完整规则/UI本轮重跑。证据根artifacts/verification/actor-lin-polish-20261115/，详细方案见[精修设计](docs/plans/2026-11-15-actor-lin-polish-design.md)。本条不扩大其他角色或整体UI改版，也不代替原整版G0/G6/G8或用户最终美术认可。

'''
    marker='\n## 1.'.encode(); idx=old.find(marker)
    if idx<0: raise ValueError('Plan next section not found')
    p.write_bytes(old[:idx]+section.encode()+old[idx:])
    print(json.dumps({'before_files':len(paths),'protected':len(protected)},ensure_ascii=False))

if __name__=='__main__': main()
