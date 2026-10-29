CRW, the Firecrawl-compatible scraper, with all three stealth tiers (`impersonated-http`, Google Chrome as `chrome`, and `camoufox`), plus its MCP server for Claude and Codex. Every image is built from upstream source, with Chrome from Google's stable channel.

## Install on an Apple Silicon Mac

1. Start Docker (OrbStack or Docker Desktop).
2. Download **@DMG@** and open it.
3. In Terminal, run `/Volumes/crw-build-aio-mcp/install.sh`.

The installer pulls the images (about 10 GB the first time), starts the stack on `http://127.0.0.1:3000`, and registers the `crw` MCP server with Claude Code, Claude Desktop, the Codex CLI and ChatGPT desktop. It shows every config change and asks before applying it. Afterwards, restart Claude Desktop and ChatGPT desktop, and use `crw-aio help` to manage the stack.

<!-- notarized -->
The disk image and the `crw-mcp` binary are signed with a Developer ID, and the disk image is notarized and stapled.
<!-- /notarized -->
<!-- unsigned -->
This build is **not signed or notarized**. If macOS blocks `crw-mcp`, run `xattr -dr com.apple.quarantine ~/Library/Application\ Support/crw-build-aio-mcp`.
<!-- /unsigned -->

## Images

Each image is multi-arch (linux/amd64 and linux/arm64) and signed with cosign:

@IMAGES@

To check a signature:

```sh
cosign verify @REGISTRY@crw-config-crw:@VERSION@ \
  --certificate-identity-regexp '^https://github.com/swack-tools/crw-build-aio-mcp/\.github/workflows/images\.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Built from

| upstream | commit |
|---|---|
@COMMITS@

## Licenses

crw and SearXNG are AGPL-3.0; Camoufox is MPL-2.0; Google Chrome is under Google's Chrome terms of service. Running the stack locally is fine. Offering it to others as a service carries those licenses' terms.
