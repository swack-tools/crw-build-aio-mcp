#!/usr/bin/env bash
# Have an agent CLI call crw_scrape through the installed crw MCP server once
# per stealth tier, then once with only a URL on a Cloudflare challenge (as a
# plain "scrape this" request would), and check it reports all four as ok.
# Usage: test-agent.sh <claude|codex|antigravity>
source "$(dirname "$0")/lib.sh"

agent="${1:?usage: test-agent.sh <claude|codex|antigravity>}"
curl -fsS -m 10 "$(crw_url)/v1/capabilities" >/dev/null ||
  die "crw is not answering on $(crw_url) — run: just up-stealth"

read -r -d '' prompt <<'EOF' || true
Use the crw MCP server's crw_scrape tool to scrape https://example.com three times,
once with each value of its `renderer` argument: "impersonated-http", "chrome", "camoufox".
A call counts as ok only if it succeeds and the returned content contains "Example Domain".
Then call crw_scrape once more with only the `url` argument set, on
https://www.scrapingcourse.com/cloudflare-challenge. That call counts as ok only if it succeeds
and the returned content contains "You bypassed the Cloudflare challenge".
Do not use any other tool. Reply with only this JSON object and nothing else:
{"impersonated-http": "ok" or "fail", "chrome": "ok" or "fail", "camoufox": "ok" or "fail", "cloudflare": "ok" or "fail"}
EOF

out="$(mktemp)"
case "$agent" in
  claude)
    claude mcp get crw >/dev/null 2>&1 || die "crw is not installed in Claude Code — run: just install-claude"
    log "asking claude (this takes a minute)"
    claude -p "$prompt" --allowedTools mcp__crw__crw_scrape --output-format json --max-turns 10 </dev/null \
      | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("result",""))' > "$out"
    ;;
  codex)
    codex mcp get crw >/dev/null 2>&1 || die "crw is not installed in Codex — run: just install-codex"
    log "asking codex (this takes a minute)"
    codex exec --skip-git-repo-check --ephemeral -c approval_policy='"never"' \
      --output-last-message "$out" "$prompt" </dev/null >/dev/null
    ;;
  antigravity)
    agy mcp list 2>/dev/null | grep -q '^crw[[:space:]]' || die "crw is not installed in Antigravity — run: just install-antigravity"
    log "asking agy (this takes a minute)"
    # Headless agy denies MCP tools without an allow rule, and needs a sign-in; its error, printed below, says so.
    agy -p "$prompt" --print-timeout 300s </dev/null > "$out" 2>&1 || true
    ;;
  *) die "unknown agent: $agent (claude | codex | antigravity)" ;;
esac

python3 -I - "$out" "$agent" <<'PY'
import json, re, sys
reply = open(sys.argv[1]).read()
match = re.search(r"\{[^{}]*\}", reply)
try:
    result = json.loads(match.group(0)) if match else {}
except ValueError:
    result = {}
if not result:
    sys.exit(f"{sys.argv[2]} did not reply with the expected JSON:\n{reply}")
tiers = ["impersonated-http", "chrome", "camoufox", "cloudflare"]
for tier in tiers:
    print(f"  {'PASS' if result.get(tier) == 'ok' else 'FAIL'}  {tier}")
sys.exit(0 if all(result.get(t) == "ok" for t in tiers) else 1)
PY
