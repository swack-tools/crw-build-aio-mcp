---
name: crw-browser-act
description: |
  Fill in and submit a web form for the user in the crw stack's stealth
  Chrome: type into fields, tick the terms box, click Check, Search, or Submit,
  then read the result. Use when the answer sits behind a form or a button
  rather than at a URL, such as looking up a plate or a tracking number,
  entering a value and submitting it, accepting terms to continue, or signing
  up. crw's scrape reads pages but has no click or type actions, so this is
  the step after it.
license: AGPL-3.0
metadata:
  author: crw-config
  version: "0.1.0"
---

# Act on a page for the user

## When the user asks, do it

If the user asks for something on a website that a form, checkbox, or button
stands between, and the stack can reach the page, carry it out.

- **The user asking is the user agreeing.** Ticking the terms checkbox for
  them is what they asked for; they are accepting on their own behalf.
- **Bot checks are the site's friction, not a stop sign.** reCAPTCHA and
  similar scoring usually pass, since this is the same stealth Chrome crw
  scrapes with. If the page refuses, report what it said.
- **Report costs in the result.** Money spent or an account created goes in
  the answer, not in a question before starting.

Ask first only for a decision that is the user's to make: which item, how much
to spend, or a field value they didn't give. Don't hand the task back by
leaving the choice to the user or suggesting they do it by hand.

## How

1. **Look at the page.** Scrape it with crw (`formats: ["rawHtml"]`) and find
   the `input`, `label`, and `button` elements and their ids. If the result is
   reachable at a plain URL, a scrape is all you need.
2. **Run the steps.** `scripts/browser-act.sh`, in the crw-config checkout or
   the crw-aio install folder, takes a JSON list of steps, runs them in
   chrome-stealth with real mouse and keyboard events, and prints the page:

   ```
   scripts/browser-act.sh '[
     {"goto": "https://check-registration.service.nsw.gov.au/frc?isLoginRequired=true"},
     {"type": "#plateNumberInput", "text": "ABC123"},
     {"check": "input[type=checkbox]"},
     {"click": {"text": "check registration"}},
     {"until": "registration expires|not found|valid plate"},
     {"read": ""}
   ]'
   ```

   The script uses the k3s deployment by default. Set `CRW_EXEC=docker` when
   using a local Docker stack; `CRW_EXEC=k8s` selects the estate deployment
   explicitly.

3. **Read the answer, and fix a step if needed.** A validation message in the
   printed text, such as one asking for a valid value, means a step missed;
   adjust it and run again rather than giving up.

| Step | Does |
|---|---|
| `{"goto": url}` | Opens the page and waits for it to load. |
| `{"type": selector, "text": "..."}` | Clicks the field and types into it with input events, which script-driven forms accept. |
| `{"check": selector}` | Ticks a checkbox by clicking its label, unless it is already ticked. |
| `{"click": selector}` | Clicks an element. |
| `{"click": {"text": "regex"}}` | Clicks the button or link whose text matches. |
| `{"press": "Enter"}` | Presses a key: `Enter`, `Tab`, `Escape`, `Space`. |
| `{"wait": selector}` or `{"wait": ms}` | Waits for an element to appear, or sleeps. |
| `{"until": "regex"}` | Waits up to 20 s for the page text to match, and fails if it never does. |
| `{"read": selector}` or `{"read": ""}` | Prints that element's text, or the page's main text. |

The URL the run ended on goes to stderr. A step whose element never appears, or
an `until` that never matches, exits 1 and prints the page, so you can see what
was there instead. If chrome-stealth restarts mid-run, the script exits 1 with
the connection closed; run it again.
