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
#   renderJs: false (#23), render-js-false-hop.patch: a plain-HTTP block gets
#     one more request through the impersonated-http client, whose answer wins
#     unless it is a block too, and no browser runs; a clean answer stays on
#     plain HTTP.
#   Skeleton wait, skeleton-wait-fast-ready.patch: CRW 0.41's wait for a
#     page's skeleton placeholders to fill is skipped with CHROME_FAST_READY,
#     or a caller's waitFor.
#   MCP data tools, mcp-data-tools-probe.patch: a proxy to an API whose
#     /v1/data/manifest is a 404 lists neither data tool and refuses a call
#     to one; any other answer, or none, keeps them listed.
#
# A test that is renamed or dropped fails the run instead of matching nothing.
# Usage: test-patches.sh
source "$(dirname "$0")/lib.sh"

RENDERER_FEATURES="cdp,camoufox,impersonated"
RENDERER_TESTS=(
  cdp::tests::revisitable_walls
  camoufox::tests::page_still_loading_is_read_again
  tests::forced_js_vendor_wall_falls_back_or_is_the_verdict
  tests::render_js_false_hops_to_impersonated_on_a_wall
  cdp::tests::skeleton_wait_skipped_with_fast_ready_or_a_wait_for
)
# The proxy-only build, as bin/crw-mcp is.
MCP_TESTS=(
  tests::handle_request_hides_the_data_tools_when_the_api_has_none
  tests::data_tools_available_hides_them_only_on_a_manifest_404
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
    grep -q "^test $t \.\.\. ok$" "$out" || die "$t did not run: was it renamed in patches/crw/? update the tests in $0"
  done
}
run_tests crw-renderer "${RENDERER_TESTS[@]}" -- --features "$RENDERER_FEATURES" --lib
run_tests crw-mcp "${MCP_TESTS[@]}" -- --no-default-features --bin crw-mcp
log "all $((${#RENDERER_TESTS[@]} + ${#MCP_TESTS[@]})) patch tests passed"
