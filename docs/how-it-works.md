# How it works

This page explains how the stack is built and what this project changes in
upstream CRW to get past anti-bot systems. Read it before you change stealth
behavior.

## Sources

`scripts/fetch-sources.sh` clones each upstream's default branch into
`~/.crw/src`. The clones and CRW's build output come to thousands of files, and
the Camoufox zip in `~/.crw/dist` is over a gigabyte, so they stay out of this
repository's folder. To change where they go or which ref gets checked out, see
[Settings](build-from-source.md#settings).

## Camoufox build

`scripts/build-camoufox.sh` runs upstream's own builder image
(`browser/Dockerfile`) and writes
`~/.crw/dist/camoufox-<VERSION>-lin.<ARCH>.zip`.

- The builder runs as linux/amd64 and cross-compiles to arm64 or x86_64, which is
  the path upstream tests.
- Its base image is pinned to `ubuntu:24.04`, because the `tar` in `26.04` fails
  under Rosetta.
- Toolchains are kept in a named Docker volume per Firefox version, and ccache is
  kept in a volume that outlives versions, so rebuilds are incremental. A compile
  ends by printing its ccache hit rate. `CAMOUFOX_CCACHE=<DIR>` keeps ccache in a
  directory instead, which is how CI carries it between runs in the GitHub cache.
- A cold build takes hours under emulation. With `CAMOUFOX_DIST_REGISTRY` or
  `REGISTRY` set, the script fetches the zip that CI built from the same inputs in
  about a minute, and compiles only when there is none. This project's CI publishes
  to `docker.io/swackhamer/`. `CAMOUFOX_PULL=0` or `FORCE=1` always compiles.

## Images

`docker-bake.hcl` builds the images.

- Upstream Dockerfiles that build `FROM` a registry image (`searxng/base:*`) get
  bake targets that are built here instead, wired in through `contexts`.
- `scripts/prep-sources.sh` patches camofox-browser's Dockerfile to install the
  local Camoufox zip instead of downloading a release. It also reapplies
  `patches/<NAME>/*.patch` to the checkouts on each run, in name order, and
  `fetch-sources.sh --update` reverts them before pulling.
- Either script fails loudly if upstream changes what it patches. The scripts
  stash changes that the patches can't undo, such as an older version of a patch
  after a `git pull` here, in the clone and print a warning.

### What's still prebuilt

Building these from source is out of scope:

- Official base images: debian, ubuntu, node, rust, and alpine.
- Google Chrome.
- Mozilla's build toolchains.
- The Camoufox font bundle, uBlock Origin, and yt-dlp.
- Packages from distribution, npm, cargo, and PyPI registries.

## Compose

`docker-compose.yml` belongs to this repository, so running the stack doesn't
need the clones. It started from `docker-compose.yml` and
`docker-compose.stealth.yml` in CRW's repository, and it keeps their hardening:
memory and process limits, read-only root filesystems, and no capabilities.
One exception: `chrome-stealth` keeps Chrome's profile on the container's disk
instead of in a `/tmp` tmpfs, because a tmpfs is memory, and Chrome's caches
filled upstream's 512 MB in about two days of steady scraping. Chrome then
had no space to write, and its DevTools sessions hung. `start.sh` caps the HTTP
and media caches, and `CHROME_SHM_SIZE` and `CHROME_MEM_LIMIT` in `.env` raise
the container's shared memory and memory limit for a page that needs more.

It runs the local images without upstream's Lightpanda and browserless services.
It adds the `camofox` service, which CRW reaches through
`CRW_RENDERER__CAMOUFOX__BASE_URL`. SearXNG gets CRW's
`config/searxng/settings.yml`.

The file's header lists the Git blob IDs of the upstream files that it came from.
`prep-sources.sh` warns when upstream changes one, so you can weigh the change
here.

### Stealth by default

These settings apply to a scrape that sets nothing, as an MCP client sends it.

| Setting | Effect | Why |
|---|---|---|
| `CRW_RENDERER__MODE=chrome` | Chrome goes first. | Upstream's `auto` mode tries Lightpanda first, which has no stealth and answers most pages. Lightpanda is neither built nor started. |
| `CRW_RENDERER__CAMOUFOX__INCLUDE_IN_AUTO=true` | CRW tries Camoufox when Chrome is blocked. | |
| `CRW_RENDERER__RENDER_JS_DEFAULT=true` | Every page renders in a browser, which costs a second or more per page over plain HTTP. A request can still set `renderJs: false` to skip the browser, or `renderer: "impersonated-http"` to pick that tier. | Upstream starts with plain HTTP and only renders pages that look unfinished, so a page that fills itself in after load, such as a bot check's verdict, came back as its empty shell. A page that draws its content with JavaScript, such as a shop's product grid, comes back the same way over HTTP. |
| `CRW_RENDERER__CHROME_FAST_READY=true` and `CRW_RENDERER__CHROME_SPA_SELECTOR_MAX_MS=3000` | After a page loads, CRW reads it as soon as its text is there and the network has settled, and waits at most 3 seconds for a page that never settles. | Upstream waits for a `main`, `article`, or `#content` element for up to 8 seconds, and a page without one, such as example.com, always waited the full 8 seconds. Upstream rarely pays this, since it serves such pages over HTTP; this stack renders every page, so it paid it on every page without such an element. A request that sets `waitFor` skips this wait and the other automatic ones, such as scrolling for lazy-loaded content. |
| `CRW_RENDERER__CHROME_INTERCEPT_RESOURCES=false` | Pages load images, fonts, and analytics as they do for a person. | Upstream blocks them to save time, and pages can tell. |
| `CRW_RENDERER__CHROME_CHALLENGE_MAX_RETRIES=8` and `CRW_RENDERER__CHROME_NAV_BUDGET_MS=40000` | An anti-bot challenge gets up to 24 seconds to clear. | Upstream checks once, inside a 12-second page budget. |
| `CRW_RENDERER__CHROME_OUTBOUND_CHECK=false` | Chrome's requests go straight out, as in a person's browser. Chrome's own Local Network Access still asks before a public page reaches a private address. | Upstream pauses each request to check it against private network ranges, which breaks some anti-bot scripts. Kasada's cleared one cold visit in four with the check and every one without it. |
| `CRW_RENDERER__CHROME_CONTEXT_POOL_ENABLED=false` | Pages open in Chrome's own profile, so cookies that a site sets, such as an anti-bot clearance, are there on the next visit. | Upstream's pool gives each page its own browser context, which pages can tell is incognito. |

### User agent string

The stack replaces CRW's `CRW/0.0.1` with a Linux Chrome User-Agent. `up.sh` sets
the version to match the Chrome inside `chrome-stealth`.

## Chrome tier

`docker/chrome-stealth` runs Google Chrome stable on a virtual display (Xvfb,
1920×1080), with nothing attached to it but CRW. Upstream runs browserless's
Chromium image instead.

- **No browserless.** The browserless image drives every Chrome that it launches through
  puppeteer, which turns on the CDP Runtime domain in each page and worker. Pages
  can detect that, so deviceandbrowserinfo.com reported a bot and Cloudflare's
  challenge never cleared.
- **Windowed, not headless.** Headless Chrome differs from desktop Chrome in its
  User-Agent inside workers, client hints, and timing. Stealth scripts that cover
  this up get caught by checks such as CreepJS. Windowed Chrome has nothing to
  cover up.
- **Google Chrome, not Chromium.** Detectors such as rebrowser's flag a Chromium
  build as Chrome for Testing, because its client hints don't name Google Chrome.
- **WebGL off.** Chrome also leaves WebGL off on a machine with no usable GPU. Each
  way of turning it on in a container gets caught by a real anti-bot vendor. Akamai
  catches Mesa's software renderer, DataDome catches the same renderer under a real
  GPU's name, and Cloudflare catches Chrome's SwiftShader. With WebGL off, all three let
  Chrome through.
- **Reserved taskbar.** The display reserves 40 pixels for a taskbar, and the window
  fits the rest. A screen whose whole area is free, with a window as large as the
  screen, is how headless Chrome looks.
- **Real pointer.** `pointer.js` moves the real X11 pointer with xdotool over each
  page as it opens and scrolls a little, because behavior checks score a page that
  loads with no pointer movement as a bot. It also clicks Cloudflare's Turnstile
  checkbox ("Verify you are human") when a site asks for it. A click sent over
  DevTools reports matching screen and page coordinates, a known automation signal,
  so this click is real input too.
- **Relay.** Chrome listens only on loopback when it has a window, so a small relay
  (`relay.js`) exposes its DevTools port to CRW.
- **Timezone.** Chrome and Camoufox get this machine's timezone from `up.sh`,
  because a detector can compare the timezone with the IP address's location.

## Camoufox tier

`docker/camofox` adds a camofox-browser plugin that clicks Cloudflare's Turnstile
checkbox, which Cloudflare shows Camoufox where it lets Chrome straight through.
The click is a real X11 click, made with xdotool on Camoufox's virtual display,
because Playwright's synthetic clicks don't reach the checkbox's cross-origin
iframe. camofox-browser's crash reporter is off
(`CAMOFOX_CRASH_REPORT_ENABLED=false`).

## Patches to CRW

The patches in `patches/crw/` apply in name order, and later patches can build on
earlier ones.

### `camoufox-after-chrome.patch`

Lets Camoufox follow Chrome in auto mode (`include_in_auto`) when the mode is
`chrome`, not only `auto`.

### `camoufox-wait-for.patch`

Makes the Camoufox renderer honor `waitFor`. Without `waitFor`, the renderer waits
up to 6 seconds for the page to settle, using camofox-browser's own readiness
check, instead of reading the page the moment navigation returns.

### `camoufox-wait-loading.patch`

Reads a page again if it still looks like it's loading, within the time that
Camoufox already allows for a challenge to clear. On a busy machine, the 6-second
wait could run out while the document was still arriving, and eBay's empty page
shell came back as a successful scrape.

### `cdp-stealth.patch`

- Stops turning on the CDP Runtime domain, which CRW never needed.
- Makes each section of the injected stealth script patch only a value that's
  missing or wrong, so desktop Chrome runs it as a no-op. Removes the WebGL spoof,
  which claimed a macOS GPU, Intel Iris OpenGL Engine, under a Linux User-Agent.
- Skips the User-Agent override when Chrome already sends that User-Agent, because
  an override without client-hint metadata empties `navigator.userAgentData`.
- Reports the real page's HTTP status once an anti-bot challenge clears, instead
  of the challenge's 403, and stops waiting. CRW used to take Cloudflare's telemetry
  script, which every Cloudflare page carries, for a challenge still running.
- Waits after a page loads until the network has been quiet for a second, within 1
  to 4 seconds, so scripts that check the browser after load have written their
  result.
- Waits for Kasada's challenge, an HTTP 429 that solves itself and reloads, as it
  does for Cloudflare's.
- Answers JavaScript dialogs (`alert`, `confirm`) after 0.7 seconds. CRW left them
  open, which froze the page until the render timed out.
- Adds `CRW_RENDERER__CHROME_OUTBOUND_CHECK`.

### `challenge-markers.patch`

Fixes how CRW tells a block page from a page that loaded, which decides whether it
tries the next tier:

- PerimeterX's sensor tag and Cloudflare's telemetry script, which sit on pages
  that loaded, no longer count as blocks. On Walmart, Wayfair, and Trulia, they had
  sent every scrape on to Camoufox for nothing.
- CRW recognizes Akamai's block page as adidas serves it ("Reference Error: …"),
  Akamai's interstitial (`sec-if-cpt`, a proof of work that reloads into the page),
  and Reddit's "Prove your humanity" captcha. Before, these came back as successful
  scrapes of the block page.
- Both browsers wait for Akamai's interstitial to clear, as they do for
  Cloudflare's and Kasada's.
- CRW reports the real page's status after AWS WAF's challenge, a 202, clears.

### `render-browser-first.patch`

Sends a page to the browser first. Upstream fetched every page once over plain HTTP
before rendering it, to check its media type. That request is a bot's TLS
handshake from your IP address. Akamai answered it with an IP-reputation block on
Kohl's, Marriott, and Apartments.com, and then blocked Chrome on the latter two.

HTTP is now the fallback, through the `impersonated-http` client, when both
browsers are blocked or fail, and for files:

- A URL that names a file (`.pdf`, `.docx`, `.zip`, images, media) goes straight to
  the client.
- Chrome hands over a PDF or download that it opens from any other URL.
- When the fallback gets a block page too, the scrape fails as blocked instead of
  returning that page.
- When both browsers get Akamai's block page, there is no fallback, and the scrape
  fails as blocked right away. An HTTP client has none of the sensor cookies that
  Akamai's wall wants, and one more non-browser request is what Akamai holds against
  your IP address.

### `render-js-false-hop.patch`

Gives a `renderJs: false` scrape the second request the README describes. CRW
answered it with plain HTTP alone, so a site that turns the plain client's TLS
handshake away blocked every such scrape. JB Hi-Fi answered a 429 to plain HTTP
and a 200 to the `impersonated-http` tier, every time
([#23](https://github.com/swack-tools/crw-build-aio-mcp/issues/23)). Upstream's
auto mode makes that hop and its `renderJs: false` path didn't.

When plain HTTP gets a block page, a 401, 403, 429 or 503, or a transport
failure that a Chrome TLS fingerprint can get past, the scrape makes one more
request through the `impersonated-http` client and returns that answer unless
it's a block too. No browser runs in either case.

The hop keeps two rules of its own, because nothing runs after it. Auto mode
skips the hop on a vendor's JavaScript challenge, since Chrome follows and
clears it; here the hop is the one chance the scrape has, and Cloudflare serves
JB Hi-Fi's product pages with a challenge to the plain client and without one to
the `impersonated-http` client. Auto mode also rejects a page that needs
JavaScript, since Chrome would do better; here a request that set
`renderJs: false` asked for that page as it is.

### `revisit-walls.patch`

When Chrome's first visit gets a block page, it reloads once after a short pause,
as a person would. Chrome waits out a challenge that solves itself instead. Some anti-bot systems turn a first visit away while setting a cookie that lets
the next one through. From a fresh profile, Reddit shows a captcha the first time,
and its automatic check passes on the reload.

A page also counts as a block by its HTTP status, because eBay's first answer to a
fresh profile is a 403 that only reads "Something went wrong." A 429 doesn't count
on its status alone, because another request right away doesn't help.

### `status-not-found.patch`

Treats a 404 or 410 as the answer, so a dead link fails as
`Target returned 404 Not Found`, as it does with `renderJs: false`. Upstream treats
those statuses as possible blocks and tries the next browser. Camoufox reported
every page as a 200, so a dead link came back as a successful scrape of its "Page
not found" page.

A block page served with a 404 still goes to the next browser. The Camoufox tier
now passes on a 404 or 410 from camofox-browser's navigation. Other statuses still
read as 200, because a challenge may have cleared after them.

### `xhr-prose-only.patch`

One of CRW's fallbacks for a page whose text loads later builds markdown from long
strings in the JSON that the page fetched. It took any string of 120 characters or
more. Anti-bot sensor replies (PerimeterX's base64 payload), script bundles, and
stylesheets that pages fetch as JSON became the whole markdown of chegg.com and
homedepot.com, which read as a block page.

The fallback now keeps only strings that read as prose. It judges the text that a
reader sees, with HTML tags dropped and entities such as `&nbsp;` or `&#x4E2D;`
decoded. A string qualifies if it has little code punctuation and either of the
following:

- At least eight words, with none over 60 characters.
- Mostly the script's letters, for languages written without spaces, such as
  Chinese, Japanese, and Thai.

### `zz-runtime-apt-upgrade.patch`

CRW's runtime base is pinned by digest, so its layer now runs `apt-get upgrade` to
take Debian's security fixes. CI passes the ISO week as `REFRESH`, which reruns that
layer past the build cache once a week.

## Ports

CRW is published on `127.0.0.1:$CRW_HOST_PORT`, which defaults to 3000. If the port
is busy, `up-stealth` offers the next free one and saves the choice to `.env`.

## Client connections

`bin/crw-mcp` runs in proxy mode, pointed at the stack with `CRW_API_URL`.

- Codex gets `tool_timeout_sec = 300`, because Camoufox scrapes can outlast its
  60-second default.
- Every config file edit is shown as a diff and backed up first.
