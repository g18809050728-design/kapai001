"""Non-destructive second alpha extraction after inspecting magenta spill."""
from pathlib import Path
from datetime import datetime, timezone
import importlib.util
import json
import shutil
import numpy as np
from PIL import Image, ImageDraw

BASE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('material_builder',BASE/'build_materials.py')
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)

def main():
    target=BASE/'materials-v2'
    if target.exists():raise RuntimeError('v2 exists; inspect rather than overwrite.')
    target.mkdir()
    old=json.loads((BASE/'extraction.json').read_text(encoding='utf-8'))
    atlas=Image.open(BASE/'VFX-material-atlas-v1.png').convert('RGB')
    rows=[]
    for m in old['materials']:
        rgb=np.array(atlas.crop(m['source_region_xyxy']),dtype=np.float32)
        r,g,b=rgb.transpose(2,0,1)
        chroma=np.minimum(r,b)-g
        # The actual magenta background is noisy, not exactly RGB(255,0,255).
        # Key by magenta dominance instead of absolute distance to one RGB value.
        alpha=np.clip((175-chroma)/90,0,1)
        alpha[alpha<.06]=0
        corrected=np.clip((rgb-(1-alpha[:,:,None])*np.array([255,0,255]))/np.maximum(alpha[:,:,None],1/255),0,255)
        # Remove excess magenta from the weaker R/B channel; retain warm/cool hue.
        cr,cg,cb=corrected.transpose(2,0,1)
        excess=np.maximum(0,np.minimum(cr,cb)-cg-28)
        warm=cr>=cb
        cb[warm]-=excess[warm];cr[~warm]-=excess[~warm]
        corrected=np.stack((cr,cg,cb),axis=2)
        rgba=np.concatenate((np.clip(corrected,0,255),np.round(alpha[:,:,None]*255)),axis=2).astype(np.uint8)
        rgba[rgba[:,:,3]==0,:3]=0
        im=Image.fromarray(rgba)
        box=im.getbbox()
        im=im.crop(box)
        out=Image.new('RGBA',(im.width+16,im.height+16));out.alpha_composite(im,(8,8))
        path=target/(m['id']+'.png');out.save(path)
        data=np.array(out,dtype=np.int16);a=data[:,:,3]
        spill=((np.minimum(data[:,:,0],data[:,:,2])-data[:,:,1])>90)&(a>100)
        cell=atlas.crop(m['source_region_xyxy'])
        rows.append(dict(m,file=path.relative_to(BASE).as_posix(),size=list(out.size),sha256=builder.sha(path),
            original_cell_alpha_bbox=list(box),original_margin_px=[box[0],box[1],cell.width-box[2],cell.height-box[3]],
            touches_cell_boundary=bool(box[0]==0 or box[1]==0 or box[2]==cell.width or box[3]==cell.height),
            transparent_fraction=float((a==0).mean()),semitransparent_pixels=int(((a>0)&(a<255)).sum()),
            matte_spill_indicator_pixels=int(spill.sum()),despill_changed_pixels=int(((excess>0)&(alpha>0)).sum()),
            candidate_status='alpha_v2_pending_visual_review'))
    for background in ('dark','light'):
        bg='#1a2327' if background=='dark' else '#e8e5db'
        fg='#ece7d9' if background=='dark' else '#202c34'
        sheet=Image.new('RGB',(1440,990),bg);d=ImageDraw.Draw(sheet)
        for i,m in enumerate(rows):
            im=Image.open(BASE/m['file']).convert('RGBA');im.thumbnail((320,265),Image.Resampling.LANCZOS)
            tile=Image.new('RGBA',(360,292),bg);tile.alpha_composite(im,((360-im.width)//2,(292-im.height)//2))
            x,y=i%4*360,i//4*330;sheet.paste(tile.convert('RGB'),(x,y+30))
            d.text((x+12,y+6),f'{i+1:02d} {m["label"]}',font=builder.font(19),fill=fg)
        sheet.save(BASE/f'materials-v2-contact-{background}.jpg',quality=95)
    record=dict(old,created_at_utc=datetime.now(timezone.utc).isoformat(),
        script_sha256=builder.sha(Path(__file__)),previous_extraction='extraction.json',
        method='magenta dominance key: alpha=clamp((175-(min(R,B)-G))/90); <.06 cleared; reconstruct known matte; despill weaker R/B channel to G+28; 8px transparent padding',
        color_adjustment='despill changes edge RGB only; no newly painted shapes',materials=rows,
        clipping_indicators=[r['id'] for r in rows if r['touches_cell_boundary']],
        visual_review='pending; chroma metrics do not prove clean edges')
    builder.dump(BASE/'extraction-v2.json',record)
    # Retain the entire first assembly before publishing a corrected local preview.
    for name in ('preview.html','material-transform-check.gif'):
        shutil.copy2(BASE/name,BASE/(Path(name).stem+'-alpha-v1'+Path(name).suffix))
    builder.preview(rows)
    print(json.dumps(dict(materials=len(rows),matte_indicator_pixels=sum(m['matte_spill_indicator_pixels'] for m in rows),clipping_indicators=record['clipping_indicators']),ensure_ascii=False))

if __name__=='__main__':main()
