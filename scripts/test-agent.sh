#!/usr/bin/env bash
# Have an agent CLI call crw_scrape through the installed crw MCP server once
# per stealth tier, and check it reports all three as ok.
# Usage: test-agent.sh <claude|codex>
source "$(dirname "$0")/lib.sh"

agent="${1:?usage: test-agent.sh <claude|codex>}"
curl -fsS -m 10 "$(crw_url)/v1/capabilities" >/dev/null ||
  die "crw is not answering on $(crw_url) — run: just up-stealth"

read -r -d '' prompt <<'EOF' || true
Use the crw MCP server's crw_scrape tool to scrape https://example.com three times,
once with each value of its `renderer` argument: "impersonated-http", "chrome", "camoufox".
A call counts as ok only if it succeeds and the returned content contains "Example Domain".
Do not use any other tool. Reply with only this JSON object and nothing else:
{"impersonated-http": "ok" or "fail", "chrome": "ok" or "fail", "camoufox": "ok" or "fail"}
EOF

out="$(mktemp)"
case "$agent" in
  claude)
    claude mcp get crw >/dev/null 2>&1 || die "crw is not installed in Claude Code — run: just install-claude"
    log "asking claude (this takes a minute)"
    claude -p "$prompt" --allowedTools mcp__crw__crw_scrape --output-format json --max-turns 8 \
      | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("result",""))' > "$out"
    ;;
  codex)
    codex mcp get crw >/dev/null 2>&1 || die "crw is not installed in Codex — run: just install-codex"
    log "asking codex (this takes a minute)"
    codex exec --skip-git-repo-check --ephemeral -c approval_policy='"never"' \
      --output-last-message "$out" "$prompt" >/dev/null
    ;;
  *) die "unknown agent: $agent (claude | codex)" ;;
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
tiers = ["impersonated-http", "chrome", "camoufox"]
for tier in tiers:
    print(f"  {'PASS' if result.get(tier) == 'ok' else 'FAIL'}  {tier}")
sys.exit(0 if all(result.get(t) == "ok" for t in tiers) else 1)
PY
