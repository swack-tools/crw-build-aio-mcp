# Build from source

The build scripts clone the upstream repositories and compile CRW, Camoufox,
camofox-browser, and SearXNG. Chrome is Google's stable release from Google's
apt repository. This project is developed on Apple silicon with OrbStack.

For a prebuilt install on a Mac, see [Install from a release](install.md).

## Before you begin

Install the following:

- Docker with buildx 0.19 or later. `just build-all` also needs a containerd
  image store.
- `just`, `git`, `curl`, `openssl`, `lsof`, and `column`.
- `python3` 3.11 or later.
- `cargo`, for the native MCP binary.
- The `claude`, `codex`, and `agy` CLIs, if you use the recipes for those
  clients.

## Build and start the stack

1. If you want to skip the hours of compiling Camoufox, add the following line
   to `.env` before the first build. The build then fetches the zip that CI built,
   when CI has one for the same sources.

   ```sh
   CAMOUFOX_DIST_REGISTRY=docker.io/swackhamer/
   ```

1. Clone the sources, build the images, and start the stack. The first run takes
   hours if it compiles Camoufox.

   ```sh
   just up-stealth
   ```

1. Pin a scrape to each tier, and then run the bot checks and an eBay listing
   with default settings:

   ```sh
   just test-stealth
   ```

1. Register the MCP server, and install CRW's agent skills, with Claude, Codex,
   and Antigravity:

   ```sh
   just install
   ```

   To register with only one client family, use `just install-claude`,
   `just install-codex`, or `just install-antigravity`.

1. Run the same check through an MCP client:

   ```sh
   just test-stealth-claude
   ```

   For the other clients, use `just test-stealth-codex` or
   `just test-stealth-antigravity`.

Every install and uninstall recipe prints the exact commands and config diffs,
and then asks `Apply these changes? [y/N]`. Add `--dry-run` to only print them,
or add `--yes` to skip the question. A run without a terminal needs `--yes`.

### Run with less memory

To start the stack without Camoufox, run the following:

```sh
just up-minimal
```

The minimal stack builds and runs CRW, stealth Chrome, and SearXNG. It skips the
Camoufox compile and keeps two Chrome tabs open instead of four. On a Mac, it
uses about 700 MB, against about 1.1 GB for the full stack.

The trade-off is that nothing renders a page that Chrome is blocked on. The
full stack retries that page in Camoufox. The minimal stack fails the scrape as
`anti_bot`, and a request that sets `renderer: camoufox` is rejected. The
Cloudflare challenge checks in `just test-stealth` need Camoufox, so they fail
on the minimal stack.

The minimal stack's settings are in `docker-compose.minimal.yml`, which
`scripts/up.sh --minimal` lays over `docker-compose.yml`. To change the number
of Chrome tabs, set `CRW_CHROME_POOL_SIZE` in `.env`. To bring Camoufox back,
run `just up-stealth`.

### Allow tools in headless mode

Headless `agy -p`, which `just test-stealth-antigravity` uses, denies MCP tools
without an allow rule. Add `mcp(crw/crw_scrape)` to `permissions.allow` in
`~/.gemini/antigravity-cli/settings.json`, or add `mcp(crw/*)` for every CRW
tool. The install recipes don't add this rule, because it's your permission
setting.

## Build on Linux

The build and the stack also run on Linux. They were checked on Ubuntu on arm64.
The following differs from a Mac:

- `column` comes from `bsdextrautils` on Debian and Ubuntu:

  ```sh
  sudo apt install just bsdextrautils lsof
  ```

  Without `lsof`, a busy port goes unnoticed until `compose up` fails on it.

- If a build stops at `apt-get` with `Invalid cross-device link`, Docker's own
  builder has hit a limit of overlay2 on btrfs. Build with a container builder
  instead, which `just` picks up from the environment:

  ```sh
  docker buildx create --name crw-build --driver docker-container
  BUILDX_BUILDER=crw-build just up-stealth
  ```

- The MCP recipes register Claude Code and Codex. They skip Claude Desktop, which
  is macOS only.

## Recipes

Run `just` with no recipe to list them all. Each recipe that builds runs `fetch`
first, so a missing upstream is cloned.

### Run the stack

