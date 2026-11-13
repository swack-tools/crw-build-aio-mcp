# camofox-browser with a plugin that clicks Cloudflare's Turnstile checkbox,
# using xdotool on Camoufox's virtual display; see turnstile/index.js.
FROM camofox-browser
# camofox-browser ends as its non-root runtime user (uid 1000, group 0), so
# install and copy as root, give group 0 the new files as upstream does for
# its own plugins, and drop back to that user.
USER root
RUN apt-get update && apt-get install -y --no-install-recommends xdotool \
 && rm -rf /var/lib/apt/lists/*
COPY turnstile/ ./plugins/turnstile/
RUN node -e "const fs = require('fs'), f = 'camofox.config.json', c = JSON.parse(fs.readFileSync(f)); \
  c.plugins.turnstile = { enabled: true }; fs.writeFileSync(f, JSON.stringify(c, null, 2) + '\n')" \
 && chgrp -R 0 ./plugins/turnstile camofox.config.json && chmod -R g=u ./plugins/turnstile camofox.config.json
USER 1000
