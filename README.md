# crw-build-aio-mcp

Run [CRW](https://github.com/fastcrw/crw), the Firecrawl-compatible scraper, locally with all three of its stealth tiers on at once, built from upstream source:

| tier | what it is | where it runs |
|---|---|---|
| `chrome` via `--profile stealth` | Google Chrome on a virtual display, driven over plain CDP | `chrome-stealth` container |
| `impersonated-http` | no browser; mimics Chrome's TLS/HTTP2 fingerprint | inside crw |
| `camoufox` | Camoufox, a fingerprint-spoofing Firefox fork, behind the camofox-browser REST server | `camofox` container |

A scrape with no `renderer` set (which is how Claude and Codex call it) renders the page in Chrome, then in Camoufox if Chrome is blocked, then tries the `impersonated-http` tier. If that is blocked too, the scrape fails as blocked rather than returning the block page. Files (PDFs and the like) go to `impersonated-http` directly. With `renderJs: false` it uses plain HTTP (with a Chrome User-Agent) instead, then the `impersonated-http` tier if a site blocks that.

No prebuilt app images are pulled. The scripts clone the upstream repos and compile crw, Camoufox (Firefox), camofox-browser and SearXNG. Chrome is Google's stable release, from Google's apt repository.

## Install a release (no build)

Each [release](https://github.com/swack-tools/crw-build-aio-mcp/releases) has a signed, notarized disk image for Apple Silicon Macs.
1. Start Docker (OrbStack or Docker Desktop).
2. Open the disk image and run `/Volumes/crw-build-aio-mcp/install.sh` in Terminal.

It pulls the prebuilt images from Docker Hub, starts the stack and registers the MCP server, asking before each config change. Afterwards, `crw-aio help` manages the stack. Images are also tagged `nightly`, rebuilt each night from upstream heads.

## Build it yourself

```sh
just up-stealth                     # first run clones + builds everything (Camoufox takes hours)
just test-stealth                   # pin a scrape to each tier, then run bot checks with default settings
just install                        # MCP server into Claude and Codex (shows the changes, asks first)
just install-claude                 # only Claude Code + Claude Desktop
just install-codex                  # only Codex CLI + ChatGPT desktop
just test-stealth-claude            # the same check, driven by the claude CLI through MCP
just test-stealth-codex             # ... and by codex exec
```

Every install/uninstall recipe prints the exact commands and config diffs, then asks `Apply these changes? [y/N]`. Add `--dry-run` to only print, or `--yes` to skip the question (needed without a terminal).

Requirements: Docker with buildx (a containerd image store is needed for `build-all`), `just`, `git`, `python3` (3.11+), `cargo` (for the native MCP binary), plus the `claude` and `codex` CLIs for those recipes. It is developed on Apple Silicon (arm64) with OrbStack.

## Recipes

| recipe | does |
|---|---|
| `up-stealth` / `run-stealth` | `build`, choose a host port, `compose up --wait`, print the live renderers |
| `down`, `ps`, `logs [svc…]`, `caps` | stack housekeeping |
| `build` | every image for this machine's arch |
| `build-arm64`, `build-x86` | every image for one arch |
| `build-all` | both arches as multi-arch images |
| `push` | `build-all`, then push to `$REGISTRY` |
| `build-camoufox [arch]` | only the Camoufox zip in `dist/` |
| `build-mcp` | native `bin/crw-mcp` (proxy-only build) |
| `fetch` | clone any missing upstream into `src/` |
| `update` | fast-forward every upstream, then `build` |
| `install`, `install-claude`, `install-codex` `[--dry-run] [--yes]` | register the MCP server with both, Claude only, or Codex only |
| `uninstall`, `uninstall-claude`, `uninstall-codex` `[--dry-run] [--yes]` | remove it again |
| `test-stealth`, `test-stealth-claude`, `test-stealth-codex` | tests |
| `bundle [prefix] [tag]` | the disk image's contents, from local images, into `build/bundle` |
| `release <version>` | signed tag `v<version>` and a draft GitHub release; CI does the rest |

## How it fits together

- **Sources:** `scripts/fetch-sources.sh` clones each upstream's default branch into `src/`.
  - `<NAME>_REF` checks out something else, e.g. `CAMOUFOX_REF=v152.0.4-beta.28`.
  - `SRC_<NAME>=/path` uses an existing checkout instead of cloning.
- **Camoufox:** `scripts/build-camoufox.sh` runs upstream's own builder image (`browser/Dockerfile`) and writes `dist/camoufox-<ver>-lin.<arch>.zip`.
  - The builder runs as linux/amd64 and cross-compiles to arm64 or x86_64, which is the path upstream tests.
  - Its base image is pinned to `ubuntu:24.04` because `26.04`'s tar fails under Rosetta.
  - Toolchains are kept in a named Docker volume per Firefox version, and ccache in one that outlives versions, so rebuilds are incremental.
  - A cold build takes hours under emulation. To skip it, set `CAMOUFOX_DIST_REGISTRY=docker.io/<user>/` (or `REGISTRY`) in `.env`. The script then fetches the zip CI built from the same inputs, in about a minute, and compiles only when there is none. `CAMOUFOX_PULL=0` or `FORCE=1` always compiles.
- **Images:** `docker-bake.hcl` builds the images.
  - Upstream Dockerfiles that build `FROM` a registry image (`searxng/base:*`) get bake targets built here instead, wired in through `contexts`.
  - `scripts/prep-sources.sh` patches camofox-browser's Dockerfile to install our Camoufox zip instead of downloading a release. It also applies `patches/<name>/*.patch` to the checkouts, and `fetch-sources.sh --update` reverts them before pulling. Either one fails loudly if upstream changes what it patches.
- **Compose:** `compose.override.yml` is layered on crw's own `docker-compose.yml` and `docker-compose.stealth.yml`, so upstream's settings and hardening still apply.
  - It swaps in the local images and adds the `camofox` service, which crw reaches through `CRW_RENDERER__CAMOUFOX__BASE_URL`.
  - **Stealth by default:** these settings are for a scrape that sets nothing, as an MCP client sends it.
    - `CRW_RENDERER__MODE=chrome`: upstream's `auto` mode tries Lightpanda first, which has no stealth and answers most pages, so Lightpanda is neither built nor started.
    - `CRW_RENDERER__CAMOUFOX__INCLUDE_IN_AUTO=true`: Camoufox is tried when Chrome is blocked.
    - `CRW_RENDERER__RENDER_JS_DEFAULT=true`: every page is rendered in a browser. Upstream starts with plain HTTP and only renders pages that look unfinished, so a page that fills itself in after load (a bot check's verdict, say) came back as its empty shell. `renderJs: false` still skips the browser.
    - `CRW_RENDERER__CHROME_INTERCEPT_RESOURCES=false`: pages load images, fonts and analytics as they would for a person. Upstream blocks them to save time, and pages can tell.
    - `CRW_RENDERER__CHROME_CHALLENGE_MAX_RETRIES=8` and `CRW_RENDERER__CHROME_NAV_BUDGET_MS=40000`: up to 24s for an anti-bot challenge to clear. Upstream checks once, inside a 12s page budget.
    - `CRW_RENDERER__CHROME_OUTBOUND_CHECK=false`: Chrome's requests go straight out, as in a person's browser. Upstream pauses each one to check it against private network ranges, which breaks some anti-bot scripts (Kasada's cleared one cold visit in four with it, every one without). Chrome's own Local Network Access still asks before a public page reaches a private address.
    - `CRW_RENDERER__CHROME_CONTEXT_POOL_ENABLED=false`: pages open in Chrome's own profile, as in a person's browser, so cookies a site sets (an anti-bot clearance, say) are there on the next visit. Upstream's pool gives each page its own browser context, which pages can tell is incognito.
  - **User-Agent:** it replaces crw's `CRW/0.0.1` with a Linux Chrome User-Agent. `up.sh` sets the version to match the Chrome inside chrome-stealth.
  - **Chrome:** `docker/chrome-stealth` runs Google Chrome stable on a virtual display (Xvfb, 1920×1080), with nothing attached to it but crw. Upstream runs browserless's Chromium image instead.
    - browserless drives every Chrome it launches through puppeteer, which turns on the CDP Runtime domain in each page and worker. Pages can detect that, so deviceandbrowserinfo.com reported a bot and Cloudflare's challenge never cleared.
    - Headless Chrome also differs from desktop Chrome (its User-Agent inside workers, client hints, timing), and stealth scripts that cover this up get caught by checks such as CreepJS. Windowed Chrome has nothing to cover up.
    - It is Google Chrome, not Chromium: detectors such as rebrowser's flag a Chromium build (as Chrome for Testing) because its client hints don't name Google Chrome.
    - WebGL is off, as Chrome leaves it on a machine with no usable GPU. Each way of turning it on in a container gets caught by a real anti-bot vendor: Mesa's software renderer by Akamai, the same renderer under a real GPU's name by DataDome, and Chrome's SwiftShader by Cloudflare. With it off, all three let Chrome through.
    - The display has a 40px taskbar's worth of space reserved and the window fits the rest. A screen whose whole area is free, with a window as large as the screen, is how headless Chrome looks.
    - `pointer.js` moves the real X11 pointer (xdotool) over each page as it opens and scrolls a little, since behavior checks score a page that loads with no pointer movement as a bot. It also clicks Cloudflare's Turnstile checkbox ("Verify you are human") when a site asks for it. A click sent over DevTools reports matching screen and page coordinates, a known automation tell, so this one is real input too.
    - Chrome only listens on loopback when it has a window, so a small relay (`relay.js`) exposes its DevTools port to crw.
    - It gets this machine's timezone from `up.sh` (as does Camoufox), since a detector can compare the timezone with the IP's location.
  - **Camoufox:** `docker/camofox` adds a camofox-browser plugin that clicks Cloudflare's Turnstile checkbox ("Verify you are human"), which Cloudflare shows Camoufox where it lets Chrome straight through. The click is a real X11 one (xdotool on Camoufox's virtual display), because Playwright's synthetic clicks don't reach the checkbox's cross-origin iframe.
  - **`patches/crw/cdp-stealth.patch`:**
    - crw no longer turns on the CDP Runtime domain, which it never needed.
    - Each section of its injected stealth script only patches a value that is missing or wrong, so desktop Chrome runs it as a no-op. The WebGL spoof ("Intel Iris OpenGL Engine", a macOS GPU under a Linux User-Agent) is gone.
    - It skips the User-Agent override when Chrome already sends that User-Agent, because an override without client-hint metadata empties `navigator.userAgentData`.
    - Once an anti-bot challenge clears, it reports the real page's HTTP status rather than the challenge's 403, and stops waiting. It used to take Cloudflare's telemetry script, which every Cloudflare page carries, for a challenge still running.
    - After a page loads it waits until the network has been quiet for a second (1–4s), so scripts that check the browser after load have written their result.
    - It waits for Kasada's challenge (an HTTP 429 that solves itself and reloads) as it does for Cloudflare's.
    - It answers JavaScript dialogs (`alert`, `confirm`) after 0.7s. crw left them open, which froze the page until the render timed out.
    - It adds `CRW_RENDERER__CHROME_OUTBOUND_CHECK` (see above).
  - **`patches/crw/camoufox-wait-for.patch`** makes the Camoufox renderer honor `waitFor`, and without one, wait for the page to settle (camofox-browser's own readiness check, up to 6s) instead of reading it the moment navigation returns.
  - **`patches/crw/camoufox-after-chrome.patch`** lets Camoufox follow Chrome in auto mode (`include_in_auto`) when the mode is `chrome`, not only `auto`.
  - **`patches/crw/challenge-markers.patch`** fixes how crw tells a block page from a page that loaded, which decides whether it tries the next tier:
    - PerimeterX's sensor tag and Cloudflare's telemetry script, which sit on pages that loaded, no longer count as blocks. On Walmart, Wayfair and Trulia that had sent every scrape on to Camoufox for nothing.
    - It recognizes Akamai's block page as adidas serves it ("Reference Error: …"), Akamai's interstitial (`sec-if-cpt`, a proof of work that reloads into the page) and Reddit's "Prove your humanity" captcha. Both browsers wait for Akamai's interstitial to clear, as they do for Cloudflare's and Kasada's. Before, these came back as successful scrapes of the block page.
    - It reports the real page's status after AWS WAF's challenge (a 202) clears.
  - **`patches/crw/render-browser-first.patch`:** a page goes to the browser first. Upstream fetched every page once over plain HTTP before rendering it, to check its content type. That request is a bot's TLS handshake from your IP, and Akamai answered it with an IP-reputation block on Kohl's, Marriott and Apartments.com, then blocked Chrome on the latter two.
    - HTTP is now the fallback, through the `impersonated-http` client: when both browsers are blocked or fail, and for files. A URL naming a file (`.pdf`, `.docx`, `.zip`, images, media) goes straight to it, and Chrome hands over a PDF or download it opens from any other URL.
    - When the fallback gets a block page too, the scrape fails as blocked rather than returning that page.
  - **`patches/crw/revisit-walls.patch`:** when Chrome's first visit gets a block page (not a challenge that solves itself, which it waits out), it reloads once after a short pause, as a person would. Some anti-bot systems turn a first visit away while setting a cookie that lets the next one through: from a fresh profile, Reddit shows a captcha the first time and its automatic check passes on the reload.
- **Ports:** crw is published on `127.0.0.1:$CRW_HOST_PORT` (default 3000). If the port is busy, `up-stealth` offers the next free one and saves the choice to `.env`.
- **MCP:** `bin/crw-mcp` runs in proxy mode, pointed at the stack with `CRW_API_URL`.
  - Codex gets `tool_timeout_sec = 300`, because Camoufox scrapes can outlast its 60s default.
  - Every config file edit is shown as a diff and backed up first.

## What it gets past

With default settings (no `renderer`, no `waitFor`) and a fresh Chrome profile, crw loaded the real page on each of these sites, checked on 2026-10-29. Sites are grouped by the protection each is known to use; Chrome got each one itself except those marked *(Camoufox)*, where Chrome was turned away and the fallback got through:

| protection | sites |
|---|---|
| Cloudflare (including interactive Turnstile) | g2.com, indeed.com, glassdoor.com, crunchbase.com, gitlab.com sign-in, upwork.com, chatgpt.com, quizlet.com, coingecko.com, doordash.com, opensea.io, ziprecruiter.com, medium.com, genius.com, coinbase.com, patreon.com, producthunt.com, similarweb.com, crunchyroll.com, nowsecure.nl, nopecha.com's demo, scrapingcourse.com's challenges, investing.com *(Camoufox)* |
| DataDome | leboncoin.fr, tripadvisor.com, hermes.com, reuters.com, etsy.com, yelp.com, idealista.com, allegro.pl, soundcloud.com, fnac.com, seloger.com, vinted.com, footlocker.com, wsj.com, deezer.com |
| HUMAN (PerimeterX) | zillow.com, walmart.com, stockx.com, wayfair.com, bloomberg.com, seekingalpha.com, chegg.com, bhphotovideo.com, zoominfo.com, realtor.com, trulia.com, ssense.com, priceline.com, crateandbarrel.com, fiverr.com *(Camoufox)* |
| Akamai | nike.com, bestbuy.com, lowes.com, ups.com, fedex.com, usps.com, macys.com, kohls.com, costco.com, united.com, delta.com, aa.com, marriott.com, hilton.com, walgreens.com, sephora.com, asos.com, zara.com, ikea.com, homedepot.com, adidas.com, apartments.com, expedia.com, hm.com *(the last five Camoufox)* |
| Kasada | hyatt.com, twitch.tv, realestate.com.au, wizzair.com, scheels.com, ticketek.com.au |
| Imperva | whoscored.com, pokemoncenter.com, copart.com, iaai.com, ryanair.com |
| AWS WAF | ballotpedia.org, imdb.com, goodreads.com, booking.com, stubhub.com, audible.com |
| F5 Shape | southwest.com, target.com, nordstrom.com, starbucks.com |
| their own | amazon.com, google.com search, bing.com, duckduckgo.com, reddit.com (on the reload), instagram.com, x.com, youtube.com, tiktok.com, airbnb.com, kayak.com, ticketmaster.com, shein.com, temu.com, aliexpress.com, craigslist.org, ebay.com *(Camoufox)* |

The one it doesn't get past is lacentrale.fr, whose DataDome shows both browsers a captcha; that scrape fails as blocked. LinkedIn company pages load its sign-up wall, which is a login requirement rather than bot detection.

On fingerprint test pages it rates as a person: deviceandbrowserinfo.com "not a bot", rebrowser's detector all green, fingerprint.com bot "not detected" (no tampering, VM or incognito) and its scraping demo serves the protected data, Google's reCAPTCHA v3 demo scores it 0.9 (the highest it gives), BrowserScan and pixelscan's bot checks "Normal"/"Clear" on every row, whoer.net 100%, CreepJS 0% headless and 0% stealth. Anti-bot vendors change their checks often, so this is a snapshot; `just test-stealth` re-checks the core of it.

## CI and releases

GitHub Actions publishes multi-arch (amd64 + arm64) images to Docker Hub as `<DOCKERHUB_USERNAME>/crw-config-<name>`, signed with cosign:

| workflow | when | does |
|---|---|---|
| `images.yml` | called by the two below, or by hand | Builds each arch on a native runner and pushes by digest, then joins the digests into multi-arch tags and signs them. |
| `nightly.yml` | daily | Rebuilds what changed upstream and tags `nightly` and `nightly-YYYYMMDD`. |
| `release.yml` | `v*` tag | Tags the images `<version>` and `latest`. Builds, signs and notarizes the disk image (`crw-mcp` plus a compose bundle pinned to those images), then publishes the draft release. |

- **Skipping unchanged images:** `scripts/ci-plan.sh` pins each upstream to its current commit. Each image gets a key from its own inputs (its upstreams' commits, their `patches/`, its `docker/<name>/` files and the shared bake recipe) and is pushed as `src-<key>`. A run whose key already exists only retags, so a change to one image rebuilds only that image.
- **Camoufox:** compiled only when its build inputs change, on a free x86_64 runner (about 2h10m per arch). The key (`camoufox_key` in `scripts/lib.sh`) hashes upstream's `browser/` tree minus its tests, `patches/camoufox/` and `build-camoufox.sh`. Upstream's README, docs and Python and TypeScript libraries change most days and don't trigger a compile. The zips are kept on Docker Hub as `crw-config-camoufox-dist:<key>-<arch>`.
- **crw build cache:** crw's cargo-chef dependency layer is cached per arch in `crw-config-buildcache` on Docker Hub, so a crw change that leaves its dependencies alone skips recompiling them.
- **Chrome:** chrome-stealth's key includes Google's current Chrome stable version, so the nightly picks up each Chrome release.
- **Secrets:** the swack-tools org secrets `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` and `APPLE_*` (the same Developer ID setup as update-all). Without the Apple secrets, a release still ships, unsigned.

To release, run `just release 0.1.0` on an up-to-date `main`.

## What is still prebuilt

Building these from source is out of scope: official base images (debian, ubuntu, node, rust, alpine), Google Chrome, Mozilla's build toolchains, the Camoufox font bundle, uBlock Origin, yt-dlp, and packages from distro, npm, cargo and PyPI registries.

## Notes

- **Version risk:** Camoufox `main` can be ahead of the version camofox-browser pins. If the camoufox tier fails, set `CAMOUFOX_REF` to the pinned tag (see `src/camofox-browser/Dockerfile`) and run `just update`.
- **Remaining fingerprint tells:** Chrome has no WebGL (see above), so bot.sannysoft.com fails its two WebGL rows, BrowserScan rates the fingerprint 90% authentic rather than 100%, and iphey.com's check never finishes. The timezone (set by `up.sh`) and CPU count are the host's. fpscanner's `WEBDRIVER` test (on bot.incolumitas.com) fails because `navigator.webdriver` exists, as it does in every current Chrome.
- **Behavior checks:** the pointer moves, but a scrape never types or fills in a form, so tests that score those (deviceandbrowserinfo.com's interaction test) have nothing to score.
- **Crash reports:** camofox-browser's crash reporter is off (`CAMOFOX_CRASH_REPORT_ENABLED=false`).
- **Licenses:** crw and SearXNG are AGPL, and the chrome-stealth image contains Google Chrome, which is under Google's Chrome terms of service. Building and running them locally is fine; publishing the images (`just push`) or offering the stack as a service carries their terms.

## License

This project is licensed under the [GNU Affero General Public License v3.0 or later](LICENSE) (SPDX: `AGPL-3.0-or-later`). If you modify it and distribute it, or let people use your modified version over a network (for example, as a hosted MCP or scraping service), you must offer those users the complete source of your version under the same license.

The bundled upstream projects keep their own licenses: crw and SearXNG are AGPL-3.0, Camoufox is MPL-2.0, and Google Chrome is under Google's terms of service. The crw patches in `patches/crw/` are modifications of crw and are covered by its AGPL as well as this one.

Contributions are welcome under the [Contributor License Agreement](CLA.md); see [CONTRIBUTING.md](CONTRIBUTING.md).