| Recipe | Description |
|---|---|
| `up-stealth`, `run-stealth` | Build, choose a host port, run `compose up --wait`, and print the live renderers. This is the full stack, with Camoufox as the fallback when Chrome is blocked. |
| `up-minimal` | Build and start the stack without Camoufox. It uses less memory and skips the Camoufox compile, but a page that Chrome is blocked on fails instead of falling back. See [Run with less memory](#run-with-less-memory). |
| `down` | Stop the stack. |
| `ps` | Show the status of each service. |
| `logs [SERVICE...]` | Follow the logs of every service, or of the services you name. |
| `caps` | Print `/v1/capabilities`, which lists the live renderers. |

### Build

| Recipe | Description |
|---|---|
| `build` | Build every image for this machine's architecture. |
| `build-arm64`, `build-x86` | Build every image for one architecture. |
| `build-all` | Build multi-architecture images for both architectures. This compiles Camoufox twice, which takes hours. |
| `push` | Run `build-all`, and then push to `$REGISTRY`. |
| `build-camoufox [ARCH]` | Build only the Camoufox zip in `~/.crw/dist`. Set `FORCE=1` to rebuild it. |
| `build-mcp` | Build the native `bin/crw-mcp`, a proxy-only build, from the patched checkout. |
| `fetch [NAME...]` | Clone any missing upstream into `~/.crw/src`. |
| `update` | Fast-forward every upstream, and then run `build`. |

### Register with MCP clients

Each of these recipes takes `--dry-run` and `--yes`.

| Recipe | Description |
|---|---|
| `install` | Register the MCP server and install CRW's agent skills in Claude, Codex, and Antigravity. |
| `install-claude`, `install-codex`, `install-antigravity` | Register with one client family. |
| `uninstall` | Remove the MCP server and the skills from every client. |
| `uninstall-claude`, `uninstall-codex`, `uninstall-antigravity` | Remove them from one client family. |
| `install-skills [TARGET]`, `uninstall-skills [TARGET]` | Install or remove only the skills. `TARGET` is `claude`, `codex`, `antigravity`, or `all`, the default. |

### Test

| Recipe | Description |
|---|---|
| `test-stealth` | Pin a scrape to each tier over HTTP, and then run the bot checks, an eBay listing, and three DataDome sites with default settings. |
| `test-stealth-claude`, `test-stealth-codex`, `test-stealth-antigravity` | Run the same check through an MCP client. |
| `test-patches` | Run the offline unit tests that the CRW patches add. Needs `cargo`. CI runs it on every pull request. |
| `lint-docs [FILE...]` | Check the docs against the Google style with Vale. |

### Release

| Recipe | Description |
|---|---|
| `bundle [PREFIX] [TAG]` | Assemble the disk image's contents from local images into `build/bundle`, to test `install.sh`. |
| `release VERSION` | Create the signed tag `vVERSION` and a draft GitHub release. CI builds and publishes it. |

## Settings

Set these in `.env`. The file `.env.example` lists more of them.

| Setting | Description |
|---|---|
| `CRW_HOME=/path` | Keep the upstream clones and Camoufox zips somewhere other than `~/.crw`. |
| `<NAME>_REF` | Check out another ref of an upstream, such as `CAMOUFOX_REF=v152.0.4-beta.28`. |
| `SRC_<NAME>=/path` | Use an existing checkout instead of cloning. |
| `CAMOUFOX_DIST_REGISTRY=docker.io/<USER>/` | Fetch the Camoufox zip that CI built from the same inputs. Defaults to `REGISTRY`. |
| `CAMOUFOX_PULL=0` | Always compile Camoufox. |
| `CAMOUFOX_CCACHE=<DIR>` | Keep ccache in a directory instead of a Docker volume. |
| `REGISTRY=docker.io/<USER>/` | Set where `just push` pushes to. |
| `CRW_HOST_PORT` | Set the host port for CRW. The default is 3000. |
| `CRW_CHROME_POOL_SIZE` | Set how many Chrome tabs `just up-minimal` keeps open. The default is 2. |

To force a Camoufox compile for one run, set `FORCE=1`.

If your checkout is from before the sources moved out of this folder, you can
move them instead of cloning and building again:

```sh
mkdir -p ~/.crw && mv src dist .stamps ~/.crw/
```

## Troubleshoot a failing browser tier

Camoufox `main` can be ahead of the version that camofox-browser pins. If the
`camoufox` tier fails, set `CAMOUFOX_REF` to the pinned tag from
`~/.crw/src/camofox-browser/Dockerfile`, and then run `just update`.
