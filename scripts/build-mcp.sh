#!/usr/bin/env bash
# Compile the native crw-mcp proxy binary from the crw checkout with
# patches/crw/ applied, as the images have them (mcp-data-tools-probe.patch is
# the one it needs). The binary lands in the checkout's target/release/; the
# Justfile's build-mcp recipe moves it into bin/.
# Usage: build-mcp.sh
source "$(dirname "$0")/lib.sh"

command -v cargo >/dev/null || die "cargo is not installed: see https://rustup.rs"
"$ROOT/scripts/fetch-sources.sh" --quiet crw
apply_patches crw
(cd "$(src_dir crw)" && cargo build --quiet --release --locked -p crw-mcp --no-default-features)
