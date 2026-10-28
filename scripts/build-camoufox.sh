#!/usr/bin/env bash
# Build the Camoufox browser for Linux from src/camoufox → dist/camoufox-*-lin.<arch>.zip
# Usage: build-camoufox.sh [arm64|x86_64]   (default: host arch)
#
# Uses upstream's own builder image (browser/Dockerfile) on linux/amd64, the
# host upstream tests and cross-compiles from. Set CAMOUFOX_BUILDER_PLATFORM to
# try another. A cold build takes hours under emulation; toolchains and ccache
# persist in a named volume so later builds are incremental.
source "$(dirname "$0")/lib.sh"

arch="$(camoufox_arch "${1:-$(host_arch)}")"
src="$(src_dir camoufox)"
[[ -d "$src/browser" ]] || die "missing $src — run: just fetch"
sha="$(src_sha camoufox)"
stamp="$STAMPS/camoufox-$arch"
mkdir -p "$DIST" "$STAMPS"

zip_for_arch() { compgen -G "$DIST/camoufox-*-lin.$arch.zip" | head -1; }

exit_if_up_to_date() {
  if [[ -f "$stamp" && "$(cat "$stamp")" == "$sha" && -n "$(zip_for_arch)" ]]; then
    log "camoufox $arch is up to date ($(basename "$(zip_for_arch)"))"
    exit 0
  fi
}

[[ -n "${FORCE:-}" ]] || exit_if_up_to_date

# shellcheck disable=SC1091
version="$(. "$src/browser/upstream.sh" && echo "$version")"
platform="${CAMOUFOX_BUILDER_PLATFORM:-linux/amd64}"
# Upstream's Dockerfile says `FROM ubuntu:latest`; pin what that resolves to.
# 24.04 matches upstream's release CI, and 26.04's tar can't extract the
# Firefox source under Rosetta amd64 emulation ("Cannot open: Function not implemented").
base="${CAMOUFOX_BUILDER_BASE:-ubuntu:24.04}"
image="$PROJECT/camoufox-builder:${sha:0:12}"
volume="$PROJECT-camoufox-mozbuild-$version-${platform//\//-}"
# The compile runs detached in a container named per arch, so it outlives this
# shell: Ctrl-C or a closed terminal leaves it running, and the next run
# re-attaches to it instead of starting a second compile.
name="$PROJECT-camoufox-$arch"

if [[ "$(docker inspect -f '{{.State.Running}}' "$name" 2>/dev/null)" == true ]]; then
  [[ "$(docker inspect -f '{{.Config.Image}}' "$name")" == "$image" ]] ||
    die "$name is compiling another camoufox revision; stop it first: docker stop $name"
  log "re-attaching to the camoufox $arch compile already running ($name)"
  tail=20
else
  docker rm -f "$name" >/dev/null 2>&1 || true
  log "building camoufox builder image $image ($platform, FROM $base)"
  docker buildx build --load --platform "$platform" \
    --build-context "ubuntu:latest=docker-image://$base" \
    -t "$image" "$src/browser"

  log "compiling camoufox $version for linux/$arch in container $name (volume $volume)"
  rm -f "$DIST"/camoufox-*-lin."$arch".zip
  docker run -d --rm --name "$name" --platform "$platform" \
    -v "$DIST:/app/dist" \
    -v "$volume:/root/.mozbuild" \
    -e CCACHE_DIR=/root/.mozbuild/ccache \
    -e CARGO_BUILD_JOBS -e MOZ_PARALLEL_BUILD -e CAMOUFOX_UBO \
    "$image" --target linux --arch "$arch" >/dev/null
  tail=all
fi

trap 'echo; log "detached; the compile keeps running in $name (rerun to re-attach, or: docker stop $name)"; exit 130' INT
status="$(mktemp)"
docker wait "$name" > "$status" & # started first: --rm removes the container on exit
waiter=$!
docker logs -f --tail "$tail" "$name" || true
wait "$waiter" || true
code="$(cat "$status")"
rm -f "$status"
[[ "$code" == 0 ]] || die "camoufox compile failed (exit ${code:-unknown}); see the log above"

zip="$(zip_for_arch)"
[[ -n "$zip" ]] || die "build finished but no dist/camoufox-*-lin.$arch.zip was produced"
echo "$sha" > "$stamp"
log "built $(basename "$zip")"
