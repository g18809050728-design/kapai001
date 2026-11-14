"""Remove accidentally generated fixed sleeves from the otherwise complete torso."""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image, ImageDraw

BASE = Path(__file__).resolve().parent
source = BASE/'parts/P01_torso.png'
target = BASE/'parts/P01_torso_articulation.png'
im = Image.open(source).convert('RGBA')
# Inspected contour in the 278x251 extracted source. Keep the native canvas so
# that all parent attachments retain the same source coordinate system.
reference_size = (278, 251)
outline = [(108,0),(168,0),(217,47),(239,67),(230,108),(224,160),
           (225,210),(232,247),(58,250),(52,236),(58,179),(60,141),
           (51,103),(45,71),(68,48)]
outline = [(round(x*im.width/reference_size[0]), round(y*im.height/reference_size[1]))
           for x,y in outline]
mask = Image.new('L',(im.width*4,im.height*4))
ImageDraw.Draw(mask).polygon([(x*4,y*4) for x,y in outline],fill=255)
mask = mask.resize(im.size,Image.Resampling.LANCZOS)
pixels = np.array(im)
pixels[:,:,3] = np.minimum(pixels[:,:,3], np.array(mask))
Image.fromarray(pixels).save(target)
report = dict(source=source.relative_to(BASE).as_posix(),
              source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
              output=target.relative_to(BASE).as_posix(),
              output_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
              contour_px=outline, method='inspected alpha contour removes fixed sleeve shapes; native canvas retained',
              hidden_region_source='original atlas painted full central jacket and T-shirt; no full-character crop, no newly invented or synthesized torso pixels',
              limitations='this local cleanup does not approve the overall illustration style or prove every joint seam')
(BASE/'torso-refinement.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('Saved torso with independently movable sleeves:',target.name)
