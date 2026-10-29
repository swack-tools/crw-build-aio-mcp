#!/usr/bin/env bash
# Desktop Chrome on a virtual display, with nothing attached to it until crw
# connects.
#
# Nothing drives this Chrome but crw's own DevTools connection. Automation
# frameworks (puppeteer, which the browserless server uses, or Playwright)
# turn on the CDP Runtime domain in every page and worker, and pages can
# detect that. Headless Chrome also differs from a windowed one in its UA,
# client hints, worker values and timing, which stealth scripts can only
# partly paper over, and detectors check for the patching itself. A plain
# windowed Chrome needs none of that.
set -euo pipefail

SCREEN="${CHROME_SCREEN:-1920x1080x24}"
# A desktop's taskbar: a screen whose whole area is free for windows, with a
# window as large as the screen, is how headless Chrome looks.
TASKBAR="${CHROME_TASKBAR:-40}"
PORT="${CDP_PORT:-9222}"
CHROME="${CHROME_BIN:-google-chrome-stable}"
command -v "$CHROME" >/dev/null || { echo "chrome-stealth: no Chrome at $CHROME" >&2; exit 1; }
IFS=x read -r width height _ <<< "$SCREEN"

export DISPLAY=:99
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
# -noreset: Xvfb otherwise resets when its last client (xprop, before Chrome
# starts) disconnects, which drops the work area set below.
Xvfb "$DISPLAY" -screen 0 "$SCREEN" -nolisten tcp -noreset &
for _ in $(seq 100); do [[ -S /tmp/.X11-unix/X99 ]] && break; sleep 0.1; done
xprop -root -f _NET_WORKAREA 32c -set _NET_WORKAREA "0, 0, $width, $((height - TASKBAR))"

profile="$(mktemp -d)"

node "$(dirname "$0")/chrome-stealth-relay.js" "$PORT" $((PORT + 1)) &
# Moves the pointer over each page, and clicks Cloudflare's Turnstile checkbox
# when a page shows one (pointer.js).
node "$(dirname "$0")/chrome-stealth-pointer.js" $((PORT + 1)) "$width" $((height - TASKBAR)) &

# --no-sandbox: the container has no user namespaces.
# WebGL stays off, as Chrome leaves it on a machine with no usable GPU. Each
# way of turning it on gets caught by a real anti-bot vendor: Mesa's software
# renderer (--ignore-gpu-blocklist) by Akamai, the same renderer under a real
# GPU's name by DataDome, and SwiftShader (--enable-unsafe-swiftshader) by
# Cloudflare. With it off all three let Chrome through; fingerprint test
# pages note the missing WebGL.
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
  --window-size="$width,$((height - TASKBAR))" \
  --disable-background-timer-throttling \
  --disable-backgrounding-occluded-windows \
  --disable-renderer-backgrounding \
  "$@" \
  about:blank &

# Exit when any of them does, so compose restarts the whole set.
wait -n
