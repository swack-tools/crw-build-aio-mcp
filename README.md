# crw-build-aio-mcp

Run [CRW](https://github.com/fastcrw/crw), the Firecrawl-compatible scraper, locally with all three of its stealth tiers on at once, built from upstream source:

| tier | what it is | where it runs |
|---|---|---|
| `chrome` via `--profile stealth` | Google Chrome on a virtual display, driven over plain CDP | `chrome-stealth` container |
| `impersonated-http` | no browser; mimics Chrome's TLS/HTTP2 fingerprint | inside crw |
| `camoufox` | Camoufox, a fingerprint-spoofing Firefox fork, behind the camofox-browser REST server | `camofox` container |

A scrape with no `renderer` set (which is how Claude and Codex call it) renders the page in Chrome, then in Camoufox if Chrome is blocked. With `renderJs: false` it uses plain HTTP (with a Chrome User-Agent) instead, then the `impersonated-http` tier if a site blocks that.

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
  - Toolchains and ccache are kept in a named Docker volume, so rebuilds are incremental.
  - A cold build takes hours under emulation.
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
  - **User-Agent:** it replaces crw's `CRW/0.0.1` with a Linux Chrome User-Agent. `up.sh` sets the version to match the Chrome inside chrome-stealth.
  - **Chrome:** `docker/chrome-stealth` runs Google Chrome stable on a virtual display (Xvfb, 1920×1080), with nothing attached to it but crw. Upstream runs browserless's Chromium image instead.
    - browserless drives every Chrome it launches through puppeteer, which turns on the CDP Runtime domain in each page and worker. Pages can detect that, so deviceandbrowserinfo.com reported a bot and Cloudflare's challenge never cleared.
    - Headless Chrome also differs from desktop Chrome (its User-Agent inside workers, client hints, timing), and stealth scripts that cover this up get caught by checks such as CreepJS. Windowed Chrome has nothing to cover up.
    - It is Google Chrome, not Chromium: detectors such as rebrowser's flag a Chromium build (as Chrome for Testing) because its client hints don't name Google Chrome.
    - WebGL comes from Mesa's software renderer (llvmpipe), as on a Linux machine without GPU drivers; Chrome would otherwise turn WebGL off. Its own software renderer, SwiftShader, fails Cloudflare's challenge.
    - The display has a 40px taskbar's worth of space reserved and the window fits the rest. A screen whose whole area is free, with a window as large as the screen, is how headless Chrome looks.
    - Chrome only listens on loopback when it has a window, so a small relay (`relay.js`) exposes its DevTools port to crw.
    - It gets this machine's timezone from `up.sh` (as does Camoufox), since a detector can compare the timezone with the IP's location.
  - **Camoufox:** `docker/camofox` adds a camofox-browser plugin that clicks Cloudflare's Turnstile checkbox ("Verify you are human"), which Cloudflare shows Camoufox where it lets Chrome straight through. The click is a real X11 one (xdotool on Camoufox's virtual display), because Playwright's synthetic clicks don't reach the checkbox's cross-origin iframe.
  - **`patches/crw/cdp-stealth.patch`:**
    - crw no longer turns on the CDP Runtime domain, which it never needed.
    - Each section of its injected stealth script only patches a value that is missing or wrong, so desktop Chrome runs it as a no-op. The WebGL spoof ("Intel Iris OpenGL Engine", a macOS GPU under a Linux User-Agent) is gone.
    - It skips the User-Agent override when Chrome already sends that User-Agent, because an override without client-hint metadata empties `navigator.userAgentData`.
    - Once an anti-bot challenge clears, it reports the real page's HTTP status rather than the challenge's 403, and stops waiting. It used to take Cloudflare's telemetry script, which every Cloudflare page carries, for a challenge still running.
    - After a page loads it waits until the network has been quiet for a second (1–4s), so scripts that check the browser after load have written their result.
  - **`patches/crw/camoufox-wait-for.patch`** makes the Camoufox renderer honor `waitFor`, and without one, wait for the page to settle (camofox-browser's own readiness check, up to 6s) instead of reading it the moment navigation returns.
  - **`patches/crw/camoufox-after-chrome.patch`** lets Camoufox follow Chrome in auto mode (`include_in_auto`) when the mode is `chrome`, not only `auto`.
- **Ports:** crw is published on `127.0.0.1:$CRW_HOST_PORT` (default 3000). If the port is busy, `up-stealth` offers the next free one and saves the choice to `.env`.
- **MCP:** `bin/crw-mcp` runs in proxy mode, pointed at the stack with `CRW_API_URL`.
  - Codex gets `tool_timeout_sec = 300`, because Camoufox scrapes can outlast its 60s default.
  - Every config file edit is shown as a diff and backed up first.

## CI and releases

GitHub Actions publishes multi-arch (amd64 + arm64) images to Docker Hub as `<DOCKERHUB_USERNAME>/crw-config-<name>`, signed with cosign:

| workflow | when | does |
|---|---|---|
| `images.yml` | called by the two below, or by hand | Builds each arch on a native runner and pushes by digest, then joins the digests into multi-arch tags and signs them. |
| `nightly.yml` | daily | Rebuilds what changed upstream and tags `nightly` and `nightly-YYYYMMDD`. |
| `release.yml` | `v*` tag | Tags the images `<version>` and `latest`. Builds, signs and notarizes the disk image (`crw-mcp` plus a compose bundle pinned to those images), then publishes the draft release. |

- **Skipping unchanged images:** `scripts/ci-plan.sh` pins each upstream to its current commit. Each image gets a key from its inputs (those commits plus this repo's build recipe) and is pushed as `src-<key>`. A run whose key already exists only retags.
- **Camoufox:** compiled only when its commit changes, on a free x86_64 runner (about 3–4 hours). The zips are kept on Docker Hub as `crw-config-camoufox-dist:<key>-<arch>`.
- **Chrome:** chrome-stealth's key includes Google's current Chrome stable version, so the nightly picks up each Chrome release.
- **Secrets:** the swack-tools org secrets `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` and `APPLE_*` (the same Developer ID setup as update-all). Without the Apple secrets, a release still ships, unsigned.

To release, run `just release 0.1.0` on an up-to-date `main`.

## What is still prebuilt

Building these from source is out of scope: official base images (debian, ubuntu, node, rust, alpine), Google Chrome, Mozilla's build toolchains, the Camoufox font bundle, uBlock Origin, yt-dlp, and packages from distro, npm, cargo and PyPI registries.

## Notes

- **Version risk:** Camoufox `main` can be ahead of the version camofox-browser pins. If the camoufox tier fails, set `CAMOUFOX_REF` to the pinned tag (see `src/camofox-browser/Dockerfile`) and run `just update`.
- **Remaining fingerprint tells:** WebGL reports a software renderer (llvmpipe), which some detectors weigh against a browser. The timezone (set by `up.sh`) and CPU count are the host's. fpscanner's `WEBDRIVER` test (on bot.incolumitas.com) fails because `navigator.webdriver` exists, as it does in every current Chrome.
- **Behavior checks:** a scrape loads a page and reads it; it doesn't move a mouse or type. Tests that score that (bot.incolumitas.com's behavioral score, deviceandbrowserinfo.com's interaction test) have nothing to score.
- **Crash reports:** camofox-browser's crash reporter is off (`CAMOFOX_CRASH_REPORT_ENABLED=false`).
- **Licenses:** crw and SearXNG are AGPL, and the chrome-stealth image contains Google Chrome, which is under Google's Chrome terms of service. Building and running them locally is fine; publishing the images (`just push`) or offering the stack as a service carries their terms.
