# CI and releases

GitHub Actions publishes multi-architecture images (amd64 and arm64) to Docker Hub
as `<DOCKERHUB_USERNAME>/crw-config-<NAME>`, signed with cosign.

## Workflows

| Workflow | When it runs | What it does |
|---|---|---|
| `images.yml` | When `nightly.yml` or `release.yml` calls it, or by hand | Builds each architecture on a native runner and pushes by digest, and then joins the digests into multi-architecture tags and signs them. |
| `nightly.yml` | Daily | Rebuilds what changed upstream and tags `nightly` and `nightly-YYYYMMDD`. |
| `test.yml` | On pull requests and pushes to `main` | Applies `patches/crw/` to CRW's head and runs the unit tests that they add (`scripts/test-patches.sh`), such as eBay's reload on a 403 and Camoufox reading eBay's empty shell again. It uses only mock servers, no live sites. |
| `docs.yml` | On pull requests and pushes to `main` that change docs | Runs `scripts/lint-docs.sh`, which checks the docs against the Google style with Vale. |
| `release.yml` | On a `v*` tag | Tags the images `<VERSION>` and `latest`. Builds, signs, and notarizes the disk image (`crw-mcp` plus a compose bundle pinned to those images), and then publishes the draft release. |

## What gets rebuilt

- **Unchanged images.** `scripts/ci-plan.sh` pins each upstream to its current
  commit. Each image gets a key from its own inputs: its upstreams' commits, their
  `patches/`, its `docker/<NAME>/` files, and the shared bake recipe. The image is
  pushed as `src-<KEY>`. A run whose key already exists only retags, so a change to
  one image rebuilds only that image.
- **Camoufox.** CI compiles it only when its build inputs change, on a free x86_64 runner,
  in about 2 hours and 10 minutes per architecture. The key (`camoufox_key` in
  `scripts/lib.sh`) hashes upstream's `browser/` tree minus its tests,
  `patches/camoufox/`, and `build-camoufox.sh`. Upstream's README, docs, and Python
  and TypeScript libraries change most days and don't trigger a compile. The zips
  are kept on Docker Hub as `crw-config-camoufox-dist:<KEY>-<ARCH>`. A manual Nightly
  or Images run with `force_camoufox` compiles anyway, to time the ccache, and leaves
  a zip already published for that key in place.
- **CRW build cache.** CRW's cargo-chef dependency layer is cached per architecture
  in `crw-config-buildcache` on Docker Hub, so a CRW change that leaves its
  dependencies alone skips recompiling them.
- **Chrome.** The `chrome-stealth` key includes Google's current Chrome stable
  version, so the nightly build picks up each Chrome release.

## Secrets

The workflows use the swack-tools organization secrets `DOCKERHUB_USERNAME`,
`DOCKERHUB_TOKEN`, and `APPLE_*`. Without the Apple secrets, a release still ships,
unsigned.

## Create a release

On an up-to-date `main`, run the following command, using your version number:

```sh
just release 0.1.0
```

The recipe creates a signed tag and a draft GitHub release. `release.yml` does the
rest. Its notes come from `.github/release-notes.md`, and the disk image's README
comes from `release/README.txt`.
