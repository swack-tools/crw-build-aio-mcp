#!/usr/bin/env bash
# Generate the build inputs that upstream Dockerfiles can't take as-is:
#   src/*                             — our patches/<name>/*.patch applied
#   build/camofox-browser.Dockerfile  — installs our Camoufox zip instead of a release download
#   src/searxng/searx/version_frozen.py — what upstream's `manage container.build` writes
# Each patch fails loudly if the upstream line it replaces moves.
source "$(dirname "$0")/lib.sh"

mkdir -p "$BUILD"

# Replace exactly one line matching `needle` in `src` with `repl`; write to `out`.
patch_line() {
  python3 -I - "$@" <<'PY'
import sys
src, out, needle, repl = sys.argv[1:5]
lines = open(src).read().split("\n")
hits = [i for i, l in enumerate(lines) if needle in l]
if len(hits) != 1:
    sys.exit(f"{src}: expected one line containing {needle!r}, found {len(hits)}; upstream changed, update scripts/prep-sources.sh")
lines[hits[0]] = repl
open(out, "w").write("\n".join(lines))
PY
}

for entry in "${SOURCES[@]}"; do
  apply_patches "${entry%%|*}"
done

log "camofox-browser: use dist/camoufox-*-lin.<arch>.zip"
patch_line "$(src_dir camofox-browser)/Dockerfile" "$BUILD/camofox-browser.Dockerfile.tmp" \
  'curl -fL -o /tmp/camoufox.zip' \
  '    && cp /camoufox-dist/camoufox-*-lin.${CAMOUFOX_ARCH}.zip /tmp/camoufox.zip \'
# The RUN that owns that line needs the dist/ zips mounted.
patch_line "$BUILD/camofox-browser.Dockerfile.tmp" "$BUILD/camofox-browser.Dockerfile" \
  'RUN case "${TARGETARCH}" in' \
  'RUN --mount=type=bind,from=camoufox,target=/camoufox-dist case "${TARGETARCH}" in \'
rm "$BUILD/camofox-browser.Dockerfile.tmp"

# docker-compose.yml started from crw's compose files and lists their blob ids.
for f in docker-compose.yml docker-compose.stealth.yml config/searxng/settings.yml; do
  blob="$(git -C "$(src_dir crw)" hash-object "$f" 2>/dev/null || echo gone)"
  grep -q "$f *$blob" "$ROOT/docker-compose.yml" ||
    warn "crw changed $f since docker-compose.yml was written: see git -C $(src_dir crw) log -p -- $f, then update its blob id in docker-compose.yml"
done

log "searxng: freeze version"
(cd "$(src_dir searxng)" && python3 -I searx/version.py freeze >/dev/null)
