#!/usr/bin/env bash
# Build the stack's images with docker buildx bake.
# Usage: build-images.sh <arm64|amd64|all> [--push | --push-by-digest <metadata.json>] [target...]
#   --push            push tagged images to $REGISTRY
#   --push-by-digest  push untagged and record each digest (CI: one runner per arch)
# Camoufox zips for each requested arch must already be in dist/ (build-camoufox.sh),
# unless CAMOUFOX_DIST names an image that holds them.
source "$(dirname "$0")/lib.sh"

usage="usage: build-images.sh <arm64|amd64|all> [--push | --push-by-digest <metadata.json>] [target...]"
case "${1:?$usage}" in
  all) arches=(arm64 amd64) ;;
  *) arches=("$(docker_arch "$1")") ;;
esac
shift

output=(--load)
case "${1:-}" in
  --push|--push-by-digest)
    [[ -n "${REGISTRY:-}" ]] || die "set REGISTRY (e.g. docker.io/you/) in .env before pushing"
    if [[ "$1" == --push ]]; then
      output=(--push)
      shift
    else
      export PUSH_BY_DIGEST=true
      output=(--metadata-file "${2:?$usage}")
      shift 2
    fi
    ;;
esac
targets=("$@")

platforms=()
for arch in "${arches[@]}"; do platforms+=("linux/$arch"); done
PLATFORMS="$(IFS=,; echo "${platforms[*]}")"

if [[ -z "${CAMOUFOX_DIST:-}" ]] && { ((${#targets[@]} == 0)) || [[ " ${targets[*]} " =~ " camofox " ]]; }; then
  for arch in "${arches[@]}"; do
    compgen -G "$DIST/camoufox-*-lin.$(camoufox_arch "$arch").zip" >/dev/null ||
      die "no Camoufox build for $arch in dist/ — run: scripts/build-camoufox.sh $arch"
  done
fi

for entry in "${SOURCES[@]}"; do
  name="${entry%%|*}"
  var="$(env_name "$name")"
  export "CTX_$var=$(src_dir "$name")" "SHA_$var=$(src_sha "$name")"
done

# shellcheck disable=SC1091
eval "$(. "$(src_dir camoufox)/browser/upstream.sh" && echo "CAMOUFOX_VERSION=$version CAMOUFOX_RELEASE=$release")"
SEARXNG_VERSION="$(sed -n 's/^DOCKER_TAG = "\(.*\)"/\1/p' "$(src_dir searxng)/searx/version_frozen.py")"
export PROJECT TAG REGISTRY="${REGISTRY:-}" PLATFORMS BUILD_DIR="$BUILD" DIST_DIR="$DIST" \
  CAMOUFOX_VERSION CAMOUFOX_RELEASE SEARXNG_VERSION

log "bake ${targets[*]:-default} for $PLATFORMS (${output[*]})"
docker buildx bake -f "$ROOT/docker-bake.hcl" "${output[@]}" ${targets[@]+"${targets[@]}"}
