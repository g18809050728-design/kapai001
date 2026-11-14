"""Extract an original 4x3 material atlas and build offline alpha-fit evidence."""
from pathlib import Path
from datetime import datetime, timezone
import base64
import hashlib
import json
import math
import platform
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

BASE=Path(__file__).resolve().parent
ROOT=BASE.parents[3]
EVIDENCE=ROOT/'artifacts/verification/vfx-reference-20261114'
SPECS=[
 ('pen_trail','笔锋轨迹',['UIR-055']),('light_hit','轻命中',['UIR-016','UIR-055']),
 ('heavy_hit','重命中',['UIR-055','UIR-056']),('pressure_trail','压力轨迹',['UIR-016','UIR-055']),
 ('protection','防护',['UIR-041','UIR-055']),('block_contact','抵挡',['UIR-041','UIR-055']),
 ('guard_break','破防',['UIR-041','UIR-055']),('restore','恢复',['UIR-016','UIR-055']),
 ('focus_gain','专注变化',['UIR-016','UIR-055']),('partner_arrival','伙伴入场',['UIR-042','UIR-055']),
 ('status_attachment','状态附着',['UIR-042','UIR-055']),('phase_pulse','阶段冲击',['UIR-042','UIR-056'])]

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def dump(p,obj):p.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def font(size):return ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',size)

def flatten(im,bg):
    b=Image.new('RGBA',im.size,bg);b.alpha_composite(im);return b.convert('RGB')

