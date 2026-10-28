#!/usr/bin/env bash
# Start the stack (images must already be built) and wait until it's healthy.
source "$(dirname "$0")/lib.sh"

"$ROOT/scripts/pick-port.sh"
load_env

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
