# Contributing

Thanks for helping out. This page explains what you need to send a change.

## Sign the license agreement

Before your first pull request can be merged, you need to sign the
[Contributor License Agreement](CLA.md). The CLA bot comments on your pull request
with the sentence to post. Signing once covers all your future contributions.

The CLA lets the maintainer accept your change and offer the project under other
terms later, such as dual licensing. You keep your copyright, and your change
always stays available under the [GNU AGPL v3 or later](LICENSE).

## Set up

To build and run the stack, follow [Build from source](docs/build-from-source.md).
Before you change stealth behavior, read [How it works](docs/how-it-works.md).

## Change a patch to CRW

Fixes to upstream source live in `patches/<NAME>/*.patch`. `scripts/prep-sources.sh`
applies them to the clones in `~/.crw/src` in name order, and a later patch can
build on an earlier one.

1. Edit the patched clone in `~/.crw/src/<NAME>`.
1. Regenerate the patch with `git diff` in the clone, leaving out the changes that
   belong to other patches.
1. Run `scripts/prep-sources.sh`. It reverts the patches and reapplies them in
   order, and it stops if one no longer applies. A warning about stashed changes
   means that the regenerated patch doesn't cover all your edits.
1. If the patch adds tests, add them to `scripts/test-patches.sh`.

The patches apply to the CRW rev in `patches/crw/UPSTREAM`, and the Tests
workflow checks them there. To move the stack to a newer CRW, fast-forward the
clone with `scripts/fetch-sources.sh --update crw`, refresh any patch that no
longer applies, and write the new rev to that file. The nightly image build
clones upstream's head, so it is the first to stop when upstream moves under a
patch.

## Test your change

| Command | What it checks | Needs |
|---|---|---|
| `just test-patches` | The unit tests that the CRW patches add, against mock servers | `cargo` |
| `just test-stealth` | Each tier, the bot checks, an eBay listing, and three DataDome sites, against live sites | A running stack |
| `just test-stealth-claude`, `just test-stealth-codex`, `just test-stealth-antigravity` | The same scrapes through an MCP client | A running stack and the client |
| `just lint-docs` | The docs, against the Google style | [Vale](https://vale.sh/docs/install) |

CI runs `just test-patches` and the docs check on pull requests. It doesn't scrape
live sites, so if your change affects stealth behavior, run `just test-stealth`
yourself and put the result in the pull request.

## Write docs

Docs follow the
[Google developer documentation style guide](https://developers.google.com/style).
`just lint-docs` downloads the pinned Vale style package on its first run, and then
fails on any Vale warning or error in the docs.

`CLA.md` isn't checked, because it's a legal text.

If Vale flags a correct product or tool name, add the name to
`.github/styles/config/vocabularies/crw/accept.txt`.

## Send a pull request

Open your pull request against `main`. Describe what changed, why it changed, and
how you tested it. Pull requests are squash-merged.