def extract():
    path=BASE/'VFX-material-atlas-v1.png'
    source=Image.open(path).convert('RGB')
    if source.size!=(1536,1024):raise ValueError(f'Unexpected actual dimensions {source.size}')
    dest=BASE/'materials'
    if dest.exists():raise RuntimeError('Extraction exists: preserve it and use a new version for revisions.')
    dest.mkdir()
    rows=[]
    for i,(sid,label,req) in enumerate(SPECS):
        col,row=i%4,i//4
        region=[col*384,round(row*1024/3),(col+1)*384,round((row+1)*1024/3)]
        im=source.crop(region)
        rgb=np.array(im,dtype=np.float32)
        matte=np.array([255,0,255],dtype=np.float32)
        distance=np.max(np.abs(rgb-matte),axis=2)
        # Known flat-magenta matte. Fully blank below 18, fully opaque above 105.
        # Reconstruct RGB on fractional alpha; preserve the original atlas.
        a=np.clip((distance-18)/87,0,1)
        color=np.clip((rgb-(1-a[:,:,None])*matte)/np.maximum(a[:,:,None],1/255),0,255)
        rgba=np.concatenate([color,np.round(a[:,:,None]*255)],axis=2).astype(np.uint8)
        rgba[rgba[:,:,3]==0,:3]=0
        result=Image.fromarray(rgba)
        bbox=result.getbbox()
        if bbox is None:raise ValueError('Empty cell '+sid)
        # Preserve 8 pixels of transparent padding without stretching the material.
        result=result.crop(bbox)
        padded=Image.new('RGBA',(result.width+16,result.height+16))
        padded.alpha_composite(result,(8,8))
        file=dest/(sid+'.png');padded.save(file)
        alpha=np.array(padded)[:,:,3]
        strong=(alpha>100)
        # Matte spill indicator is reported, never treated as a visual approval.
        r,g,b=np.array(padded,dtype=np.int16)[:,:,:3].transpose(2,0,1)
        spill=(np.minimum(r,b)-g>90)&strong
        row_data=dict(id=sid,label=label,requirement_ids=req,file=file.relative_to(BASE).as_posix(),
            source_region_xyxy=region,original_cell_alpha_bbox=list(bbox),
            original_margin_px=[bbox[0],bbox[1],im.width-bbox[2],im.height-bbox[3]],
            touches_cell_boundary=bool(bbox[0]==0 or bbox[1]==0 or bbox[2]==im.width or bbox[3]==im.height),
            size=list(padded.size),sha256=sha(file),transparent_fraction=float((alpha==0).mean()),
            semitransparent_pixels=int(((alpha>0)&(alpha<255)).sum()),
            matte_spill_indicator_pixels=int(spill.sum()),
            candidate_status='extracted_pending_visual_review',selected=False)
        rows.append(row_data)
    for background in ('dark','light'):
        bg='#1a2327' if background=='dark' else '#e8e5db'
        fg='#ece7d9' if background=='dark' else '#202c34'
        sheet=Image.new('RGB',(4*360,3*330),bg)
        draw=ImageDraw.Draw(sheet)
        for i,m in enumerate(rows):
            with Image.open(BASE/m['file']) as im:
                im=im.copy();im.thumbnail((320,265),Image.Resampling.LANCZOS)
                x,y=i%4*360,i//4*330
                tile=Image.new('RGBA',(360,292),bg)
                tile.alpha_composite(im,((360-im.width)//2,(292-im.height)//2))
                sheet.paste(tile.convert('RGB'),(x,y+30))
                draw.text((x+12,y+6),f'{i+1:02d} {m["label"]}',font=font(19),fill=fg)
        sheet.save(BASE/f'materials-contact-{background}.jpg',quality=95)
    report=dict(created_at_utc=datetime.now(timezone.utc).isoformat(),command=sys.argv,platform=platform.platform(),
        source='VFX-material-atlas-v1.png',source_sha256=sha(path),actual_mode=source.mode,actual_size=list(source.size),
        script_sha256=sha(Path(__file__)),method='flat magenta distance key; thresholds 18/105; fractional-alpha matte reconstruction; tight crop with 8px transparent padding',
        native_transparency=False,static_materials_not_animation_frames=True,materials=rows,
        clipping_indicators=[m['id'] for m in rows if m['touches_cell_boundary']],
        visual_review='pending',runtime_integration='not_started',human_acceptance='pending',release_license='pending')
    dump(BASE/'extraction.json',report)
    return rows

def embed(path):return 'data:image/png;base64,'+base64.b64encode(path.read_bytes()).decode('ascii')

PAGE=r'''<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>特效材料检查 · G6</title>
<style>
:root{color-scheme:dark;font:15px/1.55 system-ui,"Microsoft YaHei",sans-serif;color:#eee9df;background:#111b22}*{box-sizing:border-box}body{margin:0}main{max-width:1280px;margin:auto;padding:24px}h1{font-size:25px;margin:6px 0}p{color:#afc1c8;margin:4px 0 18px}.badge{font-size:12px;color:#d4ede4;background:#29464a;border-radius:20px;padding:4px 10px}.layout{display:grid;grid-template-columns:minmax(280px,1fr) 330px;gap:20px}.stage{border:1px solid #40565f;border-radius:10px;overflow:hidden;background:#1a2327;display:flex;align-items:center;justify-content:center}canvas{width:100%;height:auto}.panel{padding:16px;background:#1a2b33;border:1px solid #40565f;border-radius:10px}.row{display:flex;flex-wrap:wrap;gap:10px;margin:10px 0}label{display:block}button,select{font:inherit;color:#eee9df;background:#27424b;border:1px solid #54717c;border-radius:5px;padding:7px;cursor:pointer}button:hover{background:#38606c}button:focus-visible,select:focus-visible,input:focus-visible{outline:3px solid #f4c46b;outline-offset:3px}input[type=range]{display:block;width:100%;accent-color:#94cdbb}output{font-variant-numeric:tabular-nums}.description{font-size:13px;min-height:62px;margin-top:14px;color:#bdd0d4}.small{font-size:12px;color:#9fb5bc}footer{margin-top:16px;color:#9fb5bc;font-size:12px}@media(max-width:800px){main{padding:14px}.layout{grid-template-columns:1fr}}
</style>
<main><span class="badge">G6 透明材料核对 · 未接入游戏</span><h1>特效的轮廓、边缘与叠放</h1>
<p>逐项检查轻重、方向和透明边缘。这里的静态叠放用于资源核查；角色仍是未选定的 P01 分层候选。</p>
<div class="layout"><div class="stage"><canvas id="stage" width="900" height="650" aria-label="特效透明材料检查画布"></canvas></div>
<aside class="panel"><label>材料 <select id="material" aria-label="材料"></select></label>
<div class="row"><label>背景 <select id="background"><option value="dark">深色</option><option value="light">浅色</option><option value="checker">透明棋盘</option></select></label><label>叠放 <select id="placement"><option value="isolated">孤立材料</option><option value="front">人物前方</option><option value="behind">人物后方</option></select></label></div>
<label for="scale">尺寸 <output id="scaleValue">100%</output></label><input type="range" id="scale" min="40" max="180" value="100" aria-label="材料尺寸">
<label for="rotation">角度 <output id="rotationValue">0°</output></label><input type="range" id="rotation" min="-90" max="90" value="0" aria-label="材料角度">
<label for="opacity">不透明度 <output id="opacityValue">100%</output></label><input type="range" id="opacity" min="0" max="100" value="100" aria-label="材料不透明度">
<div class="row"><label><input id="bounds" type="checkbox"> 显示材料范围</label><label><input id="context" type="checkbox"> 文字遮挡检查</label></div>
<div class="row"><button id="reset" type="button">还原检查</button><button id="cycle" type="button">旋转检查</button></div>
<div class="description" id="description"></div><div class="small">尺寸/角度/周期仅用于观察材料适配，不是正式动作参数。半透明由纯色底后处理取得，原始图集保留。</div>
</aside></div><footer>12 种静态材料候选；人工接受、许可、真实事件绑定及最终动作节奏仍待核对。可离线打开，本页没有网络或游戏状态读写。</footer></main>
<script type="application/json" id="data">__DATA__</script><script>
'use strict';const data=JSON.parse(document.getElementById('data').textContent),canvas=document.getElementById('stage'),ctx=canvas.getContext('2d');
const controls=Object.fromEntries(['material','background','placement','scale','rotation','opacity','bounds','context','cycle'].map(id=>[id,document.getElementById(id)])),images=new Map();let ready=false,rotating=false,last=null,rotationAngle=0;
for(const m of data.materials){const o=document.createElement('option');o.value=m.id;o.textContent=m.label;controls.material.append(o);}
const combinations=[{id:'combo_pen',label:'叠放：笔锋＋轻命中',ids:['pen_trail','light_hit']},{id:'combo_guard',label:'叠放：防护＋抵挡',ids:['protection','block_contact']},{id:'combo_phase',label:'叠放：阶段＋重命中',ids:['phase_pulse','heavy_hit']}];
for(const m of combinations){const o=document.createElement('option');o.value=m.id;o.textContent=m.label;controls.material.append(o);}
function selection(){const combo=combinations.find(c=>c.id===controls.material.value);return combo?combo.ids:[controls.material.value];}
function paintBg(){const light=controls.background.value==='light';ctx.fillStyle=light?'#e8e5db':'#1a2327';ctx.fillRect(0,0,900,650);if(controls.background.value==='checker'){for(let y=0;y<650;y+=25)for(let x=0;x<900;x+=25){ctx.fillStyle=((x/25+y/25)%2)?'#596269':'#3d474e';ctx.fillRect(x,y,25,25);}}return light;}
function actor(){ctx.save();const im=images.get('actor'),h=400,w=h*im.width/im.height;ctx.drawImage(im,450-w/2,520-h,w,h);ctx.restore();}
function drawMaterial(id,index,combined){const im=images.get(id),max=combined?290:360,fit=Math.min(max/im.width,max/im.height),s=Number(controls.scale.value)/100*fit;ctx.save();ctx.translate(combined&&index===0?360:450,combined&&index===0?310:320);ctx.rotate(Number(controls.rotation.value)*Math.PI/180);ctx.globalAlpha=Number(controls.opacity.value)/100;ctx.drawImage(im,-im.width*s/2,-im.height*s/2,im.width*s,im.height*s);if(controls.bounds.checked){ctx.globalAlpha=1;ctx.strokeStyle='#e5b65b';ctx.lineWidth=1;ctx.strokeRect(-im.width*s/2,-im.height*s/2,im.width*s,im.height*s);}ctx.restore();}
function render(){const light=paintBg();if(ready){if(controls.placement.value==='front')actor();const ids=selection();ids.forEach((id,i)=>drawMaterial(id,i,ids.length>1));if(controls.placement.value==='behind')actor();}if(controls.context.checked){ctx.save();ctx.fillStyle=light?'#25323b':'#e7e5da';ctx.font='22px system-ui';ctx.fillText('检查文字：意图与数值应可辨',300,100);ctx.strokeStyle=light?'#69868b':'#779398';ctx.strokeRect(310,550,280,14);ctx.restore();}document.getElementById('scaleValue').value=controls.scale.value+'%';document.getElementById('rotationValue').value=controls.rotation.value+'°';document.getElementById('opacityValue').value=controls.opacity.value+'%';const ids=selection();document.getElementById('description').textContent=ids.map(id=>{const m=data.materials.find(x=>x.id===id);return m.label+' · '+m.size.join(' × ')+' · '+m.status;}).join('；');}
function stop(){rotating=false;last=null;controls.cycle.textContent='旋转检查';controls.cycle.setAttribute('aria-pressed','false');}
for(const key of ['material','background','placement','scale','rotation','opacity','bounds','context'])controls[key].addEventListener(key==='scale'||key==='rotation'||key==='opacity'?'input':'change',()=>{stop();render();});
document.getElementById('reset').addEventListener('click',()=>{stop();controls.material.value='pen_trail';controls.background.value='dark';controls.placement.value='isolated';controls.scale.value='100';controls.rotation.value='0';controls.opacity.value='100';controls.bounds.checked=false;controls.context.checked=false;render();});
controls.cycle.addEventListener('click',()=>{rotating=!rotating;last=null;rotationAngle=Number(controls.rotation.value);controls.cycle.textContent=rotating?'暂停检查':'旋转检查';controls.cycle.setAttribute('aria-pressed',String(rotating));});
async function init(){await Promise.all([...data.materials.map(m=>({id:m.id,url:m.image_data})),{id:'actor',url:data.actor}].map(m=>new Promise((resolve,reject)=>{const im=new Image();im.onload=()=>{images.set(m.id,im);resolve();};im.onerror=()=>reject(new Error(m.id+' 载入失败'));im.src=m.url;})));ready=true;render();}
function tick(t){if(rotating){if(last!==null){rotationAngle+=(t-last)*.02;if(rotationAngle>90)rotationAngle=-90;controls.rotation.value=String(Math.round(rotationAngle));render();}last=t;}requestAnimationFrame(tick);}
init().catch(e=>{document.getElementById('description').textContent=e.message;});requestAnimationFrame(tick);window.materialInspection={data,selection,getState:()=>({ready,rotating,selected:controls.material.value,scale:Number(controls.scale.value),rotation:Number(controls.rotation.value),opacity:Number(controls.opacity.value),placement:controls.placement.value}),render};
</script></html>'''

def preview(rows):
    actor_path=ROOT/'output/imagegen/layered-v3/P01-parts-v1/assembled-body-only.png'
    with Image.open(actor_path) as im:
        tight=im.crop(im.getbbox());tight.save(BASE/'P01-body-inspection.png')
    data=dict(materials=[dict(id=m['id'],label=m['label'],size=m['size'],status='候选，待正式选定',image_data=embed(BASE/m['file'])) for m in rows],
              actor=embed(BASE/'P01-body-inspection.png'))
    (BASE/'preview.html').write_text(PAGE.replace('__DATA__',json.dumps(data,ensure_ascii=False,separators=(',',':')).replace('<','\\u003c')),encoding='utf-8')
    # Offline transform/alpha compatibility sequence, no gameplay timeline.
    frames=[]
    for m in rows:
        for angle in (-24,-12,0,12,24,0):
            im=Image.open(BASE/m['file']).convert('RGBA')
            im.thumbnail((320,270),Image.Resampling.LANCZOS)
            im=im.rotate(angle,resample=Image.Resampling.BICUBIC,expand=True)
            canvas=Image.new('RGBA',(560,420),'#1a2327')
            canvas.alpha_composite(im,((560-im.width)//2,(420-im.height)//2))
            ImageDraw.Draw(canvas).text((16,16),m['label']+' / G6 旋转检查',font=font(19),fill='#e8e5db')
            frames.append(canvas.convert('RGB'))
    frames[0].save(BASE/'material-transform-check.gif',save_all=True,append_images=frames[1:],duration=110,loop=0)

def main():
    rows=extract();preview(rows)
    print(json.dumps(dict(materials=len(rows),clipping_indicators=[m['id'] for m in rows if m['touches_cell_boundary']],matte_indicator_pixels=sum(m['matte_spill_indicator_pixels'] for m in rows),preview=str(BASE/'preview.html')),ensure_ascii=False))

if __name__=='__main__':main()
