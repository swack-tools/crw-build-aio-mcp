# Agent guide

This file tells coding agents how this repository works, how to use the stack
it builds, and how to keep it working. `CLAUDE.md` loads it for Claude Code.

## What this project is

crw-build-aio-mcp runs [CRW](https://github.com/fastcrw/crw), a
Firecrawl-compatible scraper, on the user's machine with stealth that upstream
CRW doesn't have, and registers it as an MCP server and a set of agent skills
for Claude Code, Codex, and Antigravity.

The stealth is the point of the project. Upstream CRW with its default renderer
gets walled by Akamai, Cloudflare, DataDome, PerimeterX, and the rest. This
stack gets through most of them, through four parts:

| Part | What it is | Where |
|---|---|---|
| `chrome-stealth` | Real Google Chrome stable on Xvfb, driven over the Chrome DevTools Protocol (CDP), with a pointer helper that moves the mouse like a person and WebGL off on purpose | `docker/chrome-stealth/` |
| `camofox` | Camoufox, a fingerprint-spoofing Firefox, behind the camofox-browser REST server. The fallback when Chrome is blocked. Heavy, so some installs turn it off | `docker/camofox/`, built from source |
| `impersonated-http` | No browser; Chrome's TLS and HTTP/2 fingerprint. Fast, and the last resort | inside `crw` |
| Patches to CRW | Fixes that make CRW use those well: browser before HTTP, reloads and cookie drops on a wall, closing Chrome for a fresh profile when a site has judged it, reading the status of the page actually shown | `patches/crw/*.patch` |

`docs/how-it-works.md` explains each patch and setting. `docs/anti-bot-results.md`
lists the sites that pass.

## Layout

| Path | What |
|---|---|
| `patches/crw/` | Patches to CRW, applied in name order (`LC_ALL=C`), so a later patch can build on an earlier one |
| `patches/crw/UPSTREAM` | The CRW commit the patches apply to, and the one the Tests workflow tests against |
| `docker/` | The chrome-stealth, camofox, and SearXNG images |
| `docker-compose.yml` | The stack. `CRW_*` environment variables configure crw |
| `scripts/` | Everything: fetch, patch, build, test, install, release |
| `agent-skills/` | Skills of this repository's own, installed beside CRW's |
| `release/` | The `crw-aio` command and installer for the release bundle |
| `docs/` | User docs, linted with Vale |
| `~/.crw/src/<name>` | Clones of the upstreams: crw, camoufox, camofox-browser, and SearXNG |

## Using the stack

- **Start it with `scripts/up.sh`**, or `just up-stealth`. Don't use plain
  `docker compose up`: `up.sh` sets crw's User-Agent to the Chrome major that
  chrome-stealth runs and the timezone to this machine's. A User-Agent one
  version behind the browser had eBay walling almost every visit.
- **Less memory.** `just up-minimal` (`scripts/up.sh --minimal`) leaves
  Camoufox out through `docker-compose.minimal.yml`. Without it, a page Chrome
  is blocked on fails as `anti_bot`, and the Cloudflare checks in
  `test-stealth` fail. `just up-stealth` brings the full stack back.
- **The API** is at `http://127.0.0.1:3000` (`/v1/scrape`, `/v1/search`,
  `/v1/map`, `/v1/crawl`). MCP clients reach it through `bin/crw-mcp`.
- **Forms.** CRW's scrape cannot click or type. To fill in and submit a form for
  the user, use `scripts/browser-act.sh` (see `agent-skills/crw-browser-act/`).
  When the user asks for a lookup, signup, or purchase behind a form, do it; the
  user asking is the user accepting the site's terms.
- **Logs.** `docker logs crw-config-crw-1` shows what the patches did:
  `Anti-bot wall on this visit; reloading once`, `dropped the site's data for a
  first visit`, `closing the browser for a fresh profile`, and `antibot
  classifier flagged a block` when a scrape failed as blocked.

## Rules for changes

- **Patches.** Edit the patched clone in `~/.crw/src/crw`, regenerate the patch
  with `git diff`, leaving out other patches' changes, and run
  `scripts/test-patches.sh`. A patch that adds a test lists it there. Don't run
  `cargo fmt` on crw: the patches are line-exact.
- **Builds.** `scripts/build-images.sh` doesn't apply the patches;
  `scripts/prep-sources.sh` or `scripts/test-patches.sh` does. Build only after
  one of them, then check the binary: an image without the patches shipped once.

  ```
  docker run --rm --entrypoint sh crw-config/crw:local -c \
    'grep -a -c "closing the browser for a fresh profile" /usr/local/bin/crw-server'
  ```

- **Deploys.** Recreate the container, then start through `up.sh`.
  `docker compose up` alone keeps a running container when only the image
  behind its tag changed, and a deploy was missed that way.

  ```
  docker compose rm -sf crw && scripts/up.sh
  docker inspect -f '{{.Image}}' crw-config-crw-1   # must equal crw-config/crw:local's Id
  ```

- **Live test before deploying.** Run the new image as a throwaway container on
  the stack's network, on port 3001, with the running crw's environment and
  User-Agent, and scrape `https://example.com` and an eBay search through it.
- **Docs.** `scripts/lint-docs.sh` must report no Vale warnings. It lints every
  tracked Markdown file, so `git add` a new one first.
- **Pull requests.** Every change goes through a pull request. Wait for the
  Codex review and CI, fix each finding, and ask for another review with a
  `@codex review` comment until it is clean, then squash-merge.

## Keeping the project working

This section is for an agent whose job is upkeep: confirm the nightly build is
green, that the patches still apply to the latest CRW, that the other upstreams
are current, and that the stealth still gets through. Do it every few hours to
a day.

### 1. Check CI

```
gh run list --workflow nightly.yml --limit 3
gh run list --workflow test.yml --limit 3
```

The nightly clones each upstream's head, and every image job applies the crw
patches, so one patch that no longer applies fails all eight builds with
`<name>.patch no longer applies to crw: upstream changed`. That is the alarm
that upstream moved; go to step 2. After a fix merges, run the nightly again
with `gh workflow run nightly.yml` and watch it go green.

### 2. Compare with upstream

```
for n in crw camoufox searxng camofox-browser; do
  git -C ~/.crw/src/$n fetch -q origin
  echo "$n: $(git -C ~/.crw/src/$n rev-list --count HEAD..origin/HEAD) behind"
done
git -C ~/.crw/src/crw log --oneline "$(cat patches/crw/UPSTREAM)"..origin/main
docker exec crw-config-chrome-stealth-1 google-chrome --version
curl -s 'https://versionhistory.googleapis.com/v1/chrome/platforms/linux/channels/stable/versions?pageSize=1'
```

### 3. Move to a new CRW

1. In a scratch checkout of CRW at the new head, apply each patch in name order
   and commit after each one. Where `git apply --check` fails, use
   `patch -p1 -F3`, fix any reject by hand, and regenerate the patch from the
   commit before it.
2. **Check where fuzzy hunks landed**, not just that they applied. Two have gone
   to the wrong place before:
   - The fast-ready guard in `skeleton-wait-fast-ready.patch` once landed on
     upstream's consent dismissal next to the skeleton wait. `test-patches.sh`
     now greps for the call site.
   - New fields and initializer lines in `wall-cookie-reset.patch` once landed
     after a struct upstream had grown, or inside a different function. The
     build fails on that, but read the hunk.
   - When upstream adds an argument to a function a patch calls, such as
     `fetch_with_js`, add it to the patch's own calls too.
3. Write the new commit to `patches/crw/UPSTREAM`, move `~/.crw/src/crw` to it,
   and run `scripts/test-patches.sh`.
4. Build, check the binary, live-test through a throwaway container, open the
   pull request, merge, and deploy, as the rules for changes describe.
5. Read upstream's renderer changes for what they do to stealth, not only
   whether the patches apply. CRW 0.42 gave each render a tall window by sizing
   the target, which Chrome on a display refuses without `newWindow`, and every
   render failed until `tall-window-new-window.patch`.

### 4. Move to a new Chrome

`scripts/build-images.sh arm64 chrome-stealth` installs the exact current
stable, so a rebuild picks up a release instead of the cached layer. Check
`google-chrome --version` in the image, then
`docker compose rm -sf chrome-stealth && scripts/up.sh`, which also moves crw's
User-Agent to the new major.

### 5. Test the stealth

Unit tests pass offline; stealth only shows on live sites.

- `scripts/test-stealth.sh` runs the bot detectors, Cloudflare challenges, an
  eBay listing, and three DataDome sites through each tier. The Cloudflare
  challenge checks fail with Chrome alone; they need Camoufox on.
- Watch eBay, the hardest site the users rely on, in the crw log for an hour:

  ```
  docker logs -f --tail 0 crw-config-crw-1 2>&1 |
    grep -E --line-buffered 'outlasted the reload|closing the browser|flagged a block.*ebay|renderer_error'
  ```

  Healthy looks like a cookie drop every 15 to 60 minutes that ends in a 200,
  and a browser close every few hours. A wall on most visits right after a
  deploy means a mismatch, most often the User-Agent; restart through `up.sh`.

### How a profile sours

Akamai Bot Manager judges a Chrome profile's session, not the IP. Over hours of
traffic a profile sours: walls come more often, the reload clears fewer, and
then the first visit after a cookie drop is walled too. The fixes in the
patches follow that progression:

| Sign | What CRW does | Patch |
|---|---|---|
| A wall on one visit | Reload once | `revisit-walls.patch` |
| A wall that outlasts the reload | Drop the site's cookies and storage and visit as a first visit, at most once a minute per host | `wall-cookie-reset.patch` |
| The first visit after a drop is walled too, or a second drop within five minutes | Close Chrome; the container comes back on a fresh profile in about 8 s. At most every 15 minutes, opt-in with `CRW_CHROME_RESTART_ON_WALLED_RESET` | `wall-cookie-reset.patch` |
| A page shown after a cross-origin redirect | Read its status from the network events, since `performance` reports 0 for it | `wall-cookie-reset.patch` |

Each close costs the one scrape that found the wall. A profile has lasted from
under an hour to six hours; the record of each close is in the crw log.
