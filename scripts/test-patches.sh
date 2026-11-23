#!/usr/bin/env bash
# Offline regression tests for our patches to crw: clone crw (CRW_REF to pin
# it), apply patches/crw/, and run the selected renderer tests against
# mock servers rather than live sites, so CI can run them on every change.
#
#   eBay (#10), revisit-walls.patch: Chrome reloads a page only its status
#     marks as a block, such as eBay's 403 "Something went wrong" to a fresh
#     profile, but not a 404 or 429 with the same markup.
#   Upstream destination policy: a refusal must stop renderer fallback.
#   eBay, wall-cookie-reset.patch: a host whose wall outlasts the reload has
#     its cookies dropped once, not again within the cooldown, as a burst when
#     the last drop was within the window, and never for a string that isn't a
#     URL; a reload's snapshot without a <body> is of a
#     page still being parsed; the browser is closed for a fresh profile once
#     per cooldown, and only when asked; the tracker keeps the main frame's
#     last document status, iframes aside; a reloaded page with no status seen
#     is reported as 200 unless its body is a wall.
#
# A test that is renamed or dropped fails the run instead of matching nothing.
# Usage: test-patches.sh
source "$(dirname "$0")/lib.sh"

RENDERER_FEATURES="cdp,camoufox,impersonated"
RENDERER_TESTS=(
  cdp::tests::revisitable_walls
  tests::a_policy_refusal_is_never_retried_by_another_tier
  cdp::tests::wall_reset_once_per_host_per_cooldown
  cdp::tests::reload_snapshot_without_a_body_is_still_parsing
  cdp::tests::browser_restart_once_per_cooldown
  cdp::tests::reloaded_page_keeps_its_own_status_or_is_the_page
  cdp::tests::tracker_keeps_the_main_frame_document_status
)

command -v cargo >/dev/null || die "cargo is not installed: see https://rustup.rs"
"$ROOT/scripts/fetch-sources.sh" crw
apply_patches crw

out="$(mktemp)"
trap 'rm -f "$out"' EXIT
# run_tests <crate> <test>... -- <cargo test args>: every named test has to run and pass.
run_tests() {
  local crate="$1" tests=() t
  shift
  while [[ "$1" != -- ]]; do tests+=("$1"); shift; done
  shift
  log "$crate: running ${#tests[@]} patch tests"
  (cd "$(src_dir crw)" && cargo test --locked -p "$crate" "$@" -- --exact "${tests[@]}") 2>&1 |
    tee "$out" || die "patch tests failed"
  for t in "${tests[@]}"; do
    grep -q "^test $t \.\.\. ok$" "$out" || die "$t did not run: was it renamed upstream or in patches/crw/? update the tests in $0"
  done
}
run_tests crw-renderer "${RENDERER_TESTS[@]}" -- --features "$RENDERER_FEATURES" --lib
log "all ${#RENDERER_TESTS[@]} patch tests passed"
