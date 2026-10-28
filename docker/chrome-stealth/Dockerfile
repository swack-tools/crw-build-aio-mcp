# browserless's Chromium image (Chrome, fonts, Xvfb), started as a plain
# windowed Chrome instead of the browserless server; see start.sh.
FROM browserless-chromium
COPY --chmod=755 start.sh /usr/local/bin/chrome-stealth
COPY relay.js /usr/local/bin/chrome-stealth-relay.js
EXPOSE 9222
ENTRYPOINT ["/usr/local/bin/chrome-stealth"]
CMD []
