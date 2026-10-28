# crw-config — CRW with all three stealth tiers (stealth Chrome via --profile stealth,
# impersonated-http, Camoufox), every app image built from upstream source.

set shell := ["bash", "-euo", "pipefail", "-c"]

host_arch := if arch() == "aarch64" { "arm64" } else { "amd64" }

# List recipes
default:
    @just --list --unsorted

# ── sources ──────────────────────────────────────────────────────────────

# Clone any missing upstream into src/
fetch *names:
    scripts/fetch-sources.sh {{ names }}

# Pull every upstream (fast-forward) and rebuild what changed
update: && build
    scripts/fetch-sources.sh --update

# ── build ────────────────────────────────────────────────────────────────

# Build every image for this machine's arch
build: (_build host_arch)

# Build every image for linux/arm64
build-arm64: (_build "arm64")

# Build every image for linux/amd64
build-x86: (_build "amd64")

# Build both arches as multi-arch images (Camoufox is compiled twice: hours)
build-all: fetch
    scripts/prep-sources.sh
    scripts/build-camoufox.sh arm64
    scripts/build-camoufox.sh x86_64
    scripts/build-images.sh all

# build-all, then push to $REGISTRY (set it in .env, e.g. docker.io/you/)
push: build-all
    scripts/build-images.sh all --push

# Compile just the Camoufox browser zip into dist/ (FORCE=1 to rebuild)
build-camoufox arch=host_arch:
    scripts/build-camoufox.sh {{ arch }}

# Build the native crw-mcp proxy binary into bin/
build-mcp:
    @scripts/fetch-sources.sh crw 2>/dev/null
    @cd src/crw && cargo build --quiet --release --locked -p crw-mcp --no-default-features
    @mkdir -p bin && cp src/crw/target/release/crw-mcp bin/crw-mcp

[private]
_build arch: fetch
    scripts/prep-sources.sh
    scripts/build-camoufox.sh {{ arch }}
    scripts/build-images.sh {{ arch }}

# ── run ──────────────────────────────────────────────────────────────────

# Build (cached) and start the stealth stack, then print the live renderers
up-stealth: build
    scripts/up.sh

alias run-stealth := up-stealth

# Stop the stack
down:
    source scripts/lib.sh && compose down

# Show service status
ps:
    source scripts/lib.sh && compose ps

# Follow logs (all services, or the ones named)
logs *services:
    source scripts/lib.sh && compose logs -f --tail=100 {{ services }}

# Print /v1/capabilities
caps:
    source scripts/lib.sh && curl -fsS "$(crw_url)/v1/capabilities" | python3 -m json.tool

# ── MCP ──────────────────────────────────────────────────────────────────

# Install the crw MCP server into Claude and Codex (asks first)  [--dry-run] [--yes]
install *flags: build-mcp
    @scripts/install-mcp.sh install all {{ flags }}

# Install into Claude Code + Claude Desktop (asks first)  [--dry-run] [--yes]
install-claude *flags: build-mcp
    @scripts/install-mcp.sh install claude {{ flags }}

# Install into Codex CLI + ChatGPT desktop (asks first)  [--dry-run] [--yes]
install-codex *flags: build-mcp
    @scripts/install-mcp.sh install codex {{ flags }}

# Remove the crw MCP server from Claude and Codex (asks first)  [--dry-run] [--yes]
uninstall *flags:
    @scripts/install-mcp.sh uninstall all {{ flags }}

# Remove from Claude Code + Claude Desktop (asks first)  [--dry-run] [--yes]
uninstall-claude *flags:
    @scripts/install-mcp.sh uninstall claude {{ flags }}

# Remove from Codex CLI + ChatGPT desktop (asks first)  [--dry-run] [--yes]
uninstall-codex *flags:
    @scripts/install-mcp.sh uninstall codex {{ flags }}

# ── release ──────────────────────────────────────────────────────────────

# Assemble the DMG's contents from local images into build/bundle (to test install.sh)
bundle prefix="crw-config/" tag="local":
    rm -rf build/bundle
    scripts/release-bundle.sh {{ prefix }} {{ tag }} build/bundle

# Tag v<version> (signed), push it and open a draft release; CI builds and publishes it
release version:
    scripts/release.sh {{ version }}

# ── tests ────────────────────────────────────────────────────────────────

# Scrape through each stealth tier over HTTP, plus a bot-check report
test-stealth:
    scripts/test-stealth.sh

# Ask Claude Code to scrape through each tier via the crw MCP server
test-stealth-claude:
    scripts/test-agent.sh claude

# Ask Codex to scrape through each tier via the crw MCP server
test-stealth-codex:
    scripts/test-agent.sh codex
