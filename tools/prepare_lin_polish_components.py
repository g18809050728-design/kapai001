"""Create documented, uniformly enlarged same-master edit targets and masks."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
RAW=ROOT/'output/imagegen/actor-lin-polish-20261115'

def main():
    source=Image.open(RAW/'p01-master-v1.png').convert('RGBA')
    records={}
    for key, box, scale, offset in [('face',(410,50,650,355),3,(150,48)),('sleeve',(250,325,432,623),3,(230,60))]:
        target=Image.new('RGBA',(1024,1024),'#ff00ff')
        crop=source.crop(box).resize((round((box[2]-box[0])*scale),round((box[3]-box[1])*scale)),Image.Resampling.LANCZOS)
        target.alpha_composite(crop,offset)
        target.convert('RGB').save(RAW/f'p01-{key}-input.png')
        records[key]={'source_crop':list(box),'scale':scale,'offset':list(offset)}
    mask=Image.new('RGBA',(1024,1536),'white'); d=ImageDraw.Draw(mask)
    d.polygon([(250,349),(356,315),(416,349),(425,421),(564,421),(582,574),(366,630),(250,614)],fill=(0,0,0,0))
    d.polygon([(632,348),(712,370),(749,507),(994,344),(1002,620),(658,635),(637,573)],fill=(0,0,0,0))
    mask.save(RAW/'p01-trunk-mask.png')
    (RAW/'edit-registration.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
    prompts={
    'face-neutral-v1': '''Use case: identity-preserve
Asset type: enlarged clean painted P01 Lin head/neck detail for a 2D game sprite.
Input image 1 is the exact Lin edit target, already enlarged. Image 2 is ONLY Shen's illustration rendering-style reference.
Refine the same Lin drawing at this enlarged resolution: beautifully clean adult eyes through thin black rectangular glasses, fine brows, natural compact nose, controlled lips and jaw, organized dark hair strands with crisp tapered tips, believable subtle warm skin shading, clean ear anatomy. Match image 2's professional thin linework and restrained painted planes. Keep the SAME identity, face viewing angle, calm intelligent expression, head/neck proportions and exact silhouette, outline position, hair locks, glasses position and collar geometry from image 1. No crop/zoom/reposition; all magenta and silhouette stay registered. No thick eyeliner, stubble, exaggerated pointed chin, zombie pallor, new highlights or accessories. Do not copy Shen's face or clothing. Retain flat pure #ff00ff background. Sharply finished painting with fine material detail, not blurry sharpening or heavy texture.''',
    'trunk-v1': '''Use case: precise-object-edit
Asset type: hidden torso reconstruction from the SAME Lin master for 2D skeletal animation.
In the editable regions, remove BOTH complete arms, hands, pen and entire laptop. Reconstruct a continuous armless dark teal jacket and ivory button shirt beneath the removed arms, with coherent original zipper, pockets, fabric folds and side seams. Finish the hidden cloth behind the forearm and cuffs. Keep the exact master body placement, same shoulder width, jacket hem, neckline and collar, neck, head, legs and entire unmasked region unchanged. Arms are detached at shoulder seam; leave broad continuous fabric shoulders, not dark empty holes or amputated skin stumps. No hand/skin/pen/keyboard remnants on the garment. Same refined thin contour and hand-painted style as the source. All outside the torso is flat solid magenta #ff00ff. No text, props or cast shadows.''',
    'sleeve-v1': '''Use case: precise-object-edit
Asset type: same-master isolated near upper-arm rolled sleeve for 2D animation.
Keep ONLY the large dark teal sleeve on the left of this image, from its original shoulder cap down to its rolled cuff at the bottom. Remove the chest/torso fragments, bare forearm, hand and pen, reconstructing uninterrupted sleeve fabric where the forearm concealed it. The resulting one sleeve is the exact same shape, placement, scale, shoulder cap and bottom cuff as the input; do not move, straighten, rotate or resize it. Bottom cuff must have a complete clean fabric overlap for the elbow. The sleeve keeps its full natural volume and original refined painted folds, teal outer fabric and pale grey rolled cuff. Pure solid #ff00ff all around this single isolated sleeve; no head, neck, trunk, skin, hand, pen, other arm or objects. Preserve the exact registration within this 1024x1024 image.'''
    }
    (RAW/'prompts').mkdir(exist_ok=True)
    for key,prompt in prompts.items(): (RAW/'prompts'/f'p01-{key}.txt').write_text(prompt,encoding='utf-8')
    print('Prepared 3 component edit targets/prompts; API calls: 0')

if __name__=='__main__': main()
