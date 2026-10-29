/**
 * Clicks Cloudflare's Turnstile checkbox ("Verify you are human") when a tab
 * shows one.
 *
 * Camoufox gets past Cloudflare's background checks but is then often shown
 * the checkbox, which a person clicks and nothing on this server would. The
 * click has to be a real one: Playwright's mouse events never reach the
 * checkbox (it is in a cross-origin iframe), so this moves the X11 pointer on
 * Camoufox's virtual display with xdotool instead.
 */

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { removeXvfbDisplayFiles } from '../../lib/tmp-cleanup.js';

const run = promisify(execFile);

// The virtual screen. Camoufox sizes each window from its fingerprint (up to
// 4K), and the core's 1280x720 screen leaves the rest of a larger window where
// no pointer can reach.
const SCREEN = '3840x2160x24';
// How long a tab is watched after it opens, and how often.
const WATCH_MS = 60_000;
const TICK_MS = 1000;
// Clicks per tab; a widget that is still there after these won't clear.
const MAX_CLICKS = 3;
// Turnstile's iframe is 300x65 with its checkbox centred 21px from the left.
const WIDGET_WIDTH = 300;
const CHECKBOX_X = 21;

export async function register(app, ctx) {
  const { events, log, VirtualDisplay } = ctx;

  class LargeVirtualDisplay extends VirtualDisplay {
    get xvfb_args() {
      const args = [...super.xvfb_args];
      const idx = args.indexOf('-screen');
      if (idx >= 0) args[idx + 2] = SCREEN;
      return args;
    }

    kill() {
      const proc = this.proc;
      if (proc && !this.filesCleanupRegistered) {
        this.filesCleanupRegistered = true;
        const cleanup = () => removeXvfbDisplayFiles(this.display);
        if (proc.exitCode === null) proc.once('exit', cleanup);
        else cleanup();
      }
      return super.kill();
    }
  }
  try {
    ctx.plugin.registerVirtualDisplayProvider(() => new LargeVirtualDisplay());
  } catch (err) {
    log('warn', 'turnstile: another plugin provides the display; widgets past its edge cannot be clicked', { error: err.message });
  }

  let display = null;
  events.on('browser:launched', ({ display: launched }) => { display = launched || null; });
  events.on('tab:created', ({ tabId, page }) => {
    if (!display) return;
    watch(page, display, (msg, fields) => log('info', `turnstile: ${msg}`, { tabId, ...fields }));
  });
}

async function watch(page, display, log) {
  const until = Date.now() + WATCH_MS;
  let clicks = 0;
  try {
    while (Date.now() < until && clicks < MAX_CLICKS && !page.isClosed()) {
      await page.waitForTimeout(TICK_MS);
      // The widget's iframe needs a moment to draw the checkbox.
      if (page.frames().length < 2) continue;
      const box = await widgetBox(page);
      if (!box) continue;
      const left = box.width > WIDGET_WIDTH ? box.x : box.x + (box.width - WIDGET_WIDTH) / 2;
      const target = {
        x: left + CHECKBOX_X + (Math.random() - 0.5) * 6,
        y: box.y + box.height / 2 + (Math.random() - 0.5) * 6,
      };
      if (await click(page, display, target)) {
        clicks++;
        log('clicked', { url: page.url(), clicks });
        // Give Cloudflare time to verify and reload before looking again.
        await page.waitForTimeout(5000);
      }
    }
  } catch {
    // The tab closed or navigated away mid-step; nothing left to do.
  }
}

// The widget's box in the page. Its iframe sits in a closed shadow root
// (whose frame Camoufox reports without a URL), so it is found through the
// element holding Turnstile's hidden response field, which is as wide as
// its container with the widget at the left.
async function widgetBox(page) {
  const box = await page.evaluate(() => {
    const input = document.querySelector('input[name="cf-turnstile-response"]');
    if (!input || input.value) return null;
    const host = input.parentElement;
    host.scrollIntoView({ block: 'center', inline: 'nearest' });
    const r = host.getBoundingClientRect();
    return { x: r.x, y: r.y, width: r.width, height: r.height };
  }).catch(() => null);
  return box && box.width >= WIDGET_WIDTH && box.height >= 50 ? box : null;
}

// Click a point given in page (CSS pixel) coordinates with the X11 pointer.
// Where the page sits on the screen depends on the window and its toolbars,
// so the pointer is first moved onto the page and the offset read back from
// the event the page receives. That also confirms the window under the
// pointer is this tab's; if it isn't, no click is made.
async function click(page, display, target) {
  const env = { ...process.env, DISPLAY: display };
  const xdo = (...args) => run('xdotool', args, { env });
  await page.bringToFront();
  await page.evaluate(() => {
    if (window.__turnstilePointer !== undefined) return;
    window.__turnstilePointer = null;
    document.addEventListener('mousemove', (e) => {
      window.__turnstilePointer = { x: e.clientX, y: e.clientY };
    }, true);
  });
  // A point on the page whatever the toolbar height: below the widget.
  const probe = { x: Math.round(target.x + 40), y: Math.round(target.y + 150) };
  await xdo('mousemove', String(probe.x), String(probe.y));
  await page.waitForTimeout(80);
  await xdo('mousemove', String(probe.x + 3), String(probe.y + 2));
  await page.waitForTimeout(150);
  const seen = await page.evaluate(() => window.__turnstilePointer);
  if (!seen) return false;
  const dx = probe.x + 3 - seen.x;
  const dy = probe.y + 2 - seen.y;
  const end = { x: target.x + dx, y: target.y + dy };
  // Approach in a few uneven steps, as a hand would.
  const start = { x: probe.x + 3, y: probe.y + 2 };
  for (const t of [0.35, 0.65, 0.85, 0.95, 1]) {
    const jitter = t < 1 ? (Math.random() - 0.5) * 10 : 0;
    const x = Math.round(start.x + (end.x - start.x) * t + jitter);
    const y = Math.round(start.y + (end.y - start.y) * t + jitter);
    await xdo('mousemove', String(x), String(y));
    await page.waitForTimeout(30 + Math.random() * 60);
  }
  await page.waitForTimeout(120 + Math.random() * 200);
  await xdo('click', '1');
  return true;
}
