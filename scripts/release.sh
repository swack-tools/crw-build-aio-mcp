#!/usr/bin/env bash
# Start a release: a signed tag v<version> on the pushed main, and a draft
# GitHub release that the Release workflow fills in and publishes.
# Usage: release.sh <version>   (e.g. 0.1.0)
source "$(dirname "$0")/lib.sh"

version="${1:?usage: release.sh <version, e.g. 0.1.0>}"
version="${version#v}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must look like 0.1.0"
tag="v$version"

cd "$ROOT"
[[ -z "$(git status --porcelain)" ]] || die "commit or stash your changes first"
git fetch --quiet origin main
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || die "HEAD is not origin/main; push main first"
! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "$tag already exists"

git tag -s "$tag" -m "crw-build-aio-mcp $version"
git verify-tag "$tag"
git push origin "$tag"
gh release create "$tag" --draft --verify-tag --title "crw-build-aio-mcp $version" \
  --notes "Building. The Release workflow publishes this once the images and the disk image are ready."
log "released $tag as a draft; watch it with: gh run watch \$(gh run list -w Release -L 1 --json databaseId -q '.[0].databaseId')"
