#!/usr/bin/env bash
# 1. /v1/capabilities must list all three stealth tiers.
# 2. A scrape pinned to each tier must succeed and be rendered by that tier,
#    and an unpinned (auto) scrape of a JS page must use a stealth tier.
# 3. Bot-check report (never fails): bot.sannysoft.com through each JS tier,
#    plus status/challenge detection for any STEALTH_URL=url1,url2 pages.
source "$(dirname "$0")/lib.sh"

url="$(crw_url)"
caps="$(curl -fsS -m 10 "$url/v1/capabilities")" || die "crw is not answering on $url — run: $(hint up-stealth up)"

python3 -I - "$url" "$caps" "${STEALTH_URL:-}" <<'PY'
import json, re, sys, time, urllib.error, urllib.request

base, caps, extra = sys.argv[1], json.loads(sys.argv[2]), sys.argv[3]
TIERS = ["impersonated-http", "chrome", "camoufox"]
JS_TIERS = ["chrome", "camoufox"]
failed = False


def scrape(page, tier, formats, **opts):
    body = json.dumps({"url": page, "renderer": tier, "formats": formats, **opts}).encode()
    req = urllib.request.Request(f"{base}/v1/scrape", body, {"content-type": "application/json"})
    start = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=240) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError as err:
        try:
            data = json.loads(err.read())
        except ValueError:
            data = {"success": False, "error": f"HTTP {err.code}"}
    except (urllib.error.URLError, TimeoutError) as err:
        data = {"success": False, "error": str(err)}
    return data, time.monotonic() - start


available = caps.get("renderers", {}).get("available", [])
print(f"renderers available: {', '.join(available)}")
for tier in TIERS:
    if tier not in available:
        print(f"  FAIL {tier} is not available")
        failed = True

print("\nscrape https://example.com, pinned to each tier")
for tier in TIERS:
    data, secs = scrape("https://example.com", tier, ["markdown"])
    doc = data.get("data") or {}
    got = (doc.get("metadata") or {}).get("renderedWith")
    ok = bool(data.get("success")) and got == tier and "Example Domain" in (doc.get("markdown") or "")
    failed |= not ok
    note = "" if ok else f"  error={data.get('error') or data.get('warning') or '-'}"
    print(f"  {'PASS' if ok else 'FAIL'}  {tier:<18} renderedWith={got}  {secs:5.1f}s{note}")

print("\nbot-check report (auto must use a stealth tier; the rest is informational)")
print(f"  {'page':<34} {'tier':<18} result")
for tier in [None] + JS_TIERS:
    data, _ = scrape("https://bot.sannysoft.com", tier, ["rawHtml"], waitFor=3000)
    doc = data.get("data") or {}
    html = doc.get("rawHtml") or ""
    if tier is None:
        got = (doc.get("metadata") or {}).get("renderedWith")
        tier = f"auto -> {got}"
        if got not in TIERS:
            failed = True
            tier += " (FAIL: not a stealth tier)"
    if not data.get("success") or not html:
        print(f"  {'bot.sannysoft.com':<34} {tier:<18} error: {data.get('error')}")
        continue
    counts = {k: len(re.findall(rf'class="[^"]*\b{k}\b', html)) for k in ("passed", "warn", "failed")}
    # A fully rendered page has ~30 checks. Fewer means its JS was still filling
    # the table when the DOM was read (crw's camoufox renderer ignores waitFor).
    if sum(counts.values()) < 20:
        print(f"  {'bot.sannysoft.com':<34} {tier:<18} incomplete render "
              f"({sum(counts.values())} checks), no verdict")
        continue
    webdriver = re.search(r'id="webdriver-result"[^>]*>([^<]*)', html)
    print(f"  {'bot.sannysoft.com':<34} {tier:<18} passed={counts['passed']} warn={counts['warn']} "
          f"failed={counts['failed']} webdriver={webdriver.group(1).strip() if webdriver else '?'}")

CHALLENGE = re.compile(r"just a moment|attention required|access denied|captcha|are you a robot|verify you are human", re.I)
for page in filter(None, extra.split(",")):
    for tier in TIERS:
        data, secs = scrape(page, tier, ["markdown"])
        doc = data.get("data") or {}
        meta = doc.get("metadata") or {}
        text = (meta.get("title") or "") + " " + (doc.get("markdown") or "")[:2000]
        verdict = "error" if not data.get("success") else ("challenge?" if CHALLENGE.search(text) else "ok")
        print(f"  {page[:34]:<34} {tier:<18} {verdict} status={meta.get('statusCode')} "
              f"chars={len(doc.get('markdown') or '')} {secs:.1f}s")

sys.exit(1 if failed else 0)
PY
