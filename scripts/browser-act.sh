#!/usr/bin/env bash
# Fill in and submit a page in the stack's stealth Chrome, the same browser crw
# renders in, and print what the page says: browser-act.js does the steps,
# inside the chrome-stealth container.
# Usage: browser-act.sh '<steps JSON>'   (the steps are listed in browser-act.js)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

# k8s is the estate deployment. Set CRW_EXEC=docker for a local Docker stack.
# The k8s path sends browser-act.js over stdin because kubectl exec cannot copy
# a host file into the pod; node - still receives the steps as its first arg.
case "${CRW_EXEC:-k8s}" in
  k8s)
    steps="${1:?usage: browser-act.sh '<steps JSON>'}"
    # ssh concatenates command arguments before handing them to the remote
    # shell, so quote the JSON explicitly rather than exposing its contents.
    quoted_steps="$(printf '%q' "$steps")"
    exec ssh winrarhost1 "sudo k3s kubectl -n crw exec -i deploy/crw -c chrome-stealth -- node - $quoted_steps" < "$here/browser-act.js"
    ;;
  docker)
    container="$(docker ps --filter 'name=chrome-stealth' --format '{{.Names}}' | head -1)"
    [[ -n "$container" ]] || { echo "chrome-stealth is not running; start the stack first" >&2; exit 1; }
    docker cp "$here/browser-act.js" "$container:/tmp/browser-act.js" >/dev/null
    exec docker exec "$container" node /tmp/browser-act.js "${1:?usage: browser-act.sh '<steps JSON>'}"
    ;;
  *)
    echo "unsupported CRW_EXEC=${CRW_EXEC}; expected k8s or docker" >&2
    exit 2
    ;;
esac
