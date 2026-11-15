"""P01 V12: coherent repaint, high-resolution details, accepted V5 motion family."""
from copy import deepcopy
import json
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageFilter
from scipy.ndimage import distance_transform_edt
import build_actor_party as b

ROOT=Path(__file__).resolve().parents[1]
RAW=ROOT/'output/imagegen/actor-lin-polish-20261115'
ART=ROOT/'assets/art/actor-lin-polish'
EV=ROOT/'artifacts/verification/actor-lin-polish-20261115'
MASTER=RAW/'p01-master-v1.png'
SCALE=.85
ORIGIN=np.array([512.,1454.])
HEAD_POLY=[[410,45],[650,45],[650,240],[600,260],[569,269],[556,282],
           [550,305],[561,322],[564,335],[548,330],[529,310],[513,302],
           [494,291],[470,276],[473,251],[479,237],[461,229],[441,212],[423,186]]
ARM_POLY=[[328,530],[381,528],[431,514],[450,488],[467,466],[486,464],
          [521,480],[544,500],[547,517],[537,529],[524,524],[518,539],
          [503,544],[490,539],[470,554],[440,567],[399,581],[346,594],[331,592]]
PEN_POLY=[[441,416],[455,418],[571,535],[568,548],[556,542],[441,431]]
LANDMARKS={
 'pelvis':[512,760],'chest':[518,459],'neck':[521,302],'cloth':[515,660],
 'near_shoulder':[365,375],'near_elbow':[328,561],'tip':[563,540],
 'far_shoulder':[648,376],'far_elbow':[690,570],'wrist':[822,567],
 'prop':[821,555],
 'legs':[{'name':'rear','hip':[443,760],'knee':[409,1050],'ankle':[398,1376],'cuff':1361},
         {'name':'front','hip':[586,760],'knee':[591,1051],'ankle':[599,1380],'cuff':1370}]
}

def keyed(path):
    """Unmatte the flat magenta, retaining fine hair/eyeglass antialiasing."""
    pixels=np.asarray(Image.open(path).convert('RGBA')).astype(float)
    rgb=pixels[:,:,:3]
    dominance=np.minimum(rgb[:,:,0],rgb[:,:,2])-rgb[:,:,1]
    alpha=np.clip((250-dominance)/230,0,1)
    # The service's nominal flat key contains low-amplitude noise. Such pixels
    # are transparent except immediately next to actual figure contours.
    support=cv2.dilate((dominance<60).astype(np.uint8),np.ones((5,5),np.uint8))>0
    alpha[~support]=0
    rgb=np.clip((rgb-(1-alpha[:,:,None])*np.array([255,0,255]))/np.maximum(alpha[:,:,None],.001),0,255)
    pixels[:,:,:3]=rgb
    pixels[:,:,3]=np.round(alpha*255)
    pixels[alpha==0]=0
    return Image.fromarray(np.round(pixels).astype(np.uint8))

def save(path,data): b.save(path,data)

def arm_mask(size):
    return np.maximum(b.polygon(size,ARM_POLY),b.polygon(size,PEN_POLY))

def source_canvas(name,key):
    reg=b.read(RAW/'edit-registration.json')[key]
    box=reg['source_crop']; x,y=reg['offset']; s=reg['scale']
    im=b.keyed(RAW/name)
    crop=im.crop((x,y,x+(box[2]-box[0])*s,y+(box[3]-box[1])*s))
    result=Image.new('RGBA',(1024,1536))
    result.alpha_composite(crop.resize((box[2]-box[0],box[3]-box[1]),Image.Resampling.LANCZOS),box[:2])
    return result

