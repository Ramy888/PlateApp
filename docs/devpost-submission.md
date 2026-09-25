# Devpost submission copy — The Plate

Paste each block into the matching Devpost field. Markdown headings need a
space after the `##`, or Devpost renders the hash marks literally.

Written against 1.4.7 (versionCode 15). Anything not yet true of the live
build is marked **[check]** — don't claim it until it ships.

---

## Field: Tagline (short, one line)

```
One small thing, added to what you already eat.
```

---

## Field: Project details

```
## Inspiration

Most nutrition apps begin by telling you that what you are about to eat is
wrong. They ask you to weigh it, count it, log it, and feel bad about it —
and the honest truth is that almost nobody keeps that up past week two.

The Plate starts from the opposite end. You are going to eat the meal in
front of you. The only useful question is: what is one thing you could add
to it, right now, that makes it better?

Not a replacement. Not a plan. One thing.

## What it does

Show The Plate a meal — photograph it, say it out loud, describe it in a
sentence, or tap it together by hand — and it answers with a single
addition, and shows you the plate with that addition on it.

Four ways in, one answer out:

- **Photograph it.** The camera reads the plate, shows you what it found as
  chips you can correct, and suggests the addition.
- **Say it.** Hold the button, describe the meal, let go. It answers out
  loud, and you can play back exactly what the microphone heard — so when
  something looks wrong you can tell a mishearing from a misunderstanding.
- **Describe it.** A chat box that only talks about food on your plate.
- **Build it by hand.** Free, offline, signed out, forever.

Three suggestions sit side by side — fastest, cheapest, plant-based — and
choosing one redraws the plate with it. Corrections are live: remove the
chicken and the suggestion changes on the spot.

What it never does: no calories, no grams, no macros, no weighing, no
streaks, no guilt. That is a rule enforced by a test in the codebase, not a
promise in a README.

## How we built it

**Flutter** app, **Cloudflare Workers** back end, and a deliberate split
between what a model decides and what a rule decides.

The suggestion is **not** made by an LLM. A pure, deterministic rule engine
picks it from a catalogue, using the foods on the plate, your goal, your
dietary and budget filters, and which past suggestions actually kept you
full. Same plate, same answer, every time — testable, instant, and it keeps
working when a model is down. The AI does the parts only a model can do:
reading a photograph, understanding a spoken sentence, and drawing the
result.

- **Gemini Flash** reads meal photos and handles voice and chat turns.
- **Flux-1-Schnell on Cloudflare Workers AI** draws the patched plate.
- **D1** holds devices and events, **R2** holds generated images for 24
  hours, **Durable Objects** hold each account's allowance.
- **RevenueCat** runs the subscription, and the server verifies entitlement
  against RevenueCat's API rather than believing the app.
- **Play Integrity** attests the install before it can register.

Prompt injection is designed out rather than filtered: the model returns
catalogue **ids**, never free text, and the server resolves those ids to
phrases from a closed set. Nothing a client sends can reach an image prompt.

## Challenges we ran into

**A label is not evidence.** Every real scan was refused with HTTP 415 for
eight days. The app sent its photo with no explicit content type, so Flutter
labelled it `application/octet-stream`; the server read the label, not the
file, and rejected it. Nothing was written down when a request was refused
before the model ran, so the logs looked empty rather than wrong. The fix
was to decide the type from the file's first bytes and to record refusals —
and the very next attempt named the problem in one line.

**A subscription the server could not see.** Someone could pay, get a
receipt, and still be sent back to the paywall. The server verifies with
RevenueCat using an id captured once at first launch, from an SDK that
configures asynchronously — so it was usually null, and a null id meant the
check never ran at all. The id is adoptable after the fact now, a negative
answer goes stale in a minute where a positive one lasts an hour, and any
launch that finds a subscription repairs the server's copy.

**Nonce padding.** Play Integrity tokens came back with a padded base64
nonce where an unpadded one had been issued, so every genuine Play install
failed attestation while emulators passed.

**One payment, every account on the phone.** RevenueCat mints one anonymous
id per install and keeps it forever, so a subscription — or a redeemed promo
code — stayed attached to the handset rather than to the person. Signing out
and in as someone else inherited it. The store is told who signed in now, and
told to forget them on the way out, so the next person starts with nothing.

**Changing plan is not a second sale.** Google treats a monthly-to-yearly
move as *replacing* one subscription, and has to be told which one; sold as a
new purchase it becomes two subscriptions and two charges. With
`withTimeProration` the switch is immediate and the unused remainder is
credited — on the recorded run, 51 days of trial carried into the year and
the charge that day was zero.

## Accomplishments that we're proud of

The engine is pure. The picture is honest — every generated image carries a
non-dismissible AI label, and the drawn plate is free and works offline, so
nobody pays to find out what the answer is.

And the unit economics are real rather than hoped for: reading a meal costs
about $0.0017, drawing the patched plate about $0.0019. We measured the
photo-editing feature at $0.068 an image, found it was reachable only
through a bug, and deleted it.

## What we learned

Green tests are not evidence that the product works. 135 tests passed while
the app was completely broken in production, because the fixtures declared
`image/jpeg` and the server never looked past the label. Two wrong
assumptions cancelled out in every test and in none of real life.

The fix was not more tests. It was making the server say what it did — one
structured line per request, and a durable row for every refusal — so the
next failure named itself instead of being inferred.

## What's next for The Plate

iOS. And the thing the engine is actually for: enough after-meal answers
to learn which additions keep *you* full, rather than which ones keep people
in general full.
```

---

## Field: Additional info / "Tell us about your team"

```
Built solo, in public, over the Shipaton.

RevenueCat SDK handles the subscription; the Cloudflare Worker verifies the
entitlement server-side against the RevenueCat REST API, so the phone is
never the authority on what someone has paid for.

RevenueCat project: [check — paste your project id]
Package name: com.platepatch.app
```

---

## Field: Try it out links

```
Google Play — https://play.google.com/store/apps/details?id=com.platepatch.app
```

Judges also need a promo code. **[check]** — generate one in Play Console
and paste it into the submission where it asks for judge access.

---

## Media captions

| Asset | Caption |
|---|---|
| App icon | The Plate |
| Screenshot 1 — home | Four ways to show it a meal. Building one by hand is free, signed out, forever. |
| Screenshot 2 — scan result | What the camera read, correctable in place — and one thing to add. |
| Screenshot 3 — patched plate | The plate, drawn with the addition on it. Always labelled as AI. |
| Screenshot 4 — voice | Hold and say your meal. Play back exactly what it heard. |
| Screenshot 5 — paywall | Three free AI meals. Pro for the rest. |
| Demo video | Under two minutes, on a real device. |

Screenshots must be **1179 × 2556**, no device frames. **[check]** the ones
already uploaded — that size is a rule, not a suggestion.

---

## Still to do, outside this file

- Generate judge promo codes in Play Console
- Record the demo video: **under 2 minutes**, public on YouTube or Vimeo,
  showing the app running on a real device, no copyrighted music
- Paste the RevenueCat project id into Additional info
