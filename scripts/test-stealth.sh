#!/usr/bin/env bash
# 1. /v1/capabilities must list all three stealth tiers.
# 2. A scrape pinned to each tier must succeed and be rendered by that tier.
# 3. Bot checks: bot.sannysoft.com, deviceandbrowserinfo.com,
#    bot-detector.rebrowser.net and two Cloudflare challenges. The default
#    scrape (no renderer, no waitFor, as an MCP client sends it) must pass
#    each one; the result for each pinned JS tier is reported alongside.
#    Pages given as STEALTH_URL=url1,url2 are reported per tier.
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
    # maxAge 0: fetch the page now rather than serve crw's cached copy.
    body = json.dumps({"url": page, "renderer": tier, "formats": formats, "maxAge": 0, **opts}).encode()
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

# Each check takes the rendered HTML and markdown and returns (passed, detail).
def sannysoft(html, md):
    counts = {k: len(re.findall(rf'class="[^"]*\b{k}\b', html)) for k in ("passed", "warn", "failed")}
    # A fully rendered page has ~30 checks; fewer means its JS was still
    # filling the table when the DOM was read.
    if sum(counts.values()) < 20:
        return False, f"incomplete render ({sum(counts.values())} checks)"
    # Firefox has no window.chrome, so Camoufox failing "Chrome (New)" is expected.
    firefox = re.search(r'id="user-agent-result"[^>]*>[^<]*Firefox/', html)
    expected = 1 if firefox and re.search(r'class="[^"]*\bfailed\b[^"]*"[^>]*id="chrome-result"', html) else 0
    note = " (Chrome row: expected for Firefox)" if expected else ""
    return counts["failed"] == expected, f"passed={counts['passed']} warn={counts['warn']} failed={counts['failed']}{note}"


def deviceandbrowserinfo(html, md):
    verdict = re.search(r'"isBot":\s*(true|false)', html)
    if not verdict:
        return False, "no verdict on the page"
    signals = sorted(set(re.findall(r'"(\w+)":\s*true', html)) - {"isBot"})
    return verdict.group(1) == "false", "not a bot" if verdict.group(1) == "false" else "bot: " + ", ".join(signals)


def rebrowser(html, md):
    flagged = re.findall(r"🔴\s*(\w+)", md)
    passed = len(re.findall("🟢", md))
    if not flagged and not passed:
        return False, "no results on the page"
    return not flagged, f"{passed} passed" + (f", flagged: {', '.join(flagged)}" if flagged else "")


def bypassed(name):
    def check(html, md):
        if f"You bypassed the {name} challenge" in html:
            return True, "passed"
        return False, "challenge" if re.search(r"just a moment|verify you are human", html, re.I) else "unexpected page"
    return check


CHECKS = [
    ("bot.sannysoft.com", "https://bot.sannysoft.com", sannysoft),
    ("deviceandbrowserinfo.com", "https://deviceandbrowserinfo.com/are_you_a_bot", deviceandbrowserinfo),
    ("bot-detector.rebrowser.net", "https://bot-detector.rebrowser.net/", rebrowser),
    ("Cloudflare challenge", "https://www.scrapingcourse.com/cloudflare-challenge", bypassed("Cloudflare")),
    ("Cloudflare antibot challenge", "https://www.scrapingcourse.com/antibot-challenge", bypassed("Antibot")),
]

print("\nbot checks (the default scrape must pass; pinned tiers are informational)")
print(f"  {'page':<30} {'tier':<18} result")
for name, page, check in CHECKS:
    for tier in [None] + JS_TIERS:
        # markdown too, as MCP clients ask; maxLength 0 so no result is cut off.
        data, secs = scrape(page, tier, ["rawHtml", "markdown"], maxLength=0)
        doc = data.get("data") or {}
        html, md = doc.get("rawHtml") or "", doc.get("markdown") or ""
        ok, result = check(html, md) if data.get("success") and html else (False, f"error: {data.get('error')}")
        label = tier
        if tier is None:
            label = f"default -> {(doc.get('metadata') or {}).get('renderedWith')}"
            failed |= not ok
        mark = ("PASS" if ok else "FAIL") if tier is None else ("ok  " if ok else "no  ")
        print(f"  {mark}  {name:<30} {label:<18} {result}  {secs:.1f}s")

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
