#!/usr/bin/env bash
# Register (or remove) the crw MCP server: bin/crw-mcp in proxy mode, pointed
# at this stack via CRW_API_URL.
#   claude → Claude Code (user scope) + Claude Desktop
#   codex  → Codex CLI + ChatGPT desktop (both read ~/.codex/config.toml)
#   all    → both
# Shows every command and config diff first, then asks before changing anything.
# Usage: install-mcp.sh <install|uninstall> <claude|codex|all> [--dry-run] [--yes]
source "$(dirname "$0")/lib.sh"

usage="usage: install-mcp.sh <install|uninstall> <claude|codex|all> [--dry-run] [--yes]"
action="${1:?$usage}"
target="${2:?$usage}"
shift 2
[[ "$action" == install || "$action" == uninstall ]] || die "$usage"
case "$target" in
  claude) targets=(claude) ;;
  codex) targets=(codex) ;;
  all) targets=(claude codex) ;;
  *) die "unknown target: $target (claude | codex | all)" ;;
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

bin="$BIN/crw-mcp"
url="$(crw_url)"
if [[ "$action" == install && ! -x "$bin" ]]; then
  die "missing $bin — run: $(hint build-mcp update)"
fi

# preview=1: print what would happen. preview=: do it.
preview=

run() {
  if [[ -n "$preview" ]]; then
    printf '  run:'; printf ' %q' "$@"; echo
  else
    "$@"
  fi
}

# Edit a JSON/TOML config through mcp_config.py: show the diff, or back up and replace.
edit_config() {
  local kind="$1" file="$2" tmp before
  if [[ "$action" == uninstall && ! -f "$file" ]]; then
    [[ -z "$preview" ]] || echo "  $file: not present, no change"
    return
  fi
  tmp="$(mktemp)"
  python3 -I "$ROOT/scripts/mcp_config.py" "$kind" "$action" "$file" "$tmp" "$bin" "$url"
  if [[ -f "$file" ]] && cmp -s "$file" "$tmp"; then
    [[ -z "$preview" ]] || echo "  $file: no change"
    rm -f "$tmp"
    return
  fi
  if [[ -n "$preview" ]]; then
    before="$file"
    [[ -f "$file" ]] || before=/dev/null
    # Relabel the temp-file headers (macOS diff has no --label).
    diff -u "$before" "$tmp" | sed -e "1s#^--- .*#--- $file#" -e "2s#^+++ .*#+++ $file (new)#" || true
    rm -f "$tmp"
    return
  fi
  mkdir -p "$(dirname "$file")"
  if [[ -f "$file" ]]; then
    cp -p "$file" "$file.bak-$(date +%Y%m%d-%H%M%S)"
    cat "$tmp" > "$file"
  else
    mv "$tmp" "$file"
  fi
  rm -f "$tmp"
  log "updated $file (backup alongside)"
}

# Claude Desktop saves its in-memory settings over its config file while it
# runs, which drops edits made underneath it, and only reads the file at
# launch. So it is quit before the edit and reopened after, even when the file
# already has the entry: the running app may not have loaded it.
reopen_claude=
close_claude_desktop() {
  pgrep -x Claude >/dev/null || return 0
  if [[ -n "$preview" ]]; then
    echo "  Claude Desktop is running: it will be quit before this edit and reopened after"
    return
  fi
  log "quitting Claude Desktop"
  osascript -e 'quit app id "com.anthropic.claudefordesktop"' >/dev/null || true
  for _ in $(seq 1 30); do
    if ! pgrep -x Claude >/dev/null; then
      reopen_claude=1
      return
    fi
    sleep 1
  done
  die "Claude Desktop did not quit; quit it yourself, then re-run"
}

target_claude() {
  log "Claude Code — user scope ($action)"
  if command -v claude >/dev/null; then
    if [[ -n "$preview" ]]; then
      run claude mcp remove -s user crw
    else
      claude mcp remove -s user crw >/dev/null 2>&1 || true
    fi
    if [[ "$action" == install ]]; then
      run claude mcp add -s user crw -e "CRW_API_URL=$url" -- "$bin"
    fi
  else
    warn "claude CLI not found; skipping Claude Code"
  fi

  log "Claude Desktop ($action)"
  close_claude_desktop
  edit_config claude-desktop "$HOME/Library/Application Support/Claude/claude_desktop_config.json"
  if [[ -n "$reopen_claude" ]]; then
    open -b com.anthropic.claudefordesktop
    log "reopened Claude Desktop"
  fi
}

target_codex() {
  log "Codex CLI + ChatGPT desktop ($action)"
  edit_config codex "$HOME/.codex/config.toml"
  if [[ -z "$preview" && "$action" == install ]] && command -v codex >/dev/null; then
    codex mcp get crw >/dev/null || die "codex does not see the crw server after install"
  fi
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
[[ " ${targets[*]} " != *" codex "* ]] || warn "restart ChatGPT desktop to pick up the change"
