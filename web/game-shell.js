'use strict';

const canvas = document.getElementById('canvas');
const viewport = document.querySelector('meta[name="viewport"]');
viewport.content = 'width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no, interactive-widget=resizes-visual';
document.documentElement.lang = 'zh-CN';

const workspace = document.createElement('main');
workspace.id = 'game-workspace';
const frame = document.createElement('div');
frame.id = 'game-frame';
canvas.before(workspace);
workspace.append(frame);
frame.append(canvas, document.getElementById('status'));

const fullscreen = document.createElement('button');
fullscreen.type = 'button';
fullscreen.id = 'game-fullscreen';
const controls = document.createElement('div');
controls.id = 'game-controls';
controls.append(fullscreen);
workspace.append(controls);

const rotate = document.createElement('section');
rotate.id = 'game-rotate';
rotate.hidden = true;
const rotateTitle = document.createElement('h1');
rotateTitle.textContent = '横屏游玩';
const rotateMessage = document.createElement('p');
const rotateFullscreen = document.createElement('button');
rotateFullscreen.type = 'button';
rotateFullscreen.textContent = '全屏';
const gestureHint = document.createElement('p');
gestureHint.textContent = '双指轻点两次进入全屏';
rotate.append(rotateTitle, rotateMessage, rotateFullscreen, gestureHint);
frame.append(rotate);

const notice = document.createElement('div');
notice.id = 'game-fullscreen-notice';
notice.hidden = true;
notice.setAttribute('role', 'status');
workspace.append(notice);

