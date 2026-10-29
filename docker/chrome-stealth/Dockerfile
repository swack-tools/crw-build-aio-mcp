# Google Chrome on a virtual display, the way a person runs it on an Ubuntu
# desktop; see start.sh. Chrome stable comes from Google's apt repository
# (it reports itself as Google Chrome, which a Chromium build does not), so a
# rebuild picks up the current release.
FROM ubuntu:26.04

# Xvfb is the display; xprop gives it a taskbar-sized work area and xdotool
# moves the pointer on it. The fonts are a stock Ubuntu desktop's. Node runs
# the DevTools relay and pointer.js.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg \
      xvfb x11-utils xdotool \
      fonts-ubuntu fonts-dejavu-core fonts-liberation fonts-freefont-ttf \
      fonts-noto-core fonts-noto-mono fonts-noto-cjk fonts-noto-color-emoji \
      fonts-indic fonts-thai-tlwg fonts-kacst fonts-khmeros-core fonts-lao fonts-urw-base35 \
      nodejs \
 && curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
      | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
      > /etc/apt/sources.list.d/google-chrome.list \
 && apt-get update && apt-get install -y --no-install-recommends google-chrome-stable \
 && apt-get purge -y --auto-remove gnupg \
 && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash chrome
COPY --chmod=755 start.sh /usr/local/bin/chrome-stealth
COPY relay.js /usr/local/bin/chrome-stealth-relay.js
COPY pointer.js /usr/local/bin/chrome-stealth-pointer.js
USER chrome
WORKDIR /home/chrome
EXPOSE 9222
ENTRYPOINT ["/usr/local/bin/chrome-stealth"]