def detail_sprites(spec,positions,key,names,part,bone,z,mask=None,split=None):
    """Retain original large API pixels; logical size alone registers them."""
    reg=b.read(RAW/'edit-registration.json')[key]
    box=reg['source_crop']; factor=reg['scale']; x,y=reg['offset']
    w,h=(box[2]-box[0])*factor,(box[3]-box[1])*factor
    neutral=b.keyed(RAW/names['neutral']).crop((x,y,x+w,y+h))
    canvases={'neutral':neutral}
    for name,filename in names.items():
        if name=='neutral':continue
        candidate=b.keyed(RAW/filename).crop((x,y,x+w,y+h))
        if key=='forearm' and name=='strike':
            aligned=Image.new('RGBA',candidate.size)
            aligned.alpha_composite(candidate,(0,50))
            candidate=aligned
        if key=='face':
            editable=Image.eval(Image.open(RAW/'p01-face-feature-mask.png').getchannel('A'),lambda p:255-p)
            editable=editable.crop((x,y,x+w,y+h)).filter(ImageFilter.GaussianBlur(2))
            pixels=np.asarray(editable).copy()
            pixels[(np.asarray(neutral.getchannel('A'))<230)|(np.asarray(candidate.getchannel('A'))<230)]=0
            candidate=Image.composite(candidate,neutral,Image.fromarray(pixels))
            candidate.putalpha(neutral.getchannel('A'))
        canvases[name]=candidate
    if key=='forearm':
        # Continue a small hidden elbow underlap into the rolled cuff instead
        # of exposing the source crop's straight vertical edge.
        for name,canvas in canvases.items():
            pixels=np.asarray(canvas).copy()
            for row in range(pixels.shape[0]):
                indices=np.flatnonzero(pixels[row,:,3]>230)
                if len(indices) and indices[0]<110 and row>350:
                    edge=int(indices[0]); left=max(0,edge-70)
                    pixels[row,left:edge]=pixels[row,min(edge+8,pixels.shape[1]-1)]
            rows,cols=np.mgrid[:pixels.shape[0],:pixels.shape[1]]
            center_y=455
            # Rounded joint sits within the cuff, avoiding a vertical crop
            # edge as the forearm rotates independently of its upper sleeve.
            boundary=np.minimum(110,35 + .0035*(rows-center_y)**2)
            blend=np.clip((cols-boundary+3)/6,0,1)
            pixels[:,:,3]=np.minimum(pixels[:,:,3],np.round(blend*255)).astype(np.uint8)
            canvases[name]=Image.fromarray(pixels)
    if mask is not None:
        cropped=Image.fromarray(mask).crop(box).resize((w,h),Image.Resampling.NEAREST)
        canvases={k:b.masked(v,np.asarray(cropped)) for k,v in canvases.items()}
    if split:
        yy=np.arange(h)[:,None]/factor+box[1]
        keep=(yy<=split[1]+4) if split[0]=='head' else (yy>=split[1]-4)
        canvases={k:b.masked(v,np.broadcast_to(keep*255,(h,w))) for k,v in canvases.items()}
    boxes=[im.getbbox() for im in canvases.values()]
    crop_box=(min(p[0] for p in boxes),min(p[1] for p in boxes),max(p[2] for p in boxes),max(p[3] for p in boxes))
    source_top=[box[0]+crop_box[0]/factor,box[1]+crop_box[1]/factor]
    position=b.point(source_top)
    display=[(crop_box[2]-crop_box[0])/factor*SCALE,(crop_box[3]-crop_box[1])/factor*SCALE]
    files={}
    for name,im in canvases.items():
        files[name]=b.emit('P01',part+'_'+name,im.crop(crop_box),RAW/names[name],
            'same-master uniformly enlarged detail; original API pixels retained; display_size registers physical size',
            {'detail_scale':factor,'source_crop':box,'detail_crop':crop_box,'display_size':display})
    spec['parts'].append({'id':part,'file':files['neutral'],'bone':bone,
        'offset':[position[i]-positions[bone][i] for i in range(2)],'display_size':display,'z':z})
    return files

