#!/usr/bin/env bash
# Start the stack (images must already be built) and wait until it's healthy.
source "$(dirname "$0")/lib.sh"

# One stack per directory: stop one this directory's compose file started under
# another project name. A v0.0.1 release install ran its first start as
# crw-config, which its own commands could not see, and that stack holds the port.
for old in $(docker ps -a --format '{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.project.config_files"}}' |
  awk -F'|' -v p="$PROJECT" -v a="$ROOT/docker-compose.yml" -v b="$ROOT/compose.yml" \
    '$1 != "" && $1 != p && ($2 == a || $2 == b) { print $1 }' | sort -u); do
  log "stopping $old, an earlier stack from $ROOT"
  PROJECT="$old" compose down --remove-orphans
done

"$ROOT/scripts/pick-port.sh"
load_env

# crw sends its own User-Agent; make it claim the Chrome that chrome-stealth
# actually runs (pulling the image first if this is a fresh install).
if [[ -z "${CRW_USER_AGENT:-}" ]]; then
  image="$(compose config --images | grep -m1 chrome-stealth || true)"
  major="$(docker run --rm --entrypoint google-chrome-stable "$image" --version \
    2>/dev/null | grep -oE '[0-9]+\.' | head -1 | tr -d .)" || true
  if [[ -n "$major" ]]; then
    export CRW_USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$major.0.0.0 Safari/537.36"
  else
    warn "could not read chrome-stealth's Chrome version; crw keeps its built-in User-Agent"
  fi
fi

# Browsers report a timezone, and one that doesn't fit the IP's location is a
# bot signal. Use this machine's (the image's own is America/Los_Angeles).
if [[ -z "${CRW_TZ:-}" ]]; then
  tz="$(readlink /etc/localtime 2>/dev/null | sed -n 's|.*zoneinfo/||p')"
  if [[ -n "$tz" ]]; then export CRW_TZ="$tz"; else warn "could not read this machine's timezone; the browsers use UTC"; fi
fi

log "starting $PROJECT on $(crw_url)"
compose up -d --wait --remove-orphans

for _ in $(seq 1 30); do
  if caps="$(curl -fsS -m 5 "$(crw_url)/v1/capabilities" 2>/dev/null)"; then
    log "renderers: $(python3 -c 'import json,sys; print(", ".join(json.load(sys.stdin)["renderers"]["available"]))' <<<"$caps")"
    exit 0
  fi
  sleep 2
done
die "crw did not answer on $(crw_url)/v1/capabilities — check: $(hint "logs crw" "logs crw")"
