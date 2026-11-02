#!/usr/bin/env bash
# Offline regression tests for our patches to crw: clone crw (CRW_REF to pin
# it), apply patches/crw/, and run the unit tests those patches add, against
# mock servers rather than live sites, so CI can run them on every change.
#
#   eBay (#10), revisit-walls.patch: Chrome reloads a page only its status
#     marks as a block, such as eBay's 403 "Something went wrong" to a fresh
#     profile, but not a 404 or 429 with the same markup.
#   eBay (#10), camoufox-wait-loading.patch: Camoufox reads a page again while
#     it is still eBay's empty shell, instead of returning it as a success.
#   Akamai, render-browser-first.patch: when both browsers get Akamai's wall,
#     the scrape fails as blocked without an HTTP request from this IP; other
#     vendors' walls still fall back to HTTP, and a real HTTP body wins.
#   Auto mode (#18), render-js-auto.patch: render_js_default takes true, false,
#     "auto", "" or whitespace (the last three mean auto, so compose can opt
#     in), and a vendor's wall served with 200 goes to the browser.
#
# A test that is renamed or dropped fails the run instead of matching nothing.
# Usage: test-patches.sh
source "$(dirname "$0")/lib.sh"

FEATURES="cdp,camoufox"
TESTS=(
  cdp::tests::revisitable_walls
  camoufox::tests::page_still_loading_is_read_again
  tests::forced_js_vendor_wall_falls_back_or_is_the_verdict
  tests::auto_vendor_wall_200_goes_to_browser
)
CORE_TESTS=(
  config::tests::render_js_default_accepts_auto
  config::tests::env_var_render_js_default_auto
)

command -v cargo >/dev/null || die "cargo is not installed: see https://rustup.rs"
"$ROOT/scripts/fetch-sources.sh" crw
apply_patches crw

log "crw-renderer: running ${#TESTS[@]} patch tests, crw-core: ${#CORE_TESTS[@]}"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
(cd "$(src_dir crw)" &&
  cargo test --locked -p crw-renderer --features "$FEATURES" --lib -- --exact "${TESTS[@]}" &&
  cargo test --locked -p crw-core --lib -- --exact "${CORE_TESTS[@]}") 2>&1 |
  tee "$out" || die "patch tests failed"

for t in "${TESTS[@]}" "${CORE_TESTS[@]}"; do
  grep -q "^test $t \.\.\. ok$" "$out" || die "$t did not run: was it renamed in patches/crw/? update TESTS in $0"
done
log "all $((${#TESTS[@]} + ${#CORE_TESTS[@]})) patch tests passed"
