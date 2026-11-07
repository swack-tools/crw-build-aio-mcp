#!/usr/bin/env bash
# Build the stack's images with docker buildx bake.
# Usage: build-images.sh <arm64|amd64|all> [--push | --push-by-digest <metadata.json>] [target...]
#   --push            push tagged images to $REGISTRY
#   --push-by-digest  push untagged and record each digest (CI: one runner per arch)
# Camoufox zips for each requested arch must already be in ~/.crw/dist (build-camoufox.sh),
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
      die "no Camoufox build for $arch in $DIST — run: scripts/build-camoufox.sh $arch"
  done
fi

# The clones and zips are outside this folder, and bake won't read there unless told to.
allow=("--allow=fs.read=$DIST")
for entry in "${SOURCES[@]}"; do
  name="${entry%%|*}"
  var="$(env_name "$name")"
  export "CTX_$var=$(src_dir "$name")" "SHA_$var=$(src_sha "$name")"
  allow+=("--allow=fs.read=$(src_dir "$name")")
done

# shellcheck disable=SC1091
eval "$(. "$(src_dir camoufox)/browser/upstream.sh" && echo "CAMOUFOX_VERSION=$version CAMOUFOX_RELEASE=$release")"
SEARXNG_VERSION="$(sed -n 's/^DOCKER_TAG = "\(.*\)"/\1/p' "$(src_dir searxng)/searx/version_frozen.py")"
# chrome-stealth installs the Chrome stable Google's package index names right
# now, by exact version, so a rebuild picks up a new release instead of the
# cached layer (as ci-plan.sh keys the image). CHROME_VERSION= leaves it to apt.
# Looked up only when chrome-stealth is among the targets, so an index outage
# cannot fail a build of the others.
if [[ -z "${CHROME_VERSION+x}" ]] && { ((${#targets[@]} == 0)) || [[ " ${targets[*]} " =~ " chrome-stealth " ]]; }; then
  CHROME_VERSION="$(curl -fsSL -m 30 "https://dl.google.com/linux/chrome/deb/dists/stable/main/binary-${arches[0]}/Packages" |
    awk '/^Package: google-chrome-stable$/ {p=1} p && /^Version: / {print $2; exit}')" ||
    die "could not read Chrome's package index; set CHROME_VERSION= to install whatever apt has"
  log "Chrome stable for ${arches[0]}: $CHROME_VERSION"
fi
export PROJECT TAG REGISTRY="${REGISTRY:-}" BUILD_CACHE="${BUILD_CACHE:-}" REFRESH="${REFRESH:-}" PLATFORMS BUILD_DIR="$BUILD" DIST_DIR="$DIST" \
  CAMOUFOX_VERSION CAMOUFOX_RELEASE SEARXNG_VERSION CHROME_VERSION="${CHROME_VERSION-}"

log "bake ${targets[*]:-default} for $PLATFORMS (${output[*]})"
docker buildx bake "${allow[@]}" -f "$ROOT/docker-bake.hcl" "${output[@]}" ${targets[@]+"${targets[@]}"}