def main():
    b.ART,b.RAW,b.EV,b.SCALE,b.ORIGIN=ART,RAW,EV,SCALE,ORIGIN
    b.keyed=keyed
    b.RECORDS.clear(); EV.mkdir(parents=True,exist_ok=True)
    base=b.read(ROOT/'assets/art/actor-anatomy/P01/rig.json')
    spec=deepcopy(base); cfg=LANDMARKS
    points={'root':ORIGIN,'loop_hips':ORIGIN,'torso':cfg['pelvis'],'pelvis':cfg['pelvis'],
       'loop_chest':cfg['chest'],'head':cfg['neck'],'loop_head':cfg['neck'],
       'loop_near':cfg['near_shoulder'],'near_upper':cfg['near_shoulder'],
       'near_forearm':cfg['near_elbow'],'near_elbow':cfg['near_elbow'],'action_tip':cfg['tip'],
       'loop_far':cfg['far_shoulder'],'far_upper':cfg['far_shoulder'],
       'far_forearm':cfg['far_elbow'],'far_elbow':cfg['far_elbow'],
       'loop_cloth':cfg['cloth'],'held_wrist':cfg['wrist'],'loop_wrist':cfg['wrist'],
       'held_laptop':cfg['prop'],'loop_laptop':cfg['prop']}
    positions={k:b.point(v) for k,v in points.items()}
    spec.update(version=12,definition_id='P01',anatomy={'base_version':5,'source_scale':SCALE,
        'origin':ORIGIN.tolist(),'landmarks':cfg,'status':'pending_actual_render_review'})
    spec['bones']=[p for p in spec['bones'] if not p['id'].startswith(('rear_','front_'))]
    for bone in spec['bones']:
        parent=positions.get(bone['parent'],[0,0])
        bone['position']=[round(positions[bone['id']][i]-parent[i],6) for i in range(2)]
    spec['parts'],spec['drawings']=[],[]
    master=b.keyed(MASTER); yy,xx=np.mgrid[:1536,:1024]
    head_mask=b.polygon(master.size,HEAD_POLY).copy()
    face_pixels=np.asarray(source_canvas('p01-face-neutral-v1.png','face')).astype(int)
    skin=(face_pixels[:,:,0]>face_pixels[:,:,1]+10)&(face_pixels[:,:,0]>face_pixels[:,:,2]+30)
    head_mask[(yy>=260)&~skin]=0
    garment=b.keyed(RAW/'p01-trunk-v2.png').crop((0,0,1024,1536))
    # Both source edits retained a thin pen on the hidden jacket. Remove that
    # documented artifact only, using nearby cloth; no skin/face is inpainted.
    garment_pixels=np.asarray(garment).copy()
    pen_repair=b.polygon(master.size,[[440,410],[456,409],[542,476],[536,486],[442,432]])
    garment_pixels[:,:,:3]=cv2.inpaint(garment_pixels[:,:,:3],pen_repair,6,cv2.INPAINT_TELEA)
    garment=Image.fromarray(garment_pixels)
    body_poly=[[442,262],[480,272],[515,296],[548,303],[567,280],[647,322],[688,362],
       [691,489],[673,590],[706,706],[677,741],[650,711],[647,704],[601,704],
       [573,745],[499,714],[451,741],[352,707],[382,593],[375,508],[347,482],
       [327,367],[351,336],[417,307],[441,284]]
    body_mask=b.polygon(master.size,body_poly).copy()
    body_mask[head_mask>0]=0
    # Keep the enlarged garment's actual pixels in the mesh UVs.
    garment_reg=b.read(RAW/'edit-registration.json')['garment']
    box=garment_reg['source_crop']; gx,gy=garment_reg['offset']; factor=garment_reg['scale']
    detail=b.keyed(RAW/'p01-garment-v1.png').crop((gx,gy,gx+1000,gy+1275))
    high_mask=Image.fromarray(body_mask).crop(box).resize(detail.size,Image.Resampling.LANCZOS)
    detail=b.masked(detail,np.asarray(high_mask))
    bounds=detail.getbbox(); bitmap=detail.crop(bounds)
    file=b.emit('P01','trunk',bitmap,RAW/'p01-garment-v1.png','high resolution same-master garment; 2.5x detail source retained in mesh UVs',{'source_registration':garment_reg})
    torso={'position':b.point([box[0]+bounds[0]/factor,box[1]+bounds[1]/factor]),
        'size':[(bounds[2]-bounds[0])/factor*SCALE,(bounds[3]-bounds[1])/factor*SCALE],'file':file}
    spec['parts'].append({'id':'torso','mesh':True,'bone':'loop_chest','base_bone':'loop_cloth',
       'position':torso['position'],'size':torso['size'],'z':0,'cells':12,'file':torso['file']})
    sleeve=source_canvas('p01-sleeve-v1.png','sleeve')
    # Preserve the master's actual rolled-cuff aperture. The isolated edit
    # repainted an empty opening with a different ellipse; that would occlude
    # the anatomical elbow instead of covering just its attachment boundary.
    sleeve.paste(master.crop((250,510,432,625)),(250,510))
    sleeve_mask=b.polygon(master.size,[[342,334],[373,331],[399,349],[406,402],[400,456],
       [388,493],[383,519],[363,521],[353,525],[343,532],[335,542],[329,552],
       [327,565],[330,582],[334,590],[350,598],[366,600],[342,611],[318,613],[281,592],[261,574],
       [263,530],[278,500],[283,464],[302,418],[324,359]])
    far_mask=b.polygon(master.size,[[635,348],[667,366],[686,398],[697,457],[711,503],
       [720,553],[715,581],[690,608],[660,606],[651,577],[653,530],[647,469]])
    for name,im,source,mask,z in [('near_upper',sleeve,RAW/'p01-sleeve-v1.png',sleeve_mask,3),
                                 ('far_upper',master,MASTER,far_mask,-1)]:
        p=b.main_piece('P01',name,im,source,mask)
        spec['parts'].append({'id':name,'mesh':True,'bone':name,'base_bone':name.replace('upper','elbow'),
          'position':p['position'],'size':p['size'],'z':z,'cells':10,'file':p['file'],
          'weight_axis':[positions[name],positions[name.replace('upper','elbow')]],'weight_range':[.04,.96]})
    arms=detail_sprites(spec,positions,'forearm',{'neutral':'p01-forearm-neutral-v1.png',
        'strike':'p01-forearm-strike-v2.png'},'near_forearm','near_forearm',8)
    old_arm=next(p for p in base['drawings'] if p['part']=='near_forearm')
    old_arm=deepcopy(old_arm)
    old_arm['variants']=[{'id':'arm_strike','file':arms['strike']},{'id':'arm_follow','file':arms['strike']}]
    spec['drawings'].append(old_arm)
    # The held wrist and laptop remain separate rigid parts with their real attachment delta.
    fore_mask=b.polygon(master.size,[[675,558],[694,545],[735,551],[782,554],[806,566],
        [812,589],[793,599],[747,600],[709,592],[680,586]])
    hand_poly=[[786,558],[805,550],[815,532],[826,522],[836,522],[839,544],
       [846,529],[850,518],[858,518],[866,535],[870,524],[880,527],[886,546],
       [887,564],[881,574],[864,586],[842,593],[814,598],[792,589]]
    hand_mask=b.polygon(master.size,hand_poly)
    laptop_poly=[[658,531],[776,537],[828,371],[839,367],[978,385],[891,558],
        [809,558],[661,543]]
    laptop_mask=b.polygon(master.size,laptop_poly)
    laptop=np.asarray(b.masked(master,laptop_mask)).copy()
    repair=cv2.dilate((hand_mask>0).astype(np.uint8)*255,np.ones((7,7),np.uint8))
    trusted=(laptop[:,:,3]>0)&(repair==0)
    nearest=distance_transform_edt(~trusted,return_distances=False,return_indices=True)
    rgb=laptop[:,:,:3].copy(); rgb[~trusted]=rgb[nearest[0][~trusted],nearest[1][~trusted]]
    laptop[:,:,:3]=cv2.inpaint(rgb,repair,4,cv2.INPAINT_TELEA)
    for name,im,mask,bone,z in [('held_forearm',master,fore_mask,'far_forearm',5),
       ('held_laptop',Image.fromarray(laptop),None,'loop_laptop',6),('held_hand',master,hand_mask,'loop_wrist',7)]:
        p=b.main_piece('P01',name,im,MASTER,mask)
        # Keep source pixels instead of pre-downsampling all rigid details.
        spec['parts'].append({'id':name,'file':p['file'],'bone':bone,
            'offset':[p['position'][i]-positions[bone][i] for i in range(2)],'display_size':p['size'],'z':z})
    headnames={'neutral':'p01-face-neutral-v1.png','focus':'p01-face-focus-v1.png',
        'hit':'p01-face-hit-v1.png','blink':'p01-face-blink-v1.png'}
    faces=detail_sprites(spec,positions,'face',headnames,'head','loop_head',2,head_mask,('head',300))
    detail_sprites(spec,positions,'face',{'neutral':headnames['neutral']},'neck_overlap','loop_chest',-1,head_mask,('neck',300))
    old_head=deepcopy(next(p for p in base['drawings'] if p['part']=='head'))
    old_head['variants']=[{'id':'head_turn','file':faces['focus']},
       {'id':'head_strike','file':faces['focus']},{'id':'head_hit','file':faces['hit']}]
    spec['drawings'].append(old_head)
    spec['expression']['blink']=faces['blink']
    pants=b.keyed(RAW/'p01-pants-v1.png').crop((0,0,1024,1536))
    pelvis=b.main_piece('P01','pelvis',pants,RAW/'p01-pants-v1.png',
       np.where(yy>=665,np.clip((872-yy)/85,0,1)*255,0).astype(np.uint8))
    spec['parts'].append({'id':'pelvis','mesh':True,'bone':'pelvis','base_bone':'rear_thigh',
       'split_bone':'front_thigh','position':pelvis['position'],'size':pelvis['size'],'z':-1,
       'cells':16,'weight_range':[.24,.82],'split_range':[.4,.62],'file':pelvis['file']})
    split=np.interp(yy,[740,830,1070,1455],[530,521,501,490])
    spec['feet']=[]; calibration=[]
    for leg in cfg['legs']:
        name=leg['name']; region=(xx<split if name=='rear' else xx>=split)&(yy>=795)
        bottom=int(np.where((np.asarray(master.getchannel('A'))>0)&region)[0].max())+1
        shift=1454-bottom
        limb=b.main_piece('P01',name+'_leg',master,MASTER,np.where(region&(yy<leg['cuff']+10),255,0),shift=shift)
        shoe=b.main_piece('P01',name+'_shoe',master,MASTER,np.where(region&(yy>=leg['cuff']-13),255,0),shift=shift)
        hip,knee,ankle=b.point(leg['hip']),b.point(leg['knee'],shift),b.point(leg['ankle'],shift)
        lengths=[math.dist(hip,knee),math.dist(knee,ankle)]
        cross=(knee[0]-hip[0])*(ankle[1]-knee[1])-(knee[1]-hip[1])*(ankle[0]-knee[0])
        for id_,parent,p,pp,length in [(name+'_thigh','pelvis',hip,positions['pelvis'],lengths[0]),
           (name+'_shin',name+'_thigh',knee,hip,lengths[1]),(name+'_ankle',name+'_shin',ankle,knee,65)]:
            spec['bones'].append({'id':id_,'parent':parent,'position':[round(p[i]-pp[i],6) for i in range(2)],'length':length})
            positions[id_]=p
        frac=(knee[1]-limb['position'][1])/limb['size'][1]
        spec['parts'].append({'id':name+'_leg','mesh':True,'bone':name+'_thigh','base_bone':name+'_shin',
           'position':limb['position'],'size':limb['size'],'z':-3 if name=='rear' else -2,'cells':16,
           'weight_range':[frac-.075,frac+.075],'file':limb['file']})
        spec['parts'].append({'id':name+'_shoe','bone':name+'_ankle','file':shoe['file'],
           'offset':[shoe['position'][i]-ankle[i] for i in range(2)],'display_size':shoe['size'],'z':-4})
        spec['feet'].append({'upper':name+'_thigh','lower':name+'_shin','ankle':name+'_ankle',
            'target':ankle,'lengths':lengths,'bend':-1 if cross>0 else 1,'bind_axes':True})
        calibration.append({'name':name,'hip':hip,'knee':knee,'ankle':ankle,'lengths':lengths,'source_shift_y':shift})
    spec['anatomy']['calibration']=calibration
    oldbones={p['id']:p for p in base['bones']}; newbones={p['id']:p for p in spec['bones']}
    for animation in spec['animations'].values():
        for track in animation['tracks']:
            if track['property']=='position':
                old,new=oldbones[track['bone']]['position'],newbones[track['bone']]['position']
                track['keys']=[[t,[round(new[i]+v[i]-old[i],6) for i in range(2)]] for t,v in track['keys']]
    delta=np.array(cfg['prop'])-cfg['wrist']; spec['held_contact']['point']=(delta*SCALE).tolist()
    spec['contact_shadows']=[[p['ankle'][0]+12,0,58,11] for p in calibration]
    spec['polish']={'identity':'P01 original V5','style_reference':'P03 V10','master':MASTER.relative_to(ROOT).as_posix(),
       'full_same_source':True,'preserved_v5_rotation_curves_and_timing':True,'high_resolution_head':True,
       'approval':'pending_user_visual_review'}
    save(ART/'P01/rig.json',spec)
    files={p['file'].removeprefix('res://') for p in spec['parts']}
    files.update(v['file'].removeprefix('res://') for p in spec['drawings'] for v in p['variants'])
    files.add(spec['expression']['blink'].removeprefix('res://'))
    save(ART/'P01/source.json',{'version':12,'api_manifest':'output/imagegen/actor-lin-polish-20261115/asset-manifest.json',
       'textures':[{'file':f,'sha256':b.sha(ROOT/f)} for f in sorted(files)],'master_sha256':b.sha(MASTER)})
    save(EV/'extraction.json',{'outputs':b.RECORDS,'landmarks':cfg,'calibration':calibration})
    print(json.dumps({'version':12,'bones':len(spec['bones']),'parts':len(spec['parts']),'textures':len(files),'outputs':len(b.RECORDS)}))

if __name__=='__main__':main()
