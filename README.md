<!-- vale Google.Headings = NO -->
# crw-build-aio-mcp
<!-- vale Google.Headings = YES -->

[![Latest release](https://img.shields.io/github/v/release/swack-tools/crw-build-aio-mcp)](https://github.com/swack-tools/crw-build-aio-mcp/releases/latest)
[![Tests](https://github.com/swack-tools/crw-build-aio-mcp/actions/workflows/test.yml/badge.svg)](https://github.com/swack-tools/crw-build-aio-mcp/actions/workflows/test.yml)
[![License: AGPL-3.0-or-later](https://img.shields.io/badge/license-AGPL--3.0--or--later-blue)](LICENSE)

crw-build-aio-mcp runs [CRW](https://github.com/fastcrw/crw), a
Firecrawl-compatible web scraper, on your own machine with all three of its
stealth tiers turned on. It also registers CRW's Model Context Protocol (MCP)
server, so Claude, Codex, and Antigravity can scrape and search the web through
your local stack, and installs CRW's agent skills, which teach them which tool a
task needs: search, scrape, map, crawl, parse, or extract.

| Tier | Description | Where it runs |
|---|---|---|
| `chrome` | Google Chrome on a virtual display, driven over the Chrome DevTools Protocol (CDP) | `chrome-stealth` container |
| `camoufox` | Camoufox, a fingerprint-spoofing Firefox fork, behind the camofox-browser REST server | `camofox` container |
| `impersonated-http` | No browser. Mimics Chrome's TLS and HTTP/2 fingerprint | Inside `crw` |

You don't need to choose a tier. A scrape that doesn't set `renderer`, which is
how MCP clients call it, tries each tier until one gets the page:

1. CRW renders the page in Chrome.
1. If Chrome is blocked, CRW renders the page in Camoufox.
1. If Camoufox is blocked, CRW tries the `impersonated-http` tier, unless the block
   was Akamai's, which that tier can't get past.
1. If every tier is blocked, the scrape fails as blocked instead of returning the
   block page.

On a machine short on memory, `just up-minimal` starts the stack without
Camoufox, so a page that Chrome is blocked on fails instead of falling back. See
[Run with less memory](docs/build-from-source.md#run-with-less-memory).

Files, such as PDFs, go straight to `impersonated-http`. For the sites that
this order got past when last checked, see
[Anti-bot results](docs/anti-bot-results.md).

Rendering in Chrome costs a second or more per page. When speed matters more
than stealth, set `renderer: "impersonated-http"` to fetch the page without a
browser in well under a second, or `renderJs: false` to use plain HTTP. Either
returns a page that draws its content with JavaScript, such as a shop's product
grid, as an empty shell, so check that the result carries what you need.

## Get started

You need an Apple silicon Mac with Docker running, either OrbStack or Docker
Desktop.

1. Download the disk image from the
   [latest release](https://github.com/swack-tools/crw-build-aio-mcp/releases/latest)
   and open it.
1. In Terminal, run the installer:

   ```sh
   /Volumes/crw-build-aio-mcp/install.sh
   ```

   The installer pulls about 10 GB of images from Docker Hub, starts the stack,
   and registers the MCP server. It shows each config change and asks before
   applying it.

1. Check that all three tiers work:

   ```sh
   crw-aio test
   ```

   If your shell can't find `crw-aio`, add `~/.local/bin` to your `PATH`.

For the details, see [Install from a release](docs/install.md). On Linux, or to
compile everything yourself, see [Build from source](docs/build-from-source.md).

## Scrape and search

Ask your MCP client to scrape a page or search the web. The server provides
`crw_scrape`, `crw_search`, `crw_crawl`, `crw_map`, `crw_extract`, and
`crw_parse_file`.

CRW also serves Firecrawl's API on `http://127.0.0.1:3000`. If that port is busy
when the stack starts, you can choose the next free one. Leave `renderer` unset
to get the stealth order.

To scrape one page:

```sh
curl -s localhost:3000/v1/scrape -H 'content-type: application/json' \
  -d '{"url":"https://example.com","formats":["markdown"]}'
```

To search, with the hits in `data.results`:

```sh
curl -s localhost:3000/v1/search -H 'content-type: application/json' \
  -d '{"query":"crw scraper","limit":5}'
```

To search and scrape each hit, with the content in `data.results[].markdown`:

```sh
curl -s localhost:3000/v1/search -H 'content-type: application/json' \
  -d '{"query":"crw scraper","limit":3,"scrapeOptions":{"formats":["markdown"]}}'
```

A search goes through SearXNG to public search engines without a browser, so
only the scrape of each hit uses the stealth tiers.

With `renderJs: false`, a scrape uses plain HTTP with a Chrome User-Agent, then
the `impersonated-http` tier if the site blocks that.

## Documentation

| Page | Read it to |
|---|---|
| [Install from a release](docs/install.md) | Install, upgrade, manage, and remove the Mac release |
| [Build from source](docs/build-from-source.md) | Build the stack, run it on Linux, and look up `just` recipes |
| [How it works](docs/how-it-works.md) | Understand the services, the stealth settings, and each patch to CRW |
| [Anti-bot results](docs/anti-bot-results.md) | See which sites and fingerprint tests it passes, and its known limits |
| [CI and releases](docs/ci-and-releases.md) | Understand how images and releases get built and published |
| [Contributing](CONTRIBUTING.md) | Send a change, run the tests, and check the docs |

## License

This project is licensed under the
[GNU Affero General Public License v3.0 or later](LICENSE)
(`AGPL-3.0-or-later`). If you modify it and distribute it, or let people use
your modified version over a network, such as a hosted MCP or scraping service,
you must offer those users the complete source of your version under the same
license.

The bundled upstream projects keep their own licenses. CRW and SearXNG are
AGPL-3.0, Camoufox is MPL-2.0, and Google Chrome is under Google's terms of
service. The patches in `patches/crw/` are modifications of CRW, so CRW's AGPL
covers them as well as this project's.

Building and running these projects locally is fine. Publishing the images with
`just push` or offering the stack as a service carries their terms.
