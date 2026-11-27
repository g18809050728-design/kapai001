from pathlib import Path
from io import BytesIO
import argparse
import json
from PIL import Image, ImageChops, ImageStat
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/verification/mobile-touch-20261127'
WIDTH, HEIGHT = 844, 390


def swipe(cdp, page, x, y, dy, steps=10):
    cdp.send('Input.dispatchTouchEvent', {'type': 'touchStart', 'touchPoints': [{'x': x, 'y': y}]})
    for i in range(1, steps + 1):
        cdp.send('Input.dispatchTouchEvent', {'type': 'touchMove', 'touchPoints': [{'x': x, 'y': y + dy * i / steps}]})
        page.wait_for_timeout(17)
    cdp.send('Input.dispatchTouchEvent', {'type': 'touchEnd', 'touchPoints': []})


def difference(a, b, box):
    return max(ImageStat.Stat(ImageChops.difference(a.crop(box), b.crop(box))).mean)


def run(url):
    checks = {}
    issues = []
    OUT.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(args=['--use-angle=swiftshader', '--enable-unsafe-swiftshader'])
        context = browser.new_context(viewport={'width': WIDTH, 'height': HEIGHT}, device_scale_factor=2,
                                      is_mobile=True, has_touch=True)
        page = context.new_page()
        page.on('pageerror', lambda e: issues.append(str(e)))
        page.on('console', lambda e: issues.append(e.text) if e.type == 'error' else None)
        page.goto(url, timeout=120_000)
        page.wait_for_function("document.querySelector('#game-frame canvas') && !document.querySelector('#status')", timeout=120_000)
        page.wait_for_timeout(1100)
        cdp = context.new_cdp_session(page)

        def capture(name):
            data = page.screenshot(path=OUT / (name + '.png'), scale='css', animations='disabled')
            return Image.open(BytesIO(data)).convert('RGB')

        def tap(x, y, pause=350):
            page.touchscreen.tap(x, y)
            page.wait_for_timeout(pause)

        def canvas_fills_viewport():
            return page.locator('#canvas').evaluate('canvas => {const r=canvas.getBoundingClientRect(); return r.x===0 && r.y===0 && r.width===innerWidth && r.height===innerHeight}')

        checks['canvas fills viewport before fullscreen'] = canvas_fills_viewport()
        page.locator('#game-fullscreen').tap()
        page.wait_for_function('document.fullscreenElement === document.documentElement')
        checks['real fullscreen with no exit or reserved rail'] = canvas_fills_viewport() and page.locator('#game-controls').is_hidden()
        capture('mobile-fullscreen-menu')
        # Gallery gestures begin on card art, not in gaps or on scrollbars.
        tap(74, 250)
        before = capture('gallery-initial')
        swipe(cdp, page, 112, 274, -91)
        page.wait_for_timeout(450)
        after = capture('gallery-card-drag')
        gallery_clip = (25, 175, 800, 305)
        checks['gallery drag pans while toolbar stays'] = difference(before, after, gallery_clip) > 8 and difference(before, after, (0, 0, 450, 70)) < 2
        for _ in range(4):
            swipe(cdp, page, 112, 276, -107)
            page.wait_for_timeout(210)
        latest = capture('gallery-flick-prefetch')
        checks['gallery keeps scrolling and appends rows'] = difference(after, latest, gallery_clip) > 9 and difference(after, latest, (350, 332, 640, 378)) > .3
        tap(112, 241)
        detail = capture('gallery-tap-detail')
        checks['tap still opens detail after gestures'] = difference(detail, latest, (0, 0, 820, 160)) > 8
        tap(87, 352)
        tap(74, 352)
        tap(290, 191)
        tap(747, 323, 800)
        starting_map = capture('local-start-map')
        # The first reachable node sits low on the map; dragging down reveals upper layers.
        swipe(cdp, page, 314, 214, 63)
        page.wait_for_timeout(450)
        panned_map = capture('map-drag-from-node')
        checks['main map pans from a node without changing screens'] = difference(starting_map, panned_map, (42, 108, 545, 275)) > 5 and difference(starting_map, panned_map, (0, 0, 280, 100)) < 3
        tap(365, 350)  # locate current
        tap(314, 214)
        selected_map = capture('map-first-tap-selects')
        checks['one tap previews without entering'] = difference(starting_map, selected_map, (674, 326, 815, 375)) > 4 and difference(starting_map, selected_map, (0, 0, 280, 99)) < 3
        tap(314, 214, 1300)
        battle = capture('map-second-tap-enters')
        checks['second tap enters battle on local play with no tutorial'] = difference(starting_map, battle, (30, 130, 800, 280)) > 13
        # Open using the battle toolbar, then start dragging on the current marker.
        tap(661, 21, 470)
        overlay = capture('battle-map-overlay')
        swipe(cdp, page, 310, 237, 52)
        page.wait_for_timeout(400)
        panned_overlay = capture('battle-map-overlay-drag')
        checks['read-only map pans without leaving overlay'] = difference(overlay, panned_overlay, (50, 95, 541, 255)) > 5 and difference(overlay, panned_overlay, (80, 38, 451, 78)) < 3
        tap(730, 59, 420)
        checks['closing overlay returns to same battle'] = difference(capture('battle-after-map-close'), battle, (5, 0, 300, 55)) < 3
        page.evaluate('document.exitFullscreen()')  # system exits fullscreen; the game supplies no exit button.
        page.set_viewport_size({'width': HEIGHT, 'height': WIDTH})
        page.locator('#game-rotate').wait_for(state='visible')
        checks['portrait prompts without leaving session'] = page.locator('#canvas').is_hidden()
        page.set_viewport_size({'width': WIDTH, 'height': HEIGHT})
        page.locator('#game-rotate').wait_for(state='hidden')
        checks['landscape restores the canvas'] = canvas_fills_viewport() and page.locator('#canvas').is_visible()
        desktop = browser.new_page(viewport={'width': 1280, 'height': 800})
        desktop.goto(url, timeout=120_000)
        desktop.wait_for_function("document.querySelector('#game-frame canvas') && !document.querySelector('#status')", timeout=120_000)
        checks['desktop has no mobile fullscreen control'] = desktop.locator('#game-controls').is_hidden()
        browser.close()
    checks['no page or engine errors'] = not issues
    print(json.dumps({'checks': checks, 'errors': issues}, ensure_ascii=False, indent=2))
    return all(checks.values())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Browser touch acceptance on an isolated local Web export with the local account adapter.')
    parser.add_argument('url', nargs='?', default='http://127.0.0.1:8064/')
    raise SystemExit(0 if run(parser.parse_args().url) else 1)
