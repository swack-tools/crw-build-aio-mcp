# crw-build-aio-mcp

Run [CRW](https://github.com/fastcrw/crw), the Firecrawl-compatible scraper, locally with all three of its stealth tiers on at once, built from upstream source:

| tier | what it is | where it runs |
|---|---|---|
| `chrome` via `--profile stealth` | browserless Chromium with stealth patches | `chrome-stealth` container |
| `impersonated-http` | no browser; mimics Chrome's TLS/HTTP2 fingerprint | inside crw |
| `camoufox` | Camoufox, a fingerprint-spoofing Firefox fork, behind the camofox-browser REST server | `camofox` container |

No prebuilt app images are pulled. The scripts clone the upstream repos and compile crw, Camoufox (Firefox), camofox-browser, browserless, SearXNG and lightpanda.

## Install a release (no build)

Each [release](https://github.com/swack-tools/crw-build-aio-mcp/releases) has a signed, notarized disk image for Apple Silicon Macs.
1. Start Docker (OrbStack or Docker Desktop).
2. Open the disk image and run `/Volumes/crw-build-aio-mcp/install.sh` in Terminal.

It pulls the prebuilt images from Docker Hub, starts the stack and registers the MCP server, asking before each config change. Afterwards, `crw-aio help` manages the stack. Images are also tagged `nightly`, rebuilt each night from upstream heads.

## Build it yourself

```sh
just up-stealth                     # first run clones + builds everything (Camoufox takes hours)
just test-stealth                   # pin a scrape to each tier, then print a bot-check report
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
  - Upstream Dockerfiles that build `FROM` a registry image (`ghcr.io/browserless/base`, `searxng/base:*`) get bake targets built here instead, wired in through `contexts`.
  - `scripts/prep-sources.sh` patches two upstream Dockerfiles: lightpanda builds our checkout instead of `git clone`-ing, and camofox-browser installs our Camoufox zip instead of downloading a release. The script fails loudly if upstream changes the lines it patches.
- **Compose:** `compose.override.yml` is layered on crw's own `docker-compose.yml` and `docker-compose.stealth.yml`, so upstream's settings and hardening still apply.
  - It swaps in the local images and adds the `camofox` service.
  - It points crw at that service with `CRW_RENDERER__CAMOUFOX__*`, including `include_in_auto=true`.
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
- **Secrets:** the swack-tools org secrets `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` and `APPLE_*` (the same Developer ID setup as update-all). Without the Apple secrets, a release still ships, unsigned.

To release, run `just release 0.1.0` on an up-to-date `main`.

## What is still prebuilt

Building these from source is out of scope: official base images (debian, ubuntu, node, rust, alpine), Playwright's Chromium (browserless), lightpanda's `libc_v8.a`, Mozilla's build toolchains, the Camoufox font bundle, uBlock Origin, yt-dlp, and packages from distro, npm, cargo and PyPI registries.

## Notes

- **Version risk:** Camoufox `main` can be ahead of the version camofox-browser pins. If the camoufox tier fails, set `CAMOUFOX_REF` to the pinned tag (see `src/camofox-browser/Dockerfile`) and run `just update`.
- **Crash reports:** camofox-browser's crash reporter is off (`CAMOFOX_CRASH_REPORT_ENABLED=false`).
- **Licenses:** browserless is SSPL, and crw and SearXNG are AGPL. Building and running them locally is fine; publishing the images (`just push`) or offering the stack as a service carries their terms.
