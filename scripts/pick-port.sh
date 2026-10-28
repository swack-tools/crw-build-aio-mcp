#!/usr/bin/env bash
# Make sure CRW_HOST_PORT is free (or already ours) before `compose up`.
# Offers the next free port when it's taken and saves the choice to .env.
source "$(dirname "$0")/lib.sh"
ensure_env

port="${CRW_HOST_PORT:-3000}"

listener() { lsof -nP -iTCP:"$1" -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $1" pid "$2}'; }

ours() {
  docker ps --filter "label=com.docker.compose.project=$PROJECT" \
    --filter "label=com.docker.compose.service=crw" --format '{{.Ports}}' |
    grep -q ":$1->"
}

free() { [[ -z "$(listener "$1")" ]]; }

if free "$port" || ours "$port"; then
  set_env_var CRW_HOST_PORT "$port"
  exit 0
fi

next=$((port + 1))
until free "$next"; do next=$((next + 1)); done

[[ -t 0 ]] || die "port $port is in use ($(listener "$port")); set CRW_HOST_PORT in .env (e.g. $next)"

while true; do
  read -r -p "Port $port is in use ($(listener "$port")). Use $next? [Y/n/<port>] " answer
  case "${answer:-y}" in
    [Yy]*) break ;;
    [Nn]*) die "aborted; set CRW_HOST_PORT in .env" ;;
    *[!0-9]*) echo "enter y, n or a port number" ;;
    *)
      if free "$answer"; then next="$answer"; break; fi
      echo "port $answer is in use too"
      ;;
  esac
done

set_env_var CRW_HOST_PORT "$next"
log "crw will listen on 127.0.0.1:$next (saved to .env)"
