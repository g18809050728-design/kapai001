"""Build reproducible UI-only vignette/background derivatives from selected art."""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'output/imagegen/event-polish-20261115'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    review = json.loads((OUTPUT / 'visual-review.json').read_text(encoding='utf-8'))
    if review.get('status') != 'ai_reviewed_for_integration':
        raise SystemExit('Review the actual generated images before integration.')
    stories = json.loads((OUTPUT / 'stories.json').read_text(encoding='utf-8'))
    # The selected consultation artwork depicts a female senior; use neutral action wording.
    stories['events']['V03']['narrative'] = stories['events']['V03']['narrative'].replace('学长把笔记', '学姐把笔记')
    stories['events']['V03']['option_titles'] = {'consult': '请教选课建议'}
    config = json.loads(Path('C:/Users/Dev.LI/.codex/imagegen/config.json').read_text(encoding='utf-8-sig'))
    manifest = {'requirement_ids': ['UIR-070', 'UIR-071'], 'provider': config['base_url'],
                'model': config['model'], 'api_mode': 'images/generations; text prompt only; no uploaded reference',
                'successful_images_this_batch': 11, 'prior_successes': 110, 'cumulative_successes': 121,
                'authorized_maximum': 200, 'cost': 'not returned by service',
                'review': review, 'assets': []}
    for group in ['events', 'rooms']:
        for key, entry in stories[group].items():
            original = OUTPUT / 'originals' / f'{key}-v1.png'
            source = Image.open(original).convert('RGB')
            assert source.size == (1024, 1024), (key, source.size)
            target = ROOT / 'assets/art/events' / key
            target.mkdir(parents=True, exist_ok=True)
            # Soft perimeter only; content remains at its original resolution and scale.
            yy, xx = np.mgrid[:source.height, :source.width]
            edge = np.minimum.reduce([xx, yy, source.width - 1 - xx, source.height - 1 - yy])
            t = np.clip(edge / 66.0, 0, 1)
            alpha = np.rint(t * t * (3 - 2 * t) * 255).astype(np.uint8)
            vignette = source.convert('RGBA')
            vignette.putalpha(Image.fromarray(alpha))
            art = target / 'illustration.png'
            vignette.save(art, optimize=True)
            background = source.resize((768, 768), Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(16))
            bg = target / 'background.png'
            background.save(bg, optimize=True)
            prompt = OUTPUT / f'{key}-v1-prompt.txt'
            record = {'asset_id': key, 'requirement_id': 'UIR-070', 'version': 1,
                      'title': entry['title'], 'prompt_file': prompt.relative_to(ROOT).as_posix(),
                      'prompt_sha256': sha(prompt), 'provider': config['base_url'], 'model': config['model'],
                      'requested_size': '1024x1024', 'actual_size': list(source.size), 'quality': 'high',
                      'original': original.relative_to(ROOT).as_posix(), 'original_sha256': sha(original),
                      'selected': True, 'review_status': 'AI visual review, final user art judgment remains',
                      'derivatives': [
                          {'path': art.relative_to(ROOT).as_posix(), 'sha256': sha(art),
                           'processing': 'Original RGB untouched; add 66px smoothstep alpha perimeter, no content crop/stretch.'},
                          {'path': bg.relative_to(ROOT).as_posix(), 'sha256': sha(bg),
                           'processing': '768x768 Lanczos, Gaussian blur radius16; UI uses aspect-preserving cover and dark overlay.'}]}
            (target / 'source.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf-8')
            manifest['assets'].append(record)
    (ROOT / 'src/ui/room_stories.json').write_text(json.dumps(stories, ensure_ascii=False, indent=2), encoding='utf-8')
    (OUTPUT / 'asset-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'scenes': len(manifest['assets']), 'derived_textures': len(manifest['assets']) * 2,
                      'cumulative_successes': 121}, ensure_ascii=False))


if __name__ == '__main__':
    main()
