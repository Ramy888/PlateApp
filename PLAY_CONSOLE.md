# Play Console declarations

Full version with copy-paste blocks and the reasoning behind each answer:

**https://claude.ai/code/artifact/68fcf19f-6e34-4ef6-9399-95dbdf8598c6**

Answers were checked against the merged release manifest and the shipped source
on 7 September 2026. **If the app gains a permission or an SDK, re-check them.**

## What the shipped app does

| | |
|---|---|
| Permissions | `CAMERA`, `INTERNET`, `ACCESS_NETWORK_STATE`, `BILLING` — nothing else |
| Accounts | None |
| Ads / advertising ID | None |
| Analytics / crash reporting | None |
| Leaves the device | Meal photos, typed meal descriptions, voice recordings of a meal, and the names of foods picked by hand (Google Gemini and Cloudflare Workers AI, via our Worker), anonymous device id + purchase record (RevenueCat) |

**Audio, in the data-safety form:** collected, **not** stored, sent for
processing only. Purpose: app functionality. Not shared with third parties
beyond the processor named above. Not required — everything works by typing or
photographing instead. The microphone is only live while the button is held.

### Answering the AI-generated content questions

Play asks whether the app produces generated content, and whether users can
report and rate it. Both are yes:

| Question | Answer | Where it is in the app |
|---|---|---|
| Does the app generate content with AI? | Yes — text and images | The scan flow, and the chat reply |
| Can users report generated content? | Yes | The flag on every scan result, patch and chat reply → `widgets/report_sheet.dart` |
| Can users rate generated content? | Yes | Thumb up / thumb down on every chat reply → `POST /v1/rating` |
| Is generated content labelled? | Yes, non-dismissibly | "AI picture — appearance and serving size are illustrative", carried in R2 object metadata as well as on screen |

The one thing to be able to say to a reviewer: **no text a user types reaches
the image model.** The chat model answers in ids from the app's own catalogue,
the Worker looks those up in a generated closed set, and the picture prompt is
a fixed template over the names it found. `worker/test/chat.test.ts` asserts it
with a prompt-injection attempt.
| Never leaves the device | Meal history, saved patches, goals, dietary preferences |

## Data safety — declare exactly three types

| Type | Collected | Shared | Ephemeral | Required | Purpose |
|---|---|---|---|---|---|
| Photos and videos → **Photos** | Yes | Yes | **No** | Optional | App functionality |
| **Device or other IDs** | Yes | Yes | No | Required | App functionality |
| Financial info → **Purchase history** | Yes | Yes | No | Optional | App functionality |

Everything else: **No**. Notably **Health and fitness: No** — the rule engine
runs on the phone and meal history is never uploaded. The server keeps a count
that a scan happened, with no photo and no food names in it.

- Encrypted in transit: **yes**
- Users can request deletion: **yes**
- Deletion URL: `https://ramy888.github.io/PlateApp/delete-data.html`

**Do not tick "processed ephemerally" for Photos.** True of recognition, false
of previews — a generated preview lives in storage for up to 24 hours.

## The rest

| Declaration | Answer |
|---|---|
| App access | All functionality available without special access |
| Ads | No |
| Content rating | IARC → expect Everyone / PEGI 3 |
| Target audience | **18 and over** (13–17 pulls the listing into Families policy) |
| News / COVID-19 / government / financial features | No |
| Advertising ID | Not used |
| Photo and video permissions | Not applicable — `READ_MEDIA_IMAGES` is not requested |
| Health apps | **Nutrition and Weight Management** |

## Before submitting

The Play yearly plan has a 7-day free trial, and the app has its own 7-day scan
trial that needs no store account — so a new user gets roughly **14 days free**
in total. Fine if intended; shorten the Play offer to 3 days if not.
