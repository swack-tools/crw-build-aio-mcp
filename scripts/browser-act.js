// Drive the stack's stealth Chrome through a page: open a URL, fill fields,
// tick boxes, click buttons, wait, and print what the page says. Runs inside
// the chrome-stealth container (Node 22 has fetch and WebSocket built in)
// against Chrome's own DevTools port, so the site sees the same browser crw
// renders in. scripts/browser-act.sh copies it in and runs it.
//
// Usage: browser-act.js '<steps JSON>'
// Steps, in order:
//   {"goto": "https://..."}                   open the page and wait for it
//   {"wait": "selector"} | {"wait": ms}       wait for an element, or sleep
//   {"type": "selector", "text": "ABC123"}    click the field and type into it
//   {"check": "selector"}                     tick a checkbox (clicks its label)
//   {"click": "selector"}                     click an element
//   {"click": {"text": "regex"}}              click a button or link by its text
//   {"press": "Enter"}                        press a key
//   {"until": "regex"}                        wait up to 20 s for the page text (fails if it never matches)
//   {"read": "selector"} | {"read": ""}       print that element's text, or the page's
// Clicks and keys are real input events, as a person's would be. Exits 1 with
// the page text when a step's element never appears or an until never matches,
// and exits 1 if Chrome goes away mid-run.
const steps = JSON.parse(process.argv[2] || '[]');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const jitter = (a, b) => a + Math.random() * (b - a);
const KEYS = { Enter: 13, Tab: 9, Escape: 27, Space: 32 };

(async () => {
  const ver = await (await fetch('http://127.0.0.1:9223/json/version')).json();
  const ws = new WebSocket(ver.webSocketDebuggerUrl);
  await new Promise((ok, bad) => { ws.onopen = ok; ws.onerror = bad; });
  let id = 0;
  const pending = {};
  let closed = false;
  ws.onmessage = e => {
    const m = JSON.parse(e.data);
    if (m.id && pending[m.id]) { pending[m.id].ok(m); delete pending[m.id]; }
  };
  // Chrome can go away mid-run (the stack restarts it for a fresh profile):
  // fail every waiting command instead of leaving it pending forever.
  ws.onclose = () => {
    closed = true;
    for (const i of Object.keys(pending)) { pending[i].bad(new Error('DevTools connection closed')); delete pending[i]; }
  };
  const send = (method, params = {}, sessionId) => new Promise((ok, bad) => {
    if (closed) return bad(new Error('DevTools connection closed'));
    const i = ++id;
    pending[i] = { ok, bad };
    ws.send(JSON.stringify({ id: i, method, params, sessionId }));
  });

  // A window of its own, as Chrome on a display needs for a sized target.
  const { result: { targetId } } = await send('Target.createTarget',
    { url: 'about:blank', newWindow: true, width: 1280, height: 1000 });
  const { result: { sessionId: s } } = await send('Target.attachToTarget', { targetId, flatten: true });
  const ev = async expr => (await send('Runtime.evaluate',
    { expression: expr, returnByValue: true, awaitPromise: true }, s)).result?.result?.value;
  const pageText = () => ev("(document.querySelector('main') || document.body)?.innerText || ''");

  const find = sel => typeof sel === 'object' && sel.text
    ? `[...document.querySelectorAll('button,a,[role=button],input[type=submit],input[type=button]')]
         .find(e => new RegExp(${JSON.stringify(sel.text)}, 'i').test(e.innerText || e.value || ''))`
    : `document.querySelector(${JSON.stringify(sel)})`;
  // Where to click: the element's centre, or for a checkbox its label's left edge.
  const point = sel => ev(`(() => {
    let e = ${find(sel)};
    if (!e) return null;
    const box = e.type === 'checkbox';
    if (box) { const l = (e.id && document.querySelector('label[for="' + e.id + '"]')) || e.closest('label'); if (l) e = l; }
    e.scrollIntoView({ block: 'center' });
    const r = e.getBoundingClientRect();
    return { x: r.x + (box ? Math.min(12, r.width / 2) : r.width / 2), y: r.y + r.height / 2 };
  })()`);
  const click = async p => {
    for (const type of ['mouseMoved', 'mousePressed', 'mouseReleased']) {
      await send('Input.dispatchMouseEvent', { type, x: p.x, y: p.y, button: 'left', clickCount: 1 }, s);
      await sleep(jitter(80, 200));
    }
  };
  const key = async name => {
    const code = KEYS[name] || name.toUpperCase().charCodeAt(0);
    for (const type of ['keyDown', 'keyUp'])
      await send('Input.dispatchKeyEvent', { type, key: name, code: name, windowsVirtualKeyCode: code,
        ...(type === 'keyDown' && name === 'Enter' ? { text: '\r' } : {}) }, s);
  };
  const waitFor = async sel => {
    for (let i = 0; i < 40; i++) { if (await ev(`!!(${find(sel)})`)) return; await sleep(500); }
    const err = new Error('not found: ' + JSON.stringify(sel));
    err.page = await pageText();
    throw err;
  };

  try {
    for (const st of steps) {
      if (st.goto) {
        await send('Page.navigate', { url: st.goto }, s);
        for (let i = 0; i < 60 && (await ev('document.readyState')) !== 'complete'; i++) await sleep(500);
        await sleep(1500);
      } else if (st.wait !== undefined) {
        typeof st.wait === 'number' ? await sleep(st.wait) : await waitFor(st.wait);
      } else if (st.type) {
        await waitFor(st.type);
        await click(await point(st.type));
        await sleep(300);
        // insertText rather than key events: a React or Vue form only takes
        // input events, and keys alone fill the box without the app seeing it.
        for (const ch of st.text) { await send('Input.insertText', { text: ch }, s); await sleep(jitter(90, 200)); }
        await key('Tab');
        await sleep(400);
      } else if (st.check) {
        await waitFor(st.check);
        if (!(await ev(`${find(st.check)}.checked`))) await click(await point(st.check));
        await sleep(500);
      } else if (st.click) {
        await waitFor(st.click);
        await click(await point(st.click));
        await sleep(800);
      } else if (st.press) {
        await key(st.press);
        await sleep(800);
      } else if (st.until) {
        let matched = false;
        for (let i = 0; i < 40 && !matched; i++) {
          matched = await ev(`new RegExp(${JSON.stringify(st.until)}, 'i').test(document.body.innerText)`);
          if (!matched) await sleep(500);
        }
        if (!matched) {
          const err = new Error('page text never matched: ' + st.until);
          err.page = await pageText();
          throw err;
        }
      } else if (st.read !== undefined) {
        console.log(st.read ? await ev(`(${find(st.read)})?.innerText`) : await pageText());
      }
    }
    console.error('url: ' + await ev('location.href'));
  } finally {
    if (!closed) await send('Target.closeTarget', { targetId }).catch(() => {});
    ws.close();
  }
})().catch(e => {
  console.error('ERR ' + (e.message || e));
  if (e.page) console.log(e.page);
  process.exit(1);
});
