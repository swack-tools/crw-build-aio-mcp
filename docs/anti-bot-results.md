# Anti-bot results

Anti-bot vendors change their checks often, so these results are a snapshot.
`just test-stealth` and `crw-aio test` recheck the core of them.

## Sites

With default settings (no `renderer`, no `waitFor`) and a fresh Chrome profile, CRW
loaded the real page on each of these sites. The check ran on October 29, 2026,
and on October 31, 2026, for ebay.com.

The table groups sites by the protection that each is known to use. Chrome got each
site itself, except those marked *(Camoufox)*, where Chrome was turned away and the
fallback got through.

| Protection | Sites |
|---|---|
| Cloudflare, including interactive Turnstile | g2.com, indeed.com, glassdoor.com, crunchbase.com, gitlab.com sign-in, upwork.com, chatgpt.com, quizlet.com, coingecko.com, doordash.com, opensea.io, ziprecruiter.com, medium.com, genius.com, coinbase.com, patreon.com, producthunt.com, similarweb.com, crunchyroll.com, nowsecure.nl, nopecha.com's demo, scrapingcourse.com's challenges, investing.com *(Camoufox)* |
| DataDome | leboncoin.fr, tripadvisor.com, hermes.com, reuters.com, etsy.com, yelp.com, idealista.com, allegro.pl, soundcloud.com, fnac.com, seloger.com, vinted.com, footlocker.com, wsj.com, deezer.com |
| HUMAN (PerimeterX) | zillow.com, walmart.com, stockx.com, wayfair.com, bloomberg.com, seekingalpha.com, chegg.com, bhphotovideo.com, zoominfo.com, realtor.com, trulia.com, ssense.com, priceline.com, crateandbarrel.com, fiverr.com *(Camoufox)* |
| Akamai | nike.com, bestbuy.com, lowes.com, ups.com, fedex.com, usps.com, macys.com, kohls.com, costco.com, united.com, delta.com, aa.com, marriott.com, hilton.com, walgreens.com, sephora.com, asos.com, zara.com, ikea.com, homedepot.com *(Camoufox)*, adidas.com *(Camoufox)*, apartments.com *(Camoufox)*, expedia.com *(Camoufox)*, hm.com *(Camoufox)* |
| Kasada | hyatt.com, twitch.tv, realestate.com.au, wizzair.com, scheels.com, ticketek.com.au |
| Imperva | whoscored.com, pokemoncenter.com, copart.com, iaai.com, ryanair.com |
| AWS WAF | ballotpedia.org, imdb.com, goodreads.com, booking.com, stubhub.com, audible.com |
| F5 Shape | southwest.com, target.com, nordstrom.com, starbucks.com |
| Site's own | amazon.com, google.com search, bing.com, duckduckgo.com, reddit.com (on the reload), instagram.com, x.com, youtube.com, tiktok.com, airbnb.com, kayak.com, ticketmaster.com, shein.com, temu.com, aliexpress.com, craigslist.org, ebay.com (on the reload, or Camoufox when that fails too) |

Two sites don't return the real page:

- **lacentrale.fr.** DataDome shows both browsers a captcha, so the scrape fails as
  blocked.
- **LinkedIn company pages.** These load LinkedIn's sign-up wall, which is a login
  requirement and not bot detection.

## Fingerprint tests

| Test | Result |
|---|---|
| deviceandbrowserinfo.com | "Not a bot" |
| rebrowser's detector | All green |
| fingerprint.com | No bot, tampering, VM, or incognito detected. Its scraping demo serves the protected data. |
| Google's reCAPTCHA v3 demo | 0.9, the highest score it gives |
| BrowserScan and pixelscan bot checks | "Normal" and "Clear" on every row |
| whoer.net | 100% |
| CreepJS | 0% headless and 0% stealth |

## Known limits

- **WebGL.** Chrome has no WebGL, as explained in
  [How it works](how-it-works.md#chrome-tier). As a result, bot.sannysoft.com fails
  its two WebGL rows, BrowserScan rates the fingerprint 90% authentic instead of
  100%, and the check on iphey.com never finishes.
- **Host values.** The timezone, which `up.sh` sets, and the CPU count are the
  host's.
- **fpscanner.** Its `WEBDRIVER` test on bot.incolumitas.com fails because
  `navigator.webdriver` exists, as it does in every current Chrome.
- **Behavior checks.** The pointer moves, but a scrape never types or fills in a
  form, so tests that score those actions have nothing to score. One example is
  deviceandbrowserinfo.com's interaction test.
