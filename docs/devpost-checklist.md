# Devpost submission — every field, checked

Against the published rules for RevenueCat Shipaton 2026. Deadline
**Wed 30 September 2026, 11:45pm PDT**. Today is 25 September — five days.

Legend: **OK** verified · **DO** action needed · **ASK** needs your answer

---

## The hard requirements

| # | Rule (quoted) | State |
|---|---|---|
| 1 | "a URL to a fully published app in Apple's App Store, the Google Play Store, or the Samsung Galaxy Store" | **OK** — `play.google.com/store/apps/details?id=com.platepatch.app` returns HTTP 200 with an Install button when fetched with `gl=US` |
| 2 | Apps must be "accessible from the United States" | **OK** — same check, US storefront |
| 3 | "The first public version of the Project must be released during the Submission Period" (31 Jul – 30 Sep 2026) | **ASK** — confirm the first production release date in Play Console → Release overview |
| 4 | Uses the RevenueCat SDK to power at least one purchase | **OK** — `purchases_flutter` 10.11.0, and the Worker verifies entitlement against the RevenueCat REST API |
| 5 | Built for iOS, iPadOS, macOS or Android | **OK** — Android |
| 6 | Demo video "should be less than two (2) minutes" | **OK** — 1:52.4 |
| 7 | Video "publicly posted to YouTube or Vimeo" | **OK** — unlisted counts as public. **DO** re-upload the recut and use the `watch?v=` URL, not `/shorts/` |
| 8 | Video shows "the app functioning on its intended device" | **OK** — real Galaxy A72, screen recording |
| 9 | No third-party trademarks or copyrighted music | **OK** — no music. Google Play branding appears during the purchase flow, which is unavoidable when demonstrating a purchase and is the sponsor's own required rail |
| 10 | 1024 × 1024 app icon | **OK** — `ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png`. Note `logo.png` in the assets folder is 512 × 512 — do not upload that one |
| 11 | At least one screenshot at "1179px width and 2556px height WITHOUT device frames" | **OK** — three of them: `devpost-1179x2556-hub.png`, `-picker.png`, `-result.png` |
| 12 | "the app must either offer a free trial or the Entrant must include a promo code for judges to unlock the in-app purchase and test all premium features" | **DO** — generate judge promo codes in Play Console and paste them into the submission |
| 13 | "Everything you submit needs to be in English" | **OK** |

**Only #12 blocks submission.** #3 and #7 need one action each.

---

## Fields to fill

| Field | Source | State |
|---|---|---|
| Project name | The Plate | OK |
| Tagline | "One small thing, added to what you already eat." | OK — `docs/devpost-submission.md` |
| Project details | Inspiration / What it does / How we built it / Challenges / Accomplishments / What we learned / What's next | OK — updated to 1.4.7 |
| Built with | flutter, dart, cloudflare-workers, d1, r2, durable-objects, workers-ai, gemini, revenuecat, play-integrity | **DO** — enter these tags |
| Try it out link | the Play Store URL | OK |
| Demo video URL | `https://www.youtube.com/watch?v=CLNGsA4nrUU` | **DO** — after re-upload |
| Image gallery | icon + the three 1179×2556 shots | **DO** — upload |
| Judge access | promo code | **DO** |
| Additional info | RevenueCat project id | **DO** — paste it |

---

## Prize categories worth entering

Each one you tick needs its **own description field filled in**. An empty
category description is a wasted entry, not a free lottery ticket.

| Category | Fit | What it demands |
|---|---|---|
| **HAMM Award** (monetization) | Strong | "how the app makes money, your paywall/pricing approach, and any conversion or revenue numbers" — you have a real paywall, a monthly/yearly ladder with in-app proration, promo codes, and server-side entitlement |
| **RevenueCat Peace Prize** | Strong | "how the app was designed to benefit individuals, the community, or society at large" — no calories, no guilt, no streaks, free offline mode, MENA food catalogue |
| **Design Award** | Good | "the app's unique design elements and what areas judges should look for" — the one-page scan result, the correctable chips, the non-dismissible AI badge |
| **#BuildInPublic** | **ASK** | Needs "links to any relevant social accounts and/or links to specific content". Only enter if you actually posted during the build |
| **Grand Prize** | Weak this year | Shortlisted on "total revenue generated during the Submission Period, as reported in RevenueCat", then judged on growth numbers. You shipped days ago |
| Best Game / Next Gen / Kotlin / Galaxy / Replit / OneSignal / Layers / Stripe / Noise / Influencer | No | Each needs a partner SDK, a store, a student status, or social proof you do not have |

Three categories with real descriptions beats ten with blanks.

---

## Order of operations, 25–30 Sep

1. Watch `~/Desktop/plate-video/the-plate-demo-final.mp4` end to end. Confirm
   the free-tier narration is intact. *(Blocks 3.)*
2. Install 1.4.7 on the phone and check the identity paths. *(Blocks 4.)*
3. Re-upload the recut to YouTube, take the `watch?v=` URL.
4. Upload the 1.4.7 AAB to Play with the release notes from
   `docs/play-whats-new.md`.
5. Play Console → Promotions → generate judge promo codes.
6. RevenueCat dashboard → **Transfer behaviour = "Keep with original App User
   ID"**. Without it, restore on a second account moves the subscription.
7. Fill every field above, write the three category descriptions, submit.
