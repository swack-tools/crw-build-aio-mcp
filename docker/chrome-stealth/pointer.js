// Move the pointer the way a person would, with xdotool on the virtual
// display: real input, which pages can't tell from a hand on a mouse.
//
// - When a page opens, the pointer wanders over it and scrolls a little.
//   Behavior checks (bot.incolumitas.com, and the sensors Akamai, HUMAN and
//   DataDome put on pages) score a page that loads with no pointer movement
//   at all as a bot.
// - When a page shows Cloudflare's Turnstile checkbox ("Verify you are
//   human"), it clicks it. Cloudflare lets this Chrome through most
//   challenges unasked, but some sites always want the click, and a mouse
//   event sent over the DevTools protocol reports the same screen and page
//   coordinates, a known automation tell.
//
// Pages are found and measured over this script's own DevTools session, in an
// isolated world the page can't see.
const { execFile } = require('child_process');
const { promisify } = require('util');

const run = promisify(execFile);
// Chrome's DevTools port, and the size of the screen windows can use.
const [chromePort, SCREEN_W, SCREEN_H] = process.argv.slice(2).map(Number);
const TICK_MS = 1000;
// A challenge Chrome passes unasked shows the widget for a few seconds while
// it verifies; only a widget still unsolved after this long is clicked.
const PATIENCE_MS = 4000;
// Clicks per page; a widget that is still there after these won't clear.
const MAX_CLICKS = 3;
// Turnstile's iframe is 300x65 with its checkbox centred 21px from the left.
const WIDGET_WIDTH = 300;
const CHECKBOX_X = 21;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const log = (msg) => console.log(`chrome-stealth pointer: ${msg}`);
const xdo = (...args) => run('xdotool', args.map(String));
const rand = (min, max) => min + Math.random() * (max - min);
// Wander within this much of the screen, clear of the toolbar and taskbar.
const WANDER = { left: 80, top: 200, right: SCREEN_W - 80, bottom: SCREEN_H - 140 };

// The widget's iframe sits in a closed shadow root, so it is found through
// the element holding Turnstile's hidden response field, which is as wide as
// its container with the widget at the left.
const widgetJs = (scroll) => `(() => {
  const input = document.querySelector('input[name="cf-turnstile-response"]');
  if (!input || input.value) return null;
  const host = input.parentElement;
  ${scroll ? "host.scrollIntoView({ block: 'center', inline: 'nearest' });" : ''}
  const r = host.getBoundingClientRect();
  return r.width >= ${WIDGET_WIDTH} && r.height >= 50 ? { x: r.x, y: r.y, width: r.width, height: r.height } : null;
})()`;
// Records where the page last saw the pointer, to map page to screen coordinates.
const POINTER_JS = `(() => {
  if (window.__pointer === undefined) {
    window.__pointer = null;
    document.addEventListener('mousemove', (e) => { window.__pointer = { x: e.clientX, y: e.clientY }; }, true);
  }
  return window.__pointer;
})()`;

function connect(url) {
  const ws = new WebSocket(url);
  const pending = new Map();
  let id = 0;
  ws.onmessage = (m) => {
    const msg = JSON.parse(m.data);
    const done = msg.id && pending.get(msg.id);
    if (!done) return;
    pending.delete(msg.id);
    if (msg.error) done.reject(new Error(msg.error.message));
    else done.resolve(msg.result);
  };
  const closed = new Promise((resolve) => ws.addEventListener('close', () => {
    for (const done of pending.values()) done.reject(new Error('DevTools connection closed'));
    pending.clear();
    resolve();
  }));
  const send = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
    if (ws.readyState !== WebSocket.OPEN) return reject(new Error('DevTools connection closed'));
    pending.set(++id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params, sessionId }));
  });
  return new Promise((resolve, reject) => {
    ws.addEventListener('open', () => resolve({ send, closed, isOpen: () => ws.readyState === WebSocket.OPEN }));
    ws.addEventListener('error', () => reject(new Error(`cannot connect to ${url}`)));
  });
}

async function evaluate(cdp, page, expression) {
  if (!page.world) {
    const { frameTree } = await cdp.send('Page.getFrameTree', {}, page.sessionId);
    const { executionContextId } = await cdp.send('Page.createIsolatedWorld',
      { frameId: frameTree.frame.id, worldName: 'chrome-stealth' }, page.sessionId);
    page.world = executionContextId;
  }
  const r = await cdp.send('Runtime.evaluate',
    { expression, contextId: page.world, returnByValue: true }, page.sessionId);
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.text);
  return r.result.value;
}

