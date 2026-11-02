crw-build-aio-mcp @VERSION@
===========================

CRW, a Firecrawl-compatible web scraper, with all three stealth tiers, plus its
MCP server for Claude, Codex, and Antigravity, on Apple silicon Macs.

  chrome              Google Chrome on a virtual display, over plain CDP
  camoufox            Camoufox, a fingerprint-spoofing Firefox fork
  impersonated-http   No browser. Mimics Chrome's TLS and HTTP/2 fingerprint

Every image is built from upstream source by
https://github.com/swack-tools/crw-build-aio-mcp and pulled from Docker Hub.
Chrome is Google's stable release.
@IMAGES@

Requirements
------------
- macOS on Apple silicon
- Docker running: OrbStack or Docker Desktop
- About 10 GB of disk space for the images
- python3 (if you don't have it, run xcode-select --install)

Install
-------
In Terminal, run the following command:

  /Volumes/crw-build-aio-mcp/install.sh

The installer does the following:

- Copies everything to ~/Library/Application Support/crw-build-aio-mcp.
- Starts the stack on http://127.0.0.1:3000, or on the next free port after
  asking.
- Registers the crw MCP server with Claude Code, Claude Desktop, the Codex
  command-line tool, ChatGPT desktop, and Antigravity, if you have it. It shows
  each config change and asks before applying it.

If Claude Desktop is running, the installer quits it and reopens it. When the
installer finishes, restart both ChatGPT desktop and Antigravity.

To upgrade, run the installer from a newer disk image.

Use
---
Ask Claude, Codex, or Antigravity to scrape a page. You don't need to pick a
renderer. CRW renders the page in Chrome and, if Chrome is blocked, in Camoufox.

  crw-aio status | logs | test | down | up | update
  crw-aio mcp install claude      only Claude (or: codex, antigravity)
  crw-aio uninstall
  crw-aio help

For more information, see
https://github.com/swack-tools/crw-build-aio-mcp/blob/main/docs/install.md

Licenses
--------
CRW and SearXNG are AGPL-3.0, Camoufox is MPL-2.0, and Google Chrome is under
Google's Chrome terms of service. Running them locally is fine. Offering this
stack to others as a service carries those licenses' terms.
