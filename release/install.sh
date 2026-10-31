#!/usr/bin/env bash
# Install crw-build-aio-mcp from this disk image:
#   1. copy it to ~/Library/Application Support/crw-build-aio-mcp
#   2. link the crw-aio command into ~/.local/bin
#   3. pull the images from Docker Hub and start the stack
#   4. register the crw MCP server with Claude, Codex and Antigravity (shows the changes, asks first)
# Re-running it upgrades an install in place and keeps its .env.
# Usage: install.sh [--yes]   (--yes skips the MCP confirmation)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
dest="${CRW_AIO_HOME:-$HOME/Library/Application Support/crw-build-aio-mcp}"
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }

command -v docker >/dev/null || die "Docker is required: install OrbStack or Docker Desktop, start it, then re-run"
docker info >/dev/null 2>&1 || die "Docker is installed but not running: start it, then re-run"
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required (docker compose version)"
command -v python3 >/dev/null || die "python3 is required: run xcode-select --install, then re-run"

log "installing to $dest"
mkdir -p "$dest"
rsync -a --delete --exclude /.env "$here/payload/" "$dest/"

mkdir -p "$HOME/.local/bin"
ln -sf "$dest/bin/crw-aio" "$HOME/.local/bin/crw-aio"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) log "add ~/.local/bin to your PATH to run crw-aio by name (or use $dest/bin/crw-aio)" ;;
esac

log "pulling images (about 10 GB on first install) and starting the stack"
"$dest/bin/crw-aio" update
"$dest/bin/crw-aio" mcp install all "$@"
log "done. Manage it with: crw-aio help"
