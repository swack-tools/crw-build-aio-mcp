# camofox-browser with a plugin that clicks Cloudflare's Turnstile checkbox,
# using xdotool on Camoufox's virtual display; see turnstile/index.js.
FROM camofox-browser
RUN apt-get update && apt-get install -y --no-install-recommends xdotool \
 && rm -rf /var/lib/apt/lists/*
COPY turnstile/ ./plugins/turnstile/
RUN node -e "const fs = require('fs'), f = 'camofox.config.json', c = JSON.parse(fs.readFileSync(f)); \
  c.plugins.turnstile = { enabled: true }; fs.writeFileSync(f, JSON.stringify(c, null, 2) + '\n')"
