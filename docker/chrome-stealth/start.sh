#!/usr/bin/env bash
# Desktop Chrome on a virtual display, with nothing attached to it until crw
# connects.
#
# This replaces the browserless server the image was built for. browserless
# drives every Chrome it launches through puppeteer, which enables the CDP
# Runtime domain in each page and worker, and pages can detect that
# (deviceandbrowserinfo.com flags it; Cloudflare's challenge never clears).
# Headless Chrome also differs from a windowed one in its UA, client hints,
# worker values and timing, which stealth scripts can only partly paper over,
# and detectors check for the patching itself. A plain windowed Chrome needs
# none of that.
set -euo pipefail

SCREEN="${CHROME_SCREEN:-1920x1080x24}"
PORT="${CDP_PORT:-9222}"
CHROME="${CHROME_BIN:-$(find /usr/local/bin/playwright-browsers -path '*chromium-*' -name chrome -type f -print -quit)}"
[[ -x "$CHROME" ]] || { echo "chrome-stealth: no Chrome binary found" >&2; exit 1; }
IFS=x read -r width height _ <<< "$SCREEN"

export DISPLAY=:99
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
Xvfb "$DISPLAY" -screen 0 "$SCREEN" -nolisten tcp &
for _ in $(seq 100); do [[ -S /tmp/.X11-unix/X99 ]] && break; sleep 0.1; done

profile="$(mktemp -d)"

node "$(dirname "$0")/chrome-stealth-relay.js" "$PORT" $((PORT + 1)) &

# --no-sandbox: the container has no user namespaces (browserless runs the same way).
# No --enable-unsafe-swiftshader: without a GPU that is the only way to get
# WebGL, and Cloudflare's challenge fails a SwiftShader GPU where it passes no WebGL.
# The three background flags stop Chrome throttling the windows crw opens
# behind each other; occluded windows would report themselves hidden.
"$CHROME" \
  --no-sandbox \
  --remote-debugging-port=$((PORT + 1)) \
  --user-data-dir="$profile" \
  --no-first-run \
  --no-default-browser-check \
  --password-store=basic \
  --lang=en-US \
  --window-position=0,0 \
  --window-size="$width,$height" \
  --disable-background-timer-throttling \
  --disable-backgrounding-occluded-windows \
  --disable-renderer-backgrounding \
  "$@" \
  about:blank &

# Exit when any of the three does, so compose restarts the whole set.
wait -n
