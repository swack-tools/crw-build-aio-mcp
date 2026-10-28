#!/usr/bin/env bash
# CI: tag every image of a run once its per-arch builds are pushed.
#   Built this run: join the amd64 + arm64 digests into <name>:src-<key>, then
#     sign that manifest with cosign (keyless, GitHub OIDC).
#   Every image: point each extra tag (nightly, 0.1.0, latest, ...) at <name>:src-<key>.
# Usage: ci-publish.sh <keys-json> <digests-dir> [tag...]
#   digests-dir holds a <name>-<arch> file with the pushed digest for each image
#   built this run; images without one were reused from an earlier run.
source "$(dirname "$0")/lib.sh"

keys="${1:?usage: ci-publish.sh <keys-json> <digests-dir> [tag...]}"
digests="${2:?usage: ci-publish.sh <keys-json> <digests-dir> [tag...]}"
shift 2
[[ -n "${REGISTRY:-}" ]] || die "REGISTRY is not set"

while read -r image key; do
  repo="${REGISTRY}${PROJECT}-$image"
  if [[ -f "$digests/$image-amd64" || -f "$digests/$image-arm64" ]]; then
    log "$image: joining amd64 + arm64 into src-$key"
    docker buildx imagetools create -t "$repo:src-$key" \
      "$repo@$(cat "$digests/$image-amd64")" "$repo@$(cat "$digests/$image-arm64")"
    digest="$(docker buildx imagetools inspect "$repo:src-$key" --format '{{json .Manifest}}' |
      python3 -I -c 'import json, sys; print(json.load(sys.stdin)["digest"])')"
    cosign sign --yes "$repo@$digest"
  else
    log "$image: unchanged, reusing src-$key"
  fi
  for tag in "$@"; do
    docker buildx imagetools create -t "$repo:$tag" "$repo:src-$key"
  done
done < <(python3 -I -c 'import json, sys; [print(k, v) for k, v in json.loads(sys.argv[1]).items()]' "$keys")
