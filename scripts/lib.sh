# Shared helpers, sourced by every script in scripts/.
# shellcheck shell=bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/src"
DIST="$ROOT/dist"
BIN="$ROOT/bin"
BUILD="$ROOT/build"
STAMPS="$ROOT/.stamps"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# .env is optional; variables already set in the environment win.
load_env() {
  [[ -f "$ROOT/.env" ]] || return 0
  local line key
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    key="${line%%=*}"
    [[ -n "${!key+x}" ]] || export "$line"
  done < "$ROOT/.env"
}
load_env

export PROJECT="${PROJECT:-crw-config}"
export TAG="${TAG:-local}"

# Set KEY=value in .env, replacing an existing line.
set_env_var() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp)"
  touch "$ROOT/.env"
  awk -v k="$key" -v v="$value" '
    index($0, k "=") == 1 { print k "=" v; done = 1; next } { print }
    END { if (!done) print k "=" v }' "$ROOT/.env" > "$tmp"
  cat "$tmp" > "$ROOT/.env"
  rm -f "$tmp"
  export "$key=$value"
}

# First run: copy .env.example and generate the secrets it leaves empty.
ensure_env() {
  [[ -f "$ROOT/.env" ]] || { cp "$ROOT/.env.example" "$ROOT/.env"; log "created .env"; }
  local key
  for key in BROWSERLESS_TOKEN SEARXNG_SECRET_KEY; do
    grep -q "^$key=." "$ROOT/.env" || set_env_var "$key" "$(openssl rand -hex 24)"
  done
  load_env
}

# name|git url — every upstream checks out its default branch unless
# <NAME>_REF is set (e.g. CAMOUFOX_REF=v152.0.4-beta.28).
SOURCES=(
  "crw|https://github.com/fastcrw/crw.git"
  "camoufox|https://github.com/daijro/camoufox.git"
  "camofox-browser|https://github.com/jo-inc/camofox-browser.git"
  "browserless|https://github.com/browserless/browserless.git"
  "searxng|https://github.com/searxng/searxng.git"
  "searxng-base|https://codeberg.org/searxng/base.git"
  "lightpanda|https://github.com/lightpanda-io/browser.git"
)

env_name() { echo "$1" | tr 'a-z-' 'A-Z_'; }

# Path of a source checkout; SRC_<NAME>=/path points at an existing clone.
src_dir() {
  local var
  var="SRC_$(env_name "$1")"
  echo "${!var:-$SRC/$1}"
}

src_ref() {
  local var
  var="$(env_name "$1")_REF"
  echo "${!var:-}"
}

src_sha() { git -C "$(src_dir "$1")" rev-parse HEAD; }

# Docker arch of this host: arm64 | amd64
host_arch() {
  case "$(uname -m)" in
    arm64|aarch64) echo arm64 ;;
    x86_64|amd64) echo amd64 ;;
    *) die "unsupported host arch $(uname -m)" ;;
  esac
}

# Normalise any arch spelling to Docker's (arm64 | amd64) or Camoufox's (arm64 | x86_64).
docker_arch() {
  case "$1" in
    arm64|aarch64) echo arm64 ;;
    amd64|x86_64|x86) echo amd64 ;;
    *) die "unknown arch: $1" ;;
  esac
}
camoufox_arch() {
  case "$(docker_arch "$1")" in
    arm64) echo arm64 ;;
    amd64) echo x86_64 ;;
  esac
}

# A release bundle (scripts/release-bundle.sh) has one generated compose.yml
# with pinned registry images; a checkout layers our override on upstream's files.
compose() {
  ensure_env
  if [[ -f "$ROOT/compose.yml" ]]; then
    docker compose -p "$PROJECT" --env-file "$ROOT/.env" -f "$ROOT/compose.yml" "$@"
    return
  fi
  docker compose -p "$PROJECT" --env-file "$ROOT/.env" \
    -f "$(src_dir crw)/docker-compose.yml" \
    -f "$(src_dir crw)/docker-compose.stealth.yml" \
    -f "$ROOT/compose.override.yml" \
    --profile stealth "$@"
}

crw_url() { echo "http://127.0.0.1:${CRW_HOST_PORT:-3000}"; }

# Name a command in messages: `just <recipe>` in a checkout, `crw-aio <cmd>` in
# a release bundle (which has a compose.yml and no Justfile).
hint() {
  if [[ -f "$ROOT/compose.yml" ]]; then echo "crw-aio $2"; else echo "just $1"; fi
}
