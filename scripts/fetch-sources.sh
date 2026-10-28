#!/usr/bin/env bash
# Clone each missing upstream into src/<name>. With --update, also fast-forward
# existing clones (and re-apply <NAME>_REF).
# Usage: fetch-sources.sh [--update] [name...]   (default: all)
source "$(dirname "$0")/lib.sh"

update=
if [[ "${1:-}" == "--update" ]]; then update=1; shift; fi
mkdir -p "$SRC"
wanted=("$@")
summary=()

for entry in "${SOURCES[@]}"; do
  name="${entry%%|*}"
  url="${entry#*|}"
  if ((${#wanted[@]})) && [[ ! " ${wanted[*]} " =~ " $name " ]]; then
    continue
  fi
  dir="$(src_dir "$name")"
  ref="$(src_ref "$name")"
  override="SRC_$(env_name "$name")"

  if [[ -n "${!override:-}" ]]; then
    [[ -d "$dir/.git" ]] || die "$override=$dir is not a git checkout"
    summary+=("$name|$(git -C "$dir" rev-parse --short HEAD)|local checkout, not updated")
    continue
  fi

  old="-"
  if [[ -d "$dir/.git" ]]; then
    old="$(git -C "$dir" rev-parse --short HEAD)"
    if [[ -z "$update" ]]; then
      summary+=("$name|$old|already cloned (just update to pull)")
      continue
    fi
    git -C "$dir" fetch --quiet --tags --force origin
  else
    log "cloning $name"
    git clone --quiet --filter=blob:none "$url" "$dir"
  fi

  if [[ -n "$ref" ]] && ! git -C "$dir" show-ref --verify --quiet "refs/remotes/origin/$ref"; then
    git -C "$dir" checkout --quiet --detach "$ref" || die "$name: unknown ref $ref"
  else
    branch="${ref:-$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD)}"
    branch="${branch#origin/}"
    git -C "$dir" checkout --quiet "$branch"
    git -C "$dir" merge --quiet --ff-only "origin/$branch" ||
      die "$name: local branch $branch has diverged from origin; reset src/$name or remove it"
  fi
  new="$(git -C "$dir" rev-parse --short HEAD)"
  summary+=("$name|$old -> $new|${ref:-default branch}")
done

printf '%s\n' "${summary[@]}" | column -t -s'|' >&2
