"""Build the P01 G6 offline assembly evidence; never reads or writes game state."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import math
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[3]
EVIDENCE = ROOT / 'artifacts/verification/p01-parts-20261114'
SIZE = (640, 720)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def create_rig():
    # Body data is deliberately separate from sprite scale and draw order.
    # Values are inspected candidate assembly values, not final game animation.
    specs = [
        # id, parent, pivot fraction, rendered size, parent joint offset, local angle, z
        ('pelvis_coat_hem', None, (.5, .10), (144, 88), (320, 400), 0, 9),
        ('torso', 'pelvis_coat_hem', (.50, .92), (183, 168), (0, -6), 0, 10),
        ('head', 'torso', (.42, .91), (125, 147), (8, -139), 0, 12),
        ('hair_back', 'head', (.50, .80), (143, 102), (0, -64), 0, 11),
        ('hair_front', 'head', (.50, .82), (143, 96), (3, -64), 0, 13),
        ('arm_far_upper', 'torso', (.55, .14), (61, 110), (-62, -125), -14, 4),
        ('arm_far_lower_hand', 'arm_far_upper', (.49, .12), (43, 112), (0, 77), -52, 16),
        ('arm_near_upper', 'torso', (.52, .13), (68, 109), (61, -124), -8, 18),
        ('arm_near_lower', 'arm_near_upper', (.48, .12), (45, 110), (0, 78), -23, 19),
        ('hand_near', 'arm_near_lower', (.57, .14), (39, 62), (0, 85), -5, 20),
        ('leg_far_upper', 'pelvis_coat_hem', (.48, .14), (64, 108), (-31, 41), 8, 3),
        ('leg_far_lower_foot', 'leg_far_upper', (.28, .09), (86, 120), (0, 80), -8, 2),
        ('leg_near_upper', 'pelvis_coat_hem', (.47, .14), (68, 108), (32, 41), -8, 8),
        ('leg_near_lower_foot', 'leg_near_upper', (.28, .10), (90, 120), (0, 80), 8, 7),
        ('laptop', 'arm_far_lower_hand', (.42, .65), (87, 93), (0, 89), 56, 15),
        ('pen', 'hand_near', (.50, .60), (12, 92), (6, 35), -120, 21),
    ]
    parts = []
    for pid, parent, pivot, target, offset, angle, z in specs:
        filename = 'P01_torso_articulation.png' if pid == 'torso' else 'P01_' + pid + '.png'
        path = BASE / 'parts' / filename
        with Image.open(path) as im:
            w, h = im.size
        parts.append(dict(id=pid, file='parts/' + filename, parent=parent,
                          pivot_px=[round(w * pivot[0], 3), round(h * pivot[1], 3)],
                          scale=[target[0] / w, target[1] / h],
                          rendered_size=list(target), rest_offset=list(offset),
                          rest_angle_deg=angle, z_index=z,
                          role='prop' if pid in ('laptop', 'pen') else 'body',
                          image_size=[w, h], sha256=sha(path)))
    rig = dict(schema='p01-offline-parts-v1', entity_id='P01', version='parts-v1',
               requirement_ids=['UIR-052', 'UIR-054', 'UIR-057'],
               canvas_size=list(SIZE), coordinate_system='x right, y down; degrees clockwise',
               transform='joint = parent_joint + rotate(parent_angle, rest_offset); angle = parent_angle + rest_angle + delta; sprite scale does not propagate',
               purpose='G6 asset articulation and seam inspection only; not game timing or runtime',
               source_atlas='P01-parts-atlas-v1.png', source_atlas_sha256=sha(BASE / 'P01-parts-atlas-v1.png'),
               prop_ids=['laptop', 'pen'], parts=parts,
               poses={
                   'breath': {'torso': -2, 'head': 3, 'arm_near_upper': 3, 'arm_far_upper': -2},
                   'reach': {'torso': -5, 'head': 7, 'arm_near_upper': -45, 'arm_near_lower': -25, 'hand_near': 13, 'leg_near_upper': -4, 'leg_near_lower_foot': 4},
                   'lean': {'torso': 11, 'head': -9, 'arm_near_upper': 20, 'arm_near_lower': 18, 'arm_far_upper': 4, 'leg_near_upper': -10, 'leg_near_lower_foot': 10},
                   'fold': {'torso': 17, 'head': 9, 'arm_near_upper': 27, 'arm_near_lower': -57, 'arm_far_upper': 12, 'leg_far_upper': 8, 'leg_far_lower_foot': -8},
               },
               human_acceptance='pending', release_license='pending', runtime_integration='not_started')
    (BASE / 'rig.json').write_text(json.dumps(rig, ensure_ascii=False, indent=2), encoding='utf-8')
    return rig


def joints(rig, pose=None, amount=1.0):
    pose = pose or {}
    parts = {p['id']: p for p in rig['parts']}
    result = {}

    def visit(pid):
        if pid in result:
            return result[pid]
        p = parts[pid]
        px, py, pa = visit(p['parent']) if p['parent'] else (0, 0, 0)
        x, y = p['rest_offset']
        rad = math.radians(pa)
        result[pid] = (px + math.cos(rad)*x - math.sin(rad)*y,
                       py + math.sin(rad)*x + math.cos(rad)*y,
                       pa + p['rest_angle_deg'] + pose.get(pid, 0)*amount)
        return result[pid]

    for p in rig['parts']:
        visit(p['id'])
    return result


def layer(p, state):
    im = Image.open(BASE / p['file']).convert('RGBA')
    x, y, angle = state[p['id']]
    c, s = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    sx, sy = p['scale']
    qx, qy = p['pivot_px']
    # Inverse world->source matrix for Pillow; no repeated raster transforms.
    affine = (c/sx, s/sx, qx-(c*x+s*y)/sx,
              -s/sy, c/sy, qy+(s*x-c*y)/sy)
    return im.transform(SIZE, Image.Transform.AFFINE, affine, Image.Resampling.BICUBIC)


def render(rig, pose=None, amount=1.0, props=True, background=None, bones=False):
    state = joints(rig, pose, amount)
    canvas = Image.new('RGBA', SIZE, background or (0, 0, 0, 0))
    for p in sorted(rig['parts'], key=lambda p:p['z_index']):
        if props or p['role'] != 'prop':
            canvas.alpha_composite(layer(p, state))
    if bones:
        draw = ImageDraw.Draw(canvas)
        for p in rig['parts']:
            x, y, _ = state[p['id']]
            if p['parent']:
                px, py, _ = state[p['parent']]
                draw.line((px, py, x, y), fill=(240, 189, 74, 190), width=2)
            draw.ellipse((x-3, y-3, x+3, y+3), fill=(255, 240, 165, 255))
    return canvas


def label(draw, xy, text, fill='white', size=18):
    font_path = Path('C:/Windows/Fonts/consola.ttf')
    font = ImageFont.truetype(str(font_path), size) if font_path.exists() else ImageFont.load_default()
    draw.text(xy, text, font=font, fill=fill)


def evidence(rig):
    render(rig).save(BASE / 'assembled-rest.png')
    render(rig, props=False).save(BASE / 'assembled-body-only.png')
    names = ['rest', 'breath', 'reach', 'lean', 'fold']
    sheet = Image.new('RGB', (640*5, 760), '#18262d')
    for i, name in enumerate(names):
        im = render(rig, rig['poses'].get(name), background='#18262d')
        sheet.paste(im.convert('RGB'), (640*i, 35))
        label(ImageDraw.Draw(sheet), (640*i+24, 10), name.upper()+' / G6 ASSET CHECK')
    sheet.save(BASE / 'pose-contact.jpg', quality=93)
    render(rig, rig['poses']['reach'], props=False, background='#e4e3db', bones=True).save(BASE / 'joint-inspection.png')
    frames = []
    for name in ('breath', 'reach', 'lean', 'fold'):
        for i in range(25):
            amount = .5-.5*math.cos(2*math.pi*i/24)
            im = render(rig, rig['poses'][name], amount, background='#18262d')
            draw = ImageDraw.Draw(im)
            label(draw, (18, 20), 'P01 / '+name.upper()+' / G6 ASSET CHECK', size=16)
            frames.append(im.convert('RGB').resize((448, 504), Image.Resampling.LANCZOS))
    frames[0].save(BASE / 'articulation-check.gif', save_all=True, append_images=frames[1:], duration=70, loop=0)
    # Actual local alpha around body joints, for every inspected pose.
    join_ids = ['torso', 'head', 'arm_far_upper', 'arm_far_lower_hand', 'arm_near_upper',
                'arm_near_lower', 'hand_near', 'leg_far_upper', 'leg_far_lower_foot',
                'leg_near_upper', 'leg_near_lower_foot']
    byid = {p['id']:p for p in rig['parts']}
    rows = []
    for name in names:
        state = joints(rig, rig['poses'].get(name))
        for pid in join_ids:
            x, y, _ = state[pid]
            ix, iy = round(x), round(y)
            yy, xx = np.mgrid[-5:6, -5:6]
            mask = xx*xx + yy*yy <= 25
            parent = byid[pid]['parent']
            pa = np.array(layer(byid[parent], state))[:, :, 3]
            ca = np.array(layer(byid[pid], state))[:, :, 3]
            # Inspect only the two connecting parts. Other layers and props
            # must not hide a missing cap and falsely make this sample pass.
            alpha = np.maximum(pa, ca)
            patch = alpha[iy-5:iy+6, ix-5:ix+6]
            coverage = float((patch[mask] >= 230).mean()) if patch.shape == (11,11) else 0.0
            overlap = int(((pa > 200) & (ca > 200)).sum())
            rows.append(dict(pose=name, joint=pid, canvas_xy=[x,y], disk_radius_px=5,
                             opaque_disk_fraction=coverage, parent_child_overlap_px=overlap,
                             passed=coverage >= .97 and overlap >= 30))
    rest = render(rig)
    rest_back = render(rig, rig['poses']['reach'], 0)
    changed_world = {name:[pid for pid, state in joints(rig, pose).items()
                           if abs(state[2]-joints(rig)[pid][2]) > .1]
               for name, pose in rig['poses'].items()}
    changed_local = {name:{pid:delta for pid,delta in pose.items()
                          if byid[pid]['role']=='body' and abs(delta)>.1}
                     for name,pose in rig['poses'].items()}
    with Image.open(BASE / 'articulation-check.gif') as gif:
        actual_frames = gif.n_frames
        total_duration = 0
        for i in range(gif.n_frames):
            gif.seek(i)
            total_duration += gif.info.get('duration', 0)
    report = dict(created_at_utc=datetime.now(timezone.utc).isoformat(), scope='offline asset checks only',
                  part_count=len(rig['parts']), body_count=sum(p['role']=='body' for p in rig['parts']),
                  prop_count=2, pose_count=5, planned_gif_frames=len(frames),
                  gif_frames=actual_frames, gif_total_duration_ms=total_duration,
                  body_relative_rotations_local_delta_deg=changed_local,
                  world_angle_changes=changed_world,
                  exact_reset=np.array_equal(np.array(rest), np.array(rest_back)),
                  joint_checks=rows, failed_joint_checks=[r for r in rows if not r['passed']],
                  visual_review='pending; disk samples do not prove all seams or visual quality',
                  runtime_test='not_run')
    (EVIDENCE / 'articulation-check.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({k:report[k] for k in ('part_count','body_count','pose_count','gif_frames','exact_reset')}, ensure_ascii=False))
    print('Joint samples:', len(rows), 'failed:', len(report['failed_joint_checks']))


if __name__ == '__main__':
    rig = json.loads((BASE/'rig.json').read_text(encoding='utf-8')) if '--keep-rig' in sys.argv else create_rig()
    evidence(rig)
