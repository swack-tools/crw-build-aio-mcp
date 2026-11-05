# Install from a release

Each [release](https://github.com/swack-tools/crw-build-aio-mcp/releases) has a
disk image for Apple silicon Macs. The disk image contains the `crw-mcp` binary,
a Docker Compose bundle pinned to that release's images, an installer, and the
`crw-aio` command. You don't compile anything on your machine.

On Linux, or to compile the images yourself, see
[Build from source](build-from-source.md).

## Before you begin

Make sure that you have the following:

- macOS on Apple silicon.
- Docker running, either OrbStack or Docker Desktop, with Docker Compose v2.
- About 10 GB of free disk space for the images.
- `python3`. If you don't have it, run `xcode-select --install`.

## Install

1. Start Docker.
1. Download `crw-build-aio-mcp-VERSION-macos-arm64.dmg` from the
   [latest release](https://github.com/swack-tools/crw-build-aio-mcp/releases/latest),
   and then open it.
1. In Terminal, run the installer:

   ```sh
   /Volumes/crw-build-aio-mcp/install.sh
   ```

   To skip the confirmation for the MCP changes, add `--yes`.

The installer does the following:

1. Copies the bundle to `~/Library/Application Support/crw-build-aio-mcp`.
1. Links the `crw-aio` command into `~/.local/bin`. If that folder isn't on your
   `PATH`, add it, or run `crw-aio` by its full path.
1. Pulls the images from Docker Hub and starts the stack on
   `http://127.0.0.1:3000`. If that port is busy, it asks to use the next free
   one.
1. Registers the `crw` MCP server with Claude Code, Claude Desktop, the Codex
   command-line tool, ChatGPT desktop, and Antigravity, if you have it. It shows
   each config change and asks before applying it.
1. Installs CRW's agent skills into Claude Code, the Codex command-line tool, and
   Antigravity. They teach the agent which tool a task needs: search, scrape,
   map, crawl, parse, or extract.

Claude Desktop reads its config only at launch, so if it's running, the installer
quits it before the edit and reopens it afterward. It warns you about this first. Run the
installer from Terminal, not from inside Claude.

After the installer finishes, restart ChatGPT desktop and Antigravity to pick up
the change.

### If macOS blocks `crw-mcp`

Release builds are signed and notarized when the release's signing secrets are
available. The release notes say so. If a release says that it isn't signed and
macOS blocks `crw-mcp`, remove the quarantine attribute:

```sh
xattr -dr com.apple.quarantine ~/Library/Application\ Support/crw-build-aio-mcp
```

## Check the install

To scrape through each tier and get a bot-check report, run the following
command:

```sh
crw-aio test
```

## Manage the stack

| Command | Description |
|---|---|
| `crw-aio up` | Start the stack. Pulls the images on the first run. |
| `crw-aio down` | Stop the stack. |
| `crw-aio update` | Pull this release's images again and restart. |
| `crw-aio status` | List the containers. |
| `crw-aio logs [SERVICE...]` | Follow the logs of `crw`, `camofox`, `chrome-stealth`, or `searxng`. |
| `crw-aio test` | Scrape through each stealth tier and report on bot checks. |
| `crw-aio mcp install [TARGET] [--dry-run] [--yes]` | Register the MCP server and install the skills. |
| `crw-aio mcp uninstall [TARGET] [--dry-run] [--yes]` | Remove the MCP server and the skills. |
| `crw-aio skills install [TARGET] [--dry-run] [--yes]` | Install only the skills. |
| `crw-aio skills uninstall [TARGET] [--dry-run] [--yes]` | Remove only the skills. |
| `crw-aio help` | Print this list. |

`TARGET` is `claude`, `codex`, `antigravity`, or `all`, which is the default.

The port is `CRW_HOST_PORT` in
`~/Library/Application Support/crw-build-aio-mcp/.env`.

## Upgrade

Run `install.sh` from a newer disk image. It replaces the installed bundle and
keeps your `.env`.

## Uninstall

Run the following command:

```sh
crw-aio uninstall
```

After you confirm, it removes the MCP entries, stops the stack, and deletes the
installed folder. The images stay in Docker, and the command prints how to
remove them.

## Verify an image signature

Every image is signed with cosign. The notes of each release list the images and
this check:

```sh
cosign verify docker.io/swackhamer/crw-config-crw:VERSION \
  --certificate-identity-regexp '^https://github.com/swack-tools/crw-build-aio-mcp/\.github/workflows/images\.yml@' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Replace `VERSION` with the release version, such as `0.0.3`.