// Glide to (x, y) along a slightly curved path that eases in and out.
async function glide(x, y) {
  const { stdout } = await run('xdotool', ['getmouselocation', '--shell']);
  const from = Object.fromEntries(stdout.trim().split('\n').map((l) => l.split('=')).map(([k, v]) => [k, Number(v)]));
  const steps = Math.round(rand(14, 26));
  const bend = { x: rand(-60, 60), y: rand(-40, 40) };
  for (let i = 1; i <= steps; i++) {
    const t = i / steps;
    const ease = t * t * (3 - 2 * t);
    const arc = Math.sin(Math.PI * t);
    await xdo('mousemove', Math.round(from.X + (x - from.X) * ease + bend.x * arc),
      Math.round(from.Y + (y - from.Y) * ease + bend.y * arc));
    await sleep(rand(8, 22));
  }
}

async function wander() {
  for (let i = Math.round(rand(3, 5)); i > 0; i--) {
    await glide(rand(WANDER.left, WANDER.right), rand(WANDER.top, WANDER.bottom));
    await sleep(rand(150, 600));
    // Scroll a notch now and then; button 5 is the wheel turning down.
    if (Math.random() < 0.4) await xdo('click', 5);
  }
}

async function click(cdp, page, target) {
  const box = await evaluate(cdp, page, widgetJs(true));
  if (!box) return false;
  await sleep(300);
  const left = box.width > WIDGET_WIDTH ? box.x : box.x + (box.width - WIDGET_WIDTH) / 2;
  const goal = {
    x: left + CHECKBOX_X + (Math.random() - 0.5) * 6,
    y: box.y + box.height / 2 + (Math.random() - 0.5) * 6,
  };
  // Where the page sits on the screen depends on the window and its toolbar,
  // so move the pointer onto the page (below the widget) and read back where
  // the page saw it. That also confirms the page is the one in front.
  await evaluate(cdp, page, POINTER_JS);
  const probe = { x: Math.round(goal.x + 40), y: Math.round(goal.y + 150) };
  await xdo('mousemove', probe.x, probe.y);
  await sleep(80);
  await xdo('mousemove', probe.x + 3, probe.y + 2);
  await sleep(150);
  const seen = await evaluate(cdp, page, 'window.__pointer');
  if (!seen) return false;
  await glide(Math.round(goal.x + probe.x + 3 - seen.x), Math.round(goal.y + probe.y + 2 - seen.y));
  await sleep(rand(120, 320));
  await xdo('click', 1);
  log(`clicked in ${target.url}`);
  return true;
}

async function check(cdp, target, page) {
  if (page.url !== target.url) {
    Object.assign(page, { url: target.url, world: null, since: null, clicks: 0 });
    await cdp.send('Target.activateTarget', { targetId: target.targetId });
    await wander();
  }
  const box = await evaluate(cdp, page, widgetJs(false));
  if (!box) {
    page.since = null;
    return;
  }
  page.since ??= Date.now();
  if (Date.now() - page.since < PATIENCE_MS || page.clicks >= MAX_CLICKS) return;
  await cdp.send('Target.activateTarget', { targetId: target.targetId });
  if (await click(cdp, page, target)) {
    page.clicks++;
    page.since = Date.now();
  }
}

async function watch() {
  const version = await (await fetch(`http://127.0.0.1:${chromePort}/json/version`)).json();
  const cdp = await connect(version.webSocketDebuggerUrl);
  const pages = new Map();
  while (cdp.isOpen()) {
    await Promise.race([sleep(TICK_MS), cdp.closed]);
    if (!cdp.isOpen()) break;
    const { targetInfos } = await cdp.send('Target.getTargets');
    const live = new Set();
    for (const target of targetInfos) {
      if (target.type !== 'page' || !/^https?:/.test(target.url)) continue;
      live.add(target.targetId);
      let page = pages.get(target.targetId);
      try {
        if (!page) {
          const { sessionId } = await cdp.send('Target.attachToTarget', { targetId: target.targetId, flatten: true });
          page = { sessionId, url: null };
          pages.set(target.targetId, page);
        }
        await check(cdp, target, page);
      } catch {
        // Mid-navigation or closing; the next tick looks again.
        if (page) page.world = null;
      }
    }
    for (const [targetId, page] of pages) {
      if (live.has(targetId)) continue;
      pages.delete(targetId);
      cdp.send('Target.detachFromTarget', { sessionId: page.sessionId }).catch(() => {});
    }
  }
}

(async () => {
  for (;;) {
    await watch().catch((err) => log(err.message));
    await sleep(2000);
  }
})();
