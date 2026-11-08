#!/usr/bin/env bash
# Install (or remove) crw's agent skills: upstream's skills/ (what
# `npx skills add fastcrw/crw` installs), which teach an agent which verb a
# task needs (search, scrape, map, crawl, parse, extract, watch) and how to
# keep a scraped page out of its context. They are copied from the crw
# checkout, or from skills/ in a release bundle, into each agent's user-level
# skills folder:
#   claude      → ~/.claude/skills (Claude Code)
#   codex       → ~/.agents/skills (Codex CLI)
#   antigravity → ~/.gemini/config/skills (the app, the IDE and agy)
# Shows every copy or removal first, then asks before changing anything.
# Usage: install-skills.sh <install|uninstall> <claude|codex|antigravity|all> [--dry-run] [--yes]
source "$(dirname "$0")/lib.sh"

usage="usage: install-skills.sh <install|uninstall> <claude|codex|antigravity|all> [--dry-run] [--yes]"
action="${1:?$usage}"
target="${2:?$usage}"
shift 2
[[ "$action" == install || "$action" == uninstall ]] || die "$usage"
case "$target" in
  claude) targets=(claude) ;;
  codex) targets=(codex) ;;
  antigravity) targets=(antigravity) ;;
  all) targets=(claude codex antigravity) ;;
  *) die "unknown target: $target (claude | codex | antigravity | all)" ;;
esac

dry_run= yes=
for flag in "$@"; do
  case "$flag" in
    --dry-run|dry-run) dry_run=1 ;;
    --yes|-y) yes=1 ;;
    *) die "unknown flag: $flag ($usage)" ;;
  esac
done
[[ -z "${DRY_RUN:-}" ]] || dry_run=1

# The hub skill, the verb ladder it points at, the research one, and the two
# that keep pages out of an agent's context. Upstream's other two, crw-migrate
# and crw-self-host, are about moving to crw or running it, not using this stack.
SKILLS=(crw crw-search crw-scrape crw-map crw-crawl crw-parse crw-extract crw-watch
  crw-research crw-dynamic-search crw-best-practices crw-browser-act)
# Ours come from agent-skills/ in a checkout; a release bundle ships them in
# skills/ beside upstream's.
ours="$ROOT/agent-skills"

# A release bundle ships skills/; a checkout reads upstream's.
src="$ROOT/skills"
[[ -d "$src" ]] || src="$(src_dir crw)/skills"
if [[ "$action" == install ]]; then
  for s in "${SKILLS[@]}"; do
    [[ -f "$ours/$s/SKILL.md" || -f "$src/$s/SKILL.md" ]] || die "missing $src/$s/SKILL.md — run: $(hint fetch update)"
  done
fi

# preview=1: print what would happen. preview=: do it.
preview=

# Copy, or remove, each skill in one agent's folder. Only a SKILL.md carrying
# the skill's name is removed, and its folder only when that leaves it empty,
# so a skill of the user's own under the same name stays.
skills_for() {
  local dest="$1" s from to
  for s in "${SKILLS[@]}"; do
    from="$src/$s/SKILL.md"
    [[ ! -f "$ours/$s/SKILL.md" ]] || from="$ours/$s/SKILL.md"
    to="$dest/$s/SKILL.md"
    if [[ "$action" == install ]]; then
      if [[ -f "$to" ]] && cmp -s "$from" "$to"; then
        [[ -z "$preview" ]] || echo "  $to: up to date"
      elif [[ -n "$preview" ]]; then
        echo "  copy $from -> $to"
      else
        mkdir -p "$dest/$s"
        cp "$from" "$to"
      fi
    elif [[ ! -f "$to" ]] || ! grep -q "^name: $s\$" "$to"; then
      [[ -z "$preview" ]] || echo "  $to: not present or not crw's, no change"
    elif [[ -n "$preview" ]]; then
      echo "  remove $to"
    else
      rm -f "$to"
      rmdir "$dest/$s" 2>/dev/null || true
    fi
  done
  [[ -n "$preview" ]] || log "$action done in $dest"
}

target_claude() {
  log "Claude Code — user skills ($action)"
  skills_for "$HOME/.claude/skills"
}

target_codex() {
  log "Codex CLI — user skills ($action)"
  skills_for "$HOME/.agents/skills"
}

target_antigravity() {
  log "Antigravity — global skills ($action)"
  # Without Antigravity, that folder would be a stray one.
  if ! antigravity_present; then
    [[ -z "$preview" ]] || warn "Antigravity not found; skipping it"
    return 0
  fi
  skills_for "$HOME/.gemini/config/skills"
}

each_target() { for t in "${targets[@]}"; do "target_$t"; done; }

preview=1
each_target

if [[ -n "$dry_run" ]]; then
  log "dry run: nothing was changed"
  exit 0
fi

if [[ -z "$yes" ]]; then
  [[ -t 0 ]] || die "no terminal to confirm on; re-run with --yes"
  echo
  read -r -p "Apply these changes to ${targets[*]}? [y/N] " answer
  [[ "$answer" =~ ^[Yy] ]] || die "aborted; nothing was changed"
fi

preview=
each_target
log "done"
