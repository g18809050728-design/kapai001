"""Build the self-contained G6 asset inspection page from rig.json.

No server or Python package is required. Sprite scale is deliberately excluded
from child joint transforms so this matches the accompanying Pillow assembly.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import math
import struct
from pathlib import Path


HERE = Path(__file__).resolve().parent


def number(value, field):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"{field}: expected a finite number")
    return value


def pair(value, field):
    if not isinstance(value, list) or len(value) != 2:
        raise ValueError(f"{field}: expected two numbers")
    return [number(item, field) for item in value]


def prepare_rig(path):
    """Validate joints and embed each PNG without changing the source rig."""
    rig = json.loads(path.read_text(encoding="utf-8-sig"))
    canvas_size = pair(rig.get("canvas_size"), "canvas_size")
    if any(item <= 0 or int(item) != item for item in canvas_size):
        raise ValueError("canvas_size: expected positive integers")
    parts = rig.get("parts")
    if not isinstance(parts, list) or not parts:
        raise ValueError("parts: expected a nonempty list")
    ids = set()
    for part in parts:
        part_id = part.get("id")
        if not isinstance(part_id, str) or not part_id or part_id in ids:
            raise ValueError(f"invalid or repeated part id: {part_id!r}")
        ids.add(part_id)
        for name in ("pivot_px", "scale", "rest_offset"):
            pair(part.get(name), f"{part_id}.{name}")
        if any(value == 0 for value in part["scale"]):
            raise ValueError(f"{part_id}.scale cannot be zero")
        number(part.get("rest_angle_deg"), f"{part_id}.rest_angle_deg")
        number(part.get("z_index"), f"{part_id}.z_index")
        source = (path.parent / part["file"]).resolve()
        if not source.is_relative_to(path.parent.resolve()):
            raise ValueError(f"part file is outside rig folder: {part_id}")
        data = source.read_bytes()
        if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n":
            raise ValueError(f"expected a PNG: {source.name}")
        part["image_size"] = list(struct.unpack(">II", data[16:24]))
        part["image_sha256"] = hashlib.sha256(data).hexdigest()
        part["image_data"] = "data:image/png;base64," + base64.b64encode(data).decode("ascii")
    by_id = {part["id"]: part for part in parts}
    for part in parts:
        parent = part.get("parent")
        if parent is not None and parent not in ids:
            raise ValueError(f"unknown parent for {part['id']}: {parent}")
        visited = {part["id"]}
        while parent is not None:
            if parent in visited:
                raise ValueError(f"parent cycle at {part['id']}")
            visited.add(parent)
            parent = by_id[parent].get("parent")
    poses = rig.get("poses", {})
    if not isinstance(poses, dict):
        raise ValueError("poses: expected a dictionary")
    for pose_id, pose in poses.items():
        if not isinstance(pose, dict):
            raise ValueError(f"pose {pose_id}: expected part-angle dictionary")
        for part_id, delta in pose.items():
            if part_id not in ids:
                raise ValueError(f"pose {pose_id} references unknown part {part_id}")
            number(delta, f"poses.{pose_id}.{part_id}")
    rig["source_rig_sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    return rig


PAGE = r'''<!doctype html>
<html lang="zh-CN">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>P01 分层资源检查</title>
<style>
:root{color-scheme:dark;font:15px/1.55 system-ui,"Microsoft YaHei",sans-serif;color:#e8e4d9;background:#111a20}
*{box-sizing:border-box}body{margin:0}main{max-width:1280px;margin:auto;padding:24px}h1{font-size:25px;margin:0 0 5px}p{margin:0 0 16px;color:#b6c4ca}.badge{display:inline-block;background:#29474e;color:#d5efe9;font-size:12px;padding:3px 9px;border-radius:20px;margin-bottom:12px}.layout{display:grid;grid-template-columns:minmax(280px,1fr) 330px;gap:20px}.stage{min-height:440px;display:flex;align-items:center;justify-content:center;border:1px solid #3a5059;border-radius:12px;overflow:hidden;background:#1a2327}canvas{display:block;width:auto;max-width:100%;height:auto;max-height:76vh;aspect-ratio:640/720}.panel{background:#1a272e;border:1px solid #3a5059;border-radius:12px;padding:16px}.label{font-weight:600;margin:0 0 9px}.row{display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin-bottom:14px}button,select{font:inherit;color:#e8e4d9;background:#263c45;border:1px solid #54717c;border-radius:6px;padding:7px 11px;cursor:pointer}button:hover{background:#34545e}button[aria-pressed=true]{background:#91c9bd;color:#10272a;border-color:#bdede2}button:focus-visible,select:focus-visible,input:focus-visible{outline:3px solid #f5c86b;outline-offset:3px}input[type=range]{width:100%;accent-color:#91c9bd}input[type=checkbox]{accent-color:#91c9bd}label{cursor:pointer}.parts{max-height:285px;overflow:auto;display:grid;gap:5px;border-top:1px solid #3a5059;padding-top:10px}.parts label{display:flex;gap:7px;align-items:center;font-size:13px}.parts code{overflow-wrap:anywhere}small,.hint{font-size:12px;color:#a7bfc4}.hint{min-height:36px}output{font-variant-numeric:tabular-nums}footer{margin-top:16px;color:#9db2ba;font-size:12px}.meta{font-size:12px;color:#a7bfc4;margin-top:10px;overflow-wrap:anywhere}@media(max-width:800px){main{padding:14px}.layout{grid-template-columns:1fr}.stage{min-height:360px}canvas{max-height:65vh}.parts{max-height:220px}}
</style>
<main>
<span class="badge">G6 资产检查 · 未接入游戏</span>
<h1>P01 分层装配与动作可用性</h1>
<p>逐件观察身体、关节与遮挡。下列姿态用于检查贴图衔接；播放周期仅为离线检查参数。</p>
<div class="layout">
  <div class="stage"><canvas id="scene" aria-label="P01 分层人物装配预览"></canvas></div>
  <aside class="panel">
    <div class="label">检查姿态</div>
    <div class="row" id="poses"></div>
    <div class="row"><button id="play" type="button">播放</button><button id="reset" type="button">还原全部</button><label>周期 <select id="period"><option value="4">4 秒</option><option value="8">8 秒</option><option value="12">12 秒</option></select></label></div>
    <label for="progress">静止 → 目标姿态 → 静止 <output id="progressText">0%</output></label>
    <input id="progress" type="range" min="0" max="1000" value="0" aria-label="动作检查进度">
    <p class="hint" id="poseHint">静止装配，角度增量为零。</p>
    <div class="row"><label>底色 <select id="background"><option value="dark">深色</option><option value="light">浅色</option><option value="checker">透明棋盘</option></select></label><label><input id="joints" type="checkbox"> 显示骨点与连接</label></div>
    <div class="row"><button id="props" type="button" aria-pressed="false">隐藏道具</button><button id="showAll" type="button">显示全部部件</button></div>
    <div class="label">部件显隐 <small id="partCount"></small></div>
    <div id="parts" class="parts"></div>
    <div class="meta" id="assetInfo"></div>
  </aside>
</div>
<footer>这份页面检查独立贴图、关节关系与遮挡补全。人工接受、许可、正式动作和全量资源验收分别记录。</footer>
</main>
<script id="rig-data" type="application/json">__RIG_DATA__</script>
<script>
'use strict';
const rig=JSON.parse(document.getElementById('rig-data').textContent);
const canvas=document.getElementById('scene'),ctx=canvas.getContext('2d');
canvas.width=rig.canvas_size[0];canvas.height=rig.canvas_size[1];canvas.style.aspectRatio=`${canvas.width}/${canvas.height}`;
const byId=new Map(rig.parts.map(p=>[p.id,p]));
const ordered=rig.parts.map((p,i)=>({...p,sourceIndex:i})).sort((a,b)=>a.z_index-b.z_index||a.sourceIndex-b.sourceIndex);
const visible=new Map(rig.parts.map(p=>[p.id,true]));
const checkboxes=new Map(),images=new Map();
const controls={progress:document.getElementById('progress'),progressText:document.getElementById('progressText'),play:document.getElementById('play'),period:document.getElementById('period'),joints:document.getElementById('joints'),background:document.getElementById('background'),props:document.getElementById('props')};
let phase=0,playing=false,selected='rest',lastTimestamp=null,imagesReady=false,hideProps=false;
const propIds=new Set(rig.parts.filter(p=>p.role==='prop'||p.kind==='prop'||/(?:^|_)(laptop|pen|notebook|prop|computer)(?:_|$)/i.test(p.id)).map(p=>p.id));
for(const id of rig.prop_ids||[])if(byId.has(id))propIds.add(id);
const definitions=[{id:'rest',label:'静止',aliases:['rest','静止']},{id:'breath',label:'呼吸',aliases:['breath','breathing','idle','呼吸']},{id:'reach',label:'伸臂',aliases:['reach','action','伸臂']},{id:'lean',label:'后仰',aliases:['lean','recoil','hit','后仰']},{id:'fold',label:'收拢',aliases:['fold','depart','exit','收拢']}];
const poseButtons=new Map();
function fallbackBreath(){const result={};for(const p of rig.parts){if(p.id==='torso')result[p.id]=0.8;if(p.id==='head')result[p.id]=-0.6;if(['arm_near_upper','near_upper_arm','upper_arm_near'].includes(p.id))result[p.id]=-1.1;}return result;}
function selectedPose(){if(selected==='rest')return {};const def=definitions.find(d=>d.id===selected);for(const key of def.aliases)if(rig.poses&&Object.hasOwn(rig.poses,key))return rig.poses[key];return selected==='breath'?fallbackBreath():{};}
function setPlaying(value){playing=value;lastTimestamp=null;controls.play.textContent=value?'暂停':'播放';controls.play.setAttribute('aria-pressed',String(value));}
function selectPose(id){selected=id;phase=0;setPlaying(false);for(const [key,button]of poseButtons)button.setAttribute('aria-pressed',String(key===id));render();}
for(const def of definitions){const button=document.createElement('button');button.type='button';button.textContent=def.label;button.setAttribute('aria-pressed',String(def.id==='rest'));button.addEventListener('click',()=>selectPose(def.id));document.getElementById('poses').append(button);poseButtons.set(def.id,button);}
for(const p of ordered){const label=document.createElement('label'),checkbox=document.createElement('input'),code=document.createElement('code');checkbox.type='checkbox';checkbox.checked=true;code.textContent=p.id+(propIds.has(p.id)?' · 道具':'');label.append(checkbox,code);document.getElementById('parts').append(label);checkbox.addEventListener('change',()=>{visible.set(p.id,checkbox.checked);if(propIds.has(p.id)){hideProps=[...propIds].every(id=>!visible.get(id));updatePropButton();}render();});checkboxes.set(p.id,checkbox);}
function updatePropButton(){controls.props.textContent=hideProps?'显示道具':'隐藏道具';controls.props.setAttribute('aria-pressed',String(hideProps));controls.props.disabled=propIds.size===0;}
function setVisibility(id,value){visible.set(id,value);checkboxes.get(id).checked=value;}
function jointsForPose(pose,weight){const computed=new Map();function joint(id){if(computed.has(id))return computed.get(id);const p=byId.get(id),parent=p.parent===null||p.parent===undefined?null:joint(p.parent),base=parent?parent.angle:0,c=Math.cos(base),s=Math.sin(base),offset=p.rest_offset;const result={x:(parent?parent.x:0)+c*offset[0]-s*offset[1],y:(parent?parent.y:0)+s*offset[0]+c*offset[1],angle:base+(p.rest_angle_deg+(pose[id]||0)*weight)*Math.PI/180};computed.set(id,result);return result;}for(const p of rig.parts)joint(p.id);return computed;}
function paintBackground(){const mode=controls.background.value;ctx.fillStyle=mode==='light'?'#e8e5db':'#1a2327';ctx.fillRect(0,0,canvas.width,canvas.height);if(mode==='checker'){const cell=20;for(let y=0;y<canvas.height;y+=cell)for(let x=0;x<canvas.width;x+=cell){ctx.fillStyle=((x/cell+y/cell)%2)?'#596269':'#3d474e';ctx.fillRect(x,y,cell,cell);}}}
function render(){paintBackground();const pose=selectedPose(),weight=selected==='rest'?0:Math.sin(Math.PI*phase)**2,joints=jointsForPose(pose,weight);if(imagesReady){for(const p of ordered){if(!visible.get(p.id))continue;const joint=joints.get(p.id);ctx.save();ctx.translate(joint.x,joint.y);ctx.rotate(joint.angle);ctx.scale(p.scale[0],p.scale[1]);ctx.drawImage(images.get(p.id),-p.pivot_px[0],-p.pivot_px[1]);ctx.restore();}}if(controls.joints.checked){ctx.save();ctx.lineWidth=1.8;ctx.strokeStyle='#ffcc69';ctx.fillStyle='#ffe6a6';ctx.font='11px system-ui';for(const p of ordered){if(!visible.get(p.id))continue;const j=joints.get(p.id);if(p.parent){const parent=joints.get(p.parent);ctx.beginPath();ctx.moveTo(parent.x,parent.y);ctx.lineTo(j.x,j.y);ctx.stroke();}ctx.beginPath();ctx.arc(j.x,j.y,4,0,Math.PI*2);ctx.fill();ctx.strokeStyle='#142a32';ctx.lineWidth=3;ctx.strokeText(p.id,j.x+7,j.y-7);ctx.fillText(p.id,j.x+7,j.y-7);ctx.strokeStyle='#ffcc69';ctx.lineWidth=1.8;}ctx.restore();}controls.progress.value=String(Math.round(phase*1000));controls.progressText.value=`${Math.round(phase*100)}%`;const title=definitions.find(d=>d.id===selected).label;document.getElementById('poseHint').textContent=selected==='rest'?'静止装配，角度增量为零。':Object.keys(pose).length?`${title}：当前角度增量 ${Math.round(weight*100)}%。50% 进度为目标姿态。`:`${title}尚未配置角度，当前保持静止。`;document.getElementById('partCount').textContent=`${[...visible.values()].filter(Boolean).length} / ${rig.parts.length}`;}
controls.progress.addEventListener('input',()=>{setPlaying(false);phase=Number(controls.progress.value)/1000;render();});
controls.play.addEventListener('click',()=>{if(selected==='rest')selectPose('breath');setPlaying(!playing);});
controls.background.addEventListener('change',render);controls.joints.addEventListener('change',render);controls.period.addEventListener('change',()=>{lastTimestamp=null;});
controls.props.addEventListener('click',()=>{hideProps=!hideProps;for(const id of propIds)setVisibility(id,!hideProps);updatePropButton();render();});
document.getElementById('showAll').addEventListener('click',()=>{for(const p of rig.parts)setVisibility(p.id,true);hideProps=false;updatePropButton();render();});
document.getElementById('reset').addEventListener('click',()=>{for(const p of rig.parts)setVisibility(p.id,true);hideProps=false;controls.joints.checked=false;controls.background.value='dark';controls.period.value='4';updatePropButton();selectPose('rest');});
document.getElementById('assetInfo').textContent=`画布 ${canvas.width} × ${canvas.height} · ${rig.parts.length} 个独立部件 · 内嵌贴图，可离线打开`;
async function init(){await Promise.all(rig.parts.map(p=>new Promise((resolve,reject)=>{const img=new Image();img.onload=()=>{images.set(p.id,img);resolve();};img.onerror=()=>reject(new Error(p.id+' 图片加载失败'));img.src=p.image_data;})));imagesReady=true;updatePropButton();render();}
function tick(timestamp){if(playing){if(lastTimestamp!==null){phase=(phase+(timestamp-lastTimestamp)/(Number(controls.period.value)*1000))%1;render();}lastTimestamp=timestamp;}else lastTimestamp=null;requestAnimationFrame(tick);}
document.addEventListener('visibilitychange',()=>{lastTimestamp=null;});
init().catch(error=>{document.getElementById('poseHint').textContent=error.message;controls.play.disabled=true;});requestAnimationFrame(tick);
// Exposes inspectable matrices for the independent offline asset audit.
window.assetInspection={rig,jointsForPose,getState:()=>({selected,phase,playing,visible:Object.fromEntries(visible)}),render,selectPose};
</script>
</html>
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rig", type=Path, default=HERE / "rig.json")
    parser.add_argument("--output", type=Path, default=HERE / "preview.html")
    args = parser.parse_args()
    rig = prepare_rig(args.rig.resolve())
    # Escaping '<' keeps any text in the rig from closing the JSON script tag.
    data = json.dumps(rig, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")
    args.output.write_text(PAGE.replace("__RIG_DATA__", data), encoding="utf-8")
    print(json.dumps({"output": str(args.output.resolve()), "parts": len(rig["parts"]),
                      "rig_sha256": rig["source_rig_sha256"],
                      "bytes": args.output.stat().st_size}, ensure_ascii=False))


if __name__ == "__main__":
    main()