const coarse = matchMedia('(pointer: coarse) and (hover: none)');
const standalone = matchMedia('(display-mode: standalone), (display-mode: fullscreen)');
const renderScale = Math.min(coarse.matches ? 1.5 : 2, Math.max(1, devicePixelRatio));
window.kapaiRenderScale = renderScale;
window.kapaiMobile = coarse.matches;
const ios = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
  (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
const root = document.documentElement;
const fullscreenElement = () => document.fullscreenElement || document.webkitFullscreenElement;
const supportsFullscreen = () => Boolean(
  (document.fullscreenEnabled && root.requestFullscreen) ||
  (document.webkitFullscreenEnabled && root.webkitRequestFullscreen)
);

function resize() {
  const portrait = coarse.matches && innerHeight > innerWidth;
  rotate.hidden = !portrait;
  workspace.classList.toggle('game-portrait', portrait);
  rotateMessage.textContent = '请横放设备。切换方向会保留当前进度。';
  canvas.inert = portrait;
  canvas.classList.toggle('game-covered', portrait);
  if (portrait) return;

  // Godot divides this backing resolution by the same scale for layout and input.
  const width = Math.max(1, Math.round(frame.clientWidth * renderScale));
  const height = Math.max(1, Math.round(frame.clientHeight * renderScale));
  if (canvas.width !== width) canvas.width = width;
  if (canvas.height !== height) canvas.height = height;
}

function fullscreenChanged() {
  const active = Boolean(fullscreenElement());
  fullscreen.textContent = active ? '退出' : '全屏';
  fullscreen.setAttribute('aria-label', active ? '退出全屏' : '进入全屏');
  fullscreen.setAttribute('aria-pressed', String(active));
  const installed = standalone.matches || navigator.standalone === true;
  controls.hidden = !coarse.matches || (installed && !active);
  rotateFullscreen.hidden = installed;
  gestureHint.hidden = installed;
  notice.hidden = true;
  resize();
}

async function toggleFullscreen() {
  if (!coarse.matches) return;
  notice.hidden = true;
  try {
    if (fullscreenElement()) {
      if (screen.orientation && screen.orientation.unlock) screen.orientation.unlock();
      await (document.exitFullscreen || document.webkitExitFullscreen).call(document);
      canvas.focus({ preventScroll: true });
      return;
    }
    if (!supportsFullscreen()) throw new Error('Fullscreen is unavailable');
    await (root.requestFullscreen || root.webkitRequestFullscreen).call(root);
    if (coarse.matches && screen.orientation && screen.orientation.lock) {
      try { await screen.orientation.lock('landscape'); } catch { /* The rotate prompt remains visible. */ }
    }
    if (rotate.hidden) canvas.focus({ preventScroll: true });
  } catch {
    notice.textContent = ios
      ? '从 Safari 的共享菜单选择“添加到主屏幕”，再从图标打开，可使用独立横屏窗口。'
      : '此浏览器未能进入全屏，仍可在当前窗口游玩。';
    notice.hidden = false;
  }
}

function installFullscreenGesture() {
  const capture = { capture: true, passive: false };
  const secondFingerWindow = 85;
  const tapWindow = 300;
  const doubleTapWindow = 450;
  const movementLimit = 18;
  let heldStart = null;
  let forwardedTouch = null;
  let replaying = false;
  let chord = null;
  let firstTap = null;

  function consume(event) {
    event.stopImmediatePropagation();
    if (event.cancelable) event.preventDefault();
  }

  function flushSingle() {
    if (!heldStart) return;
    clearTimeout(heldStart.timer);
    const { event } = heldStart;
    heldStart = null;
    forwardedTouch = event.changedTouches[0];
    replaying = true;
    event.target.dispatchEvent(new TouchEvent('touchstart', {
      bubbles: true, cancelable: true, touches: [...event.touches],
      targetTouches: [...event.targetTouches], changedTouches: [...event.changedTouches],
    }));
    replaying = false;
  }

  frame.addEventListener('touchstart', event => {
    if (!coarse.matches || replaying || fullscreenElement() ||
        event.target.closest('button, input, textarea')) return;
    if (chord) {
      chord.valid = false;
      consume(event);
      return;
    }
    if (event.touches.length === 2) {
      if (heldStart) clearTimeout(heldStart.timer);
      heldStart = null;
      if (forwardedTouch) {
        // Release the first finger outside the game before suppressing the chord.
        const release = new Touch({identifier: forwardedTouch.identifier, target: forwardedTouch.target, clientX: -100, clientY: -100});
        forwardedTouch = null;
        replaying = true;
        release.target.dispatchEvent(new TouchEvent('touchcancel', {bubbles: true, changedTouches: [release]}));
        replaying = false;
      }
      const fingers = new Map([...event.touches].map(touch => [touch.identifier, touch]));
      chord = { fingers, started: event.timeStamp, valid: true };
      consume(event);
    } else if (event.touches.length === 1) {
      heldStart = { event, timer: setTimeout(flushSingle, secondFingerWindow) };
      consume(event);
    }
  }, capture);

  function moveOrEnd(event) {
    if (replaying) return;
    if (chord) {
      consume(event);
      for (const touch of event.changedTouches) {
        const start = chord.fingers.get(touch.identifier);
        if (!start || Math.hypot(start.clientX - touch.clientX, start.clientY - touch.clientY) > movementLimit) chord.valid = false;
      }
      if (event.type === 'touchcancel') chord.valid = false;
      if (event.touches.length) return;
      if (chord.valid && event.timeStamp - chord.started <= tapWindow) {
        const fingers = [...chord.fingers.values()];
        const x = (fingers[0].clientX + fingers[1].clientX) / 2;
        const y = (fingers[0].clientY + fingers[1].clientY) / 2;
        if (firstTap && event.timeStamp - firstTap.time <= doubleTapWindow &&
            Math.hypot(firstTap.x - x, firstTap.y - y) < 64) {
          firstTap = null;
          toggleFullscreen();
        } else {
          firstTap = { x, y, time: event.timeStamp };
        }
      } else {
        firstTap = null;
      }
      chord = null;
      return;
    }
    if (heldStart) flushSingle();
    if (forwardedTouch && !event.touches.length) {
      forwardedTouch = null;
      firstTap = null;
    }
  }

  for (const type of ['touchmove', 'touchend', 'touchcancel']) {
    frame.addEventListener(type, moveOrEnd, capture);
  }
}

function installKeyboardBar() {
  const done = document.createElement('button');
  done.type = 'button';
  done.id = 'game-keyboard-done';
  done.textContent = '完成';
  done.hidden = true;
  frame.append(done);
  let editing = null;

  function positionKeyboardBar() {
    frame.style.setProperty('--keyboard-top', `${window.visualViewport?.offsetTop || 0}px`);
  }

  frame.addEventListener('focusin', event => {
    if (!coarse.matches || !event.target.matches('input, textarea')) return;
    editing = event.target;
    editing.classList.add('game-keyboard-field');
    done.hidden = false;
    positionKeyboardBar();
  });
  frame.addEventListener('focusout', event => {
    if (event.target !== editing) return;
    editing.classList.remove('game-keyboard-field');
    editing = null;
    done.hidden = true;
  });
  done.addEventListener('pointerdown', event => event.preventDefault());
  done.addEventListener('click', () => {
    editing?.blur();
    canvas.focus({ preventScroll: true });
  });
  window.visualViewport?.addEventListener('resize', positionKeyboardBar);
  window.visualViewport?.addEventListener('scroll', positionKeyboardBar);
}

fullscreen.addEventListener('click', toggleFullscreen);
rotateFullscreen.addEventListener('click', toggleFullscreen);
document.addEventListener('fullscreenchange', fullscreenChanged);
document.addEventListener('webkitfullscreenchange', fullscreenChanged);
standalone.addEventListener('change', fullscreenChanged);
coarse.addEventListener('change', fullscreenChanged);
new ResizeObserver(resize).observe(frame);
installFullscreenGesture();
installKeyboardBar();
fullscreenChanged();
