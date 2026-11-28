'use strict';

const canvas = document.getElementById('canvas');
window.kapaiExitGame = () => {
  canvas.inert = true;
  const exit = document.createElement('section');
  exit.id = 'game-exit';
  const heading = document.createElement('h1');
  heading.textContent = '已退出游戏';
  const message = document.createElement('p');
  message.textContent = '可以关闭此页面，或重新进入游戏。';
  const restart = document.createElement('button');
  restart.type = 'button';
  restart.textContent = '重新进入游戏';
  restart.addEventListener('click', () => location.reload());
  exit.append(heading, message, restart);
  document.getElementById('game-frame').append(exit);
  restart.focus();
};
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
frame.append(controls);

const rotate = document.createElement('section');
rotate.id = 'game-rotate';
rotate.hidden = true;
rotate.setAttribute('aria-labelledby', 'game-rotate-title');
const rotateTitle = document.createElement('h1');
rotateTitle.id = 'game-rotate-title';
rotateTitle.textContent = '横屏游玩';
const rotateMessage = document.createElement('p');
rotateMessage.textContent = '请将手机横放。转回横屏即可继续当前进度。';
rotate.append(rotateTitle, rotateMessage);
frame.append(rotate);

const notice = document.createElement('div');
notice.id = 'game-fullscreen-notice';
notice.hidden = true;
notice.setAttribute('role', 'status');
workspace.append(notice);

const coarse = matchMedia('(pointer: coarse) and (hover: none)');
const standalone = matchMedia('(display-mode: standalone), (display-mode: fullscreen)');
const renderScale = Math.min(coarse.matches ? 2.5 : 2, Math.max(1, devicePixelRatio));
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

let hasLandscapeSize = false;

function resize() {
  const portrait = coarse.matches && innerHeight > innerWidth;
  const wasPortrait = !rotate.hidden;
  rotate.hidden = !portrait;
  workspace.classList.toggle('game-portrait', portrait);
  canvas.inert = portrait || Boolean(document.getElementById('game-exit'));
  if (portrait && frame.contains(document.activeElement)) document.activeElement.blur();
  // Keep the last landscape backing size while the browser rotates.
  if (portrait && hasLandscapeSize) return;

  // Godot divides the backing resolution by the same scale for layout and input.
  const width = Math.max(1, Math.round((portrait ? frame.clientHeight : frame.clientWidth) * renderScale));
  const height = Math.max(1, Math.round((portrait ? frame.clientWidth : frame.clientHeight) * renderScale));
  if (canvas.width !== width) canvas.width = width;
  if (canvas.height !== height) canvas.height = height;
  hasLandscapeSize = true;
  if (wasPortrait && !portrait && !canvas.inert) canvas.focus({ preventScroll: true });
}

let showFullscreenEntry = true;
window.kapaiShowFullscreenEntry = visible => {
  showFullscreenEntry = visible;
  updateFullscreenControls();
};

function updateFullscreenControls() {
  const active = Boolean(fullscreenElement());
  fullscreen.textContent = '全屏';
  fullscreen.setAttribute('aria-label', '进入全屏');
  const installed = standalone.matches || navigator.standalone === true;
  controls.hidden = !coarse.matches || !showFullscreenEntry || active || installed;
}

function fullscreenChanged() {
  updateFullscreenControls();
  notice.hidden = true;
  resize();
}

async function enterFullscreen() {
  if (!coarse.matches || fullscreenElement()) return;
  notice.hidden = true;
  try {
    if (!supportsFullscreen()) throw new Error('Fullscreen is unavailable');
    if (root.requestFullscreen) await root.requestFullscreen({ navigationUI: 'hide' });
    else await root.webkitRequestFullscreen();
    if (screen.orientation?.lock) {
      try { await screen.orientation.lock('landscape'); } catch { /* Rotation can be controlled by the device. */ }
    }
    if (rotate.hidden) canvas.focus({ preventScroll: true });
  } catch {
    notice.textContent = ios
      ? '从 Safari 的共享菜单选择“添加到主屏幕”，再从图标打开，可使用独立游戏窗口。'
      : '此浏览器未能进入全屏，仍可在当前窗口游玩。';
    notice.hidden = false;
  }
}

function installFullscreenGesture() {
  const capture = { capture: true, passive: false };
  const movementLimit = 12;
  let primary = null;
  let replaying = false;
  let chord = null;
  let firstTap = null;

  function consume(event) {
    event.stopImmediatePropagation();
    if (event.cancelable) event.preventDefault();
  }

  canvas.addEventListener('touchstart', event => {
    if (!coarse.matches || replaying || fullscreenElement() || standalone.matches ||
        navigator.standalone === true || !supportsFullscreen()) return;
    if (chord) {
      chord.valid = false;
      consume(event);
      return;
    }
    if (event.touches.length === 1) {
      // An ordinary swipe or tap uses the original event without any timer.
      primary = { touch: event.changedTouches[0], time: event.timeStamp };
    } else if (event.touches.length === 2 && primary && event.timeStamp - primary.time <= 85) {
      const previous = primary.touch;
      primary = null;
      // Cancel the first finger's gameplay press only for an actual chord.
      replaying = true;
      try {
        canvas.dispatchEvent(new TouchEvent('touchcancel', {
          bubbles: true, changedTouches: [previous],
        }));
      } finally { replaying = false; }
      const fingers = new Map([...event.touches].map(touch => [touch.identifier, touch]));
      chord = { fingers, started: event.timeStamp, valid: true };
      consume(event);
    } else {
      primary = null;
      firstTap = null;
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
      if (chord.valid && event.timeStamp - chord.started <= 300) {
        const fingers = [...chord.fingers.values()];
        const x = (fingers[0].clientX + fingers[1].clientX) / 2;
        const y = (fingers[0].clientY + fingers[1].clientY) / 2;
        if (firstTap && event.timeStamp - firstTap.time <= 450 &&
            Math.hypot(firstTap.x - x, firstTap.y - y) < 64) {
          firstTap = null;
          enterFullscreen();
        } else {
          firstTap = { x, y, time: event.timeStamp };
        }
      } else {
        firstTap = null;
      }
      chord = null;
      return;
    }
    if (primary && event.type === 'touchmove') {
      const { touch } = primary;
      const moved = [...event.changedTouches].find(point => point.identifier === touch.identifier);
      if (moved && Math.hypot(moved.clientX - touch.clientX, moved.clientY - touch.clientY) > movementLimit) {
        primary = null;
        firstTap = null;
      }
    }
    if (!event.touches.length) {
      primary = null;
      firstTap = null;
    }
  }

  for (const type of ['touchmove', 'touchend', 'touchcancel']) {
    canvas.addEventListener(type, moveOrEnd, capture);
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

fullscreen.addEventListener('click', enterFullscreen);
document.addEventListener('fullscreenchange', fullscreenChanged);
document.addEventListener('webkitfullscreenchange', fullscreenChanged);
standalone.addEventListener('change', fullscreenChanged);
coarse.addEventListener('change', fullscreenChanged);
new ResizeObserver(resize).observe(frame);
installFullscreenGesture();
installKeyboardBar();
fullscreenChanged();
