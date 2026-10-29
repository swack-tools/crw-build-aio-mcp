crw-build-aio-mcp @VERSION@
===========================

CRW (a Firecrawl-compatible scraper) with all three stealth tiers, plus its MCP
server for Claude and Codex, on Apple Silicon Macs.

  impersonated-http   no browser; mimics Chrome's TLS/HTTP2 fingerprint
  chrome              Google Chrome on a virtual display, over plain CDP
  camoufox            Camoufox, a fingerprint-spoofing Firefox fork

Every image is built from upstream source by
https://github.com/swack-tools/crw-build-aio-mcp (Chrome is Google's stable
release) and pulled from Docker Hub:
@IMAGES@

Requirements
------------
- macOS on Apple Silicon
- Docker running: OrbStack or Docker Desktop
- About 10 GB of disk for the images
- python3 (run xcode-select --install if you don't have it)

Install
-------
In Terminal:

  /Volumes/crw-build-aio-mcp/install.sh

It copies everything to ~/Library/Application Support/crw-build-aio-mcp, starts
the stack on http://127.0.0.1:3000 (or the next free port, after asking), and
registers the crw MCP server with Claude Code, Claude Desktop, the Codex CLI and
ChatGPT desktop. It shows each config change and asks before applying it.
Restart Claude Desktop and ChatGPT desktop afterwards.

Run it again from a newer disk image to upgrade.

Use
---
Ask Claude or Codex to scrape a page; there is no need to pick a renderer.
crw renders it in Chrome and, if Chrome is blocked, in Camoufox.

  crw-aio status | logs | test | down | up | update
  crw-aio mcp install claude      only Claude (or: codex)
  crw-aio uninstall

Licenses
--------
crw and SearXNG are AGPL-3.0; Camoufox is MPL-2.0; Google Chrome is under
Google's Chrome terms of service. Running them locally is fine. Offering this
stack to others as a service carries those licenses' terms.
