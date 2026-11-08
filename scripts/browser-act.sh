#!/usr/bin/env bash
# Fill in and submit a page in the stack's stealth Chrome, the same browser crw
# renders in, and print what the page says: browser-act.js does the steps,
# inside the chrome-stealth container.
# Usage: browser-act.sh '<steps JSON>'   (the steps are listed in browser-act.js)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
container="$(docker ps --filter 'name=chrome-stealth' --format '{{.Names}}' | head -1)"
[[ -n "$container" ]] || { echo "chrome-stealth is not running; start the stack first" >&2; exit 1; }
docker cp "$here/browser-act.js" "$container:/tmp/browser-act.js" >/dev/null
exec docker exec "$container" node /tmp/browser-act.js "${1:?usage: browser-act.sh '<steps JSON>'}"
