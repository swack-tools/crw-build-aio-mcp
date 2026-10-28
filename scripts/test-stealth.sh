#!/usr/bin/env bash
# 1. /v1/capabilities must list all three stealth tiers.
# 2. A scrape pinned to each tier must succeed and be rendered by that tier,
#    and an unpinned (auto) scrape must use plain HTTP or a stealth tier.
# 3. Bot-check report (never fails): bot.sannysoft.com, deviceandbrowserinfo.com
#    and a Cloudflare challenge through auto and each JS tier, plus
#    status/challenge detection for any STEALTH_URL=url1,url2 pages.
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

def sannysoft(html):
    counts = {k: len(re.findall(rf'class="[^"]*\b{k}\b', html)) for k in ("passed", "warn", "failed")}
    # A fully rendered page has ~30 checks; fewer means its JS was still
    # filling the table when the DOM was read.
    if sum(counts.values()) < 20:
        return f"incomplete render ({sum(counts.values())} checks), no verdict"
    webdriver = re.search(r'id="webdriver-result"[^>]*>([^<]*)', html)
    return (f"passed={counts['passed']} warn={counts['warn']} failed={counts['failed']} "
            f"webdriver={webdriver.group(1).strip() if webdriver else '?'}")


def deviceandbrowserinfo(html):
    verdict = re.search(r'"isBot":\s*(true|false)', html)
    if not verdict:
        return "no verdict on the page"
    signals = sorted(set(re.findall(r'"(\w+)":\s*true', html)) - {"isBot"})
    return ("bot: " + ", ".join(signals)) if verdict.group(1) == "true" else "not a bot"


def cloudflare(html):
    if "You bypassed the Cloudflare challenge" in html:
        return "passed"
    return "challenge" if re.search(r"just a moment|verify you are human", html, re.I) else "unexpected page"


CHECKS = [
    ("bot.sannysoft.com", "https://bot.sannysoft.com", sannysoft),
    ("deviceandbrowserinfo.com", "https://deviceandbrowserinfo.com/are_you_a_bot", deviceandbrowserinfo),
    ("Cloudflare challenge", "https://www.scrapingcourse.com/cloudflare-challenge", cloudflare),
]

print("\nbot-check report (auto must not use a non-stealth browser; the rest is informational)")
print(f"  {'page':<34} {'tier':<18} result")
for name, page, check in CHECKS:
    for tier in [None] + JS_TIERS:
        # markdown too, as MCP clients ask: auto mode judges a rawHtml-only
        # response by different rules and can reject a page it would serve.
        data, _ = scrape(page, tier, ["rawHtml", "markdown"], waitFor=5000)
        doc = data.get("data") or {}
        html = doc.get("rawHtml") or ""
        label = tier
        if tier is None:
            got = (doc.get("metadata") or {}).get("renderedWith")
            label = f"auto -> {got}"
            # Plain HTTP runs no page JavaScript, so it has no fingerprint to give away.
            if data.get("success") and got not in TIERS + ["http"]:
                failed = True
                label += " (FAIL: not a stealth tier)"
        result = check(html) if data.get("success") and html else f"error: {data.get('error')}"
        print(f"  {name:<34} {label:<18} {result}")

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
