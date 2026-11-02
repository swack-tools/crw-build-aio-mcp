#!/usr/bin/env bash
# Check the docs against the Google developer documentation style with Vale.
# Vale only exits non-zero on errors and the Google style is mostly warnings, so
# this fails on any warning or error. CLA.md is left out: it's a legal text.
# Usage: lint-docs.sh [file...]
source "$(dirname "$0")/lib.sh"

command -v vale >/dev/null || die "vale is required: https://vale.sh/docs/install"
cd "$ROOT"
[[ -d .github/styles/Google ]] || vale sync

if (($# == 0)); then
  files=()
  while IFS= read -r file; do files+=("$file"); done < <(git ls-files '*.md' release/README.txt | grep -vx CLA.md)
  set -- "${files[@]}"
fi

alerts="$(vale --minAlertLevel=warning --no-exit --output=line "$@")"
[[ -n "$alerts" ]] || { log "docs: no Vale warnings in $# files"; exit 0; }
printf '%s\n' "$alerts"
die "docs: fix the Vale warnings above"
