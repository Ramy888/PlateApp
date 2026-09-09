# Play Console declarations

Full version with copy-paste blocks and the reasoning behind each answer:

**https://claude.ai/code/artifact/68fcf19f-6e34-4ef6-9399-95dbdf8598c6**

Answers were checked against the merged release manifest and the shipped source
on 9 September 2026 (re-checked when Google sign-in was added). **If the app gains a permission or an SDK, re-check them.**

## What the shipped app does

| | |
|---|---|
| Permissions | `CAMERA`, `INTERNET`, `ACCESS_NETWORK_STATE`, `BILLING` — nothing else |
| Accounts | **Google sign-in**, asked for on the first AI generation — not at launch. Everything non-AI works signed out. |
| Ads / advertising ID | None |
| Analytics / crash reporting | None |
| Leaves the device | Meal photos, typed meal descriptions, voice recordings of a meal, and the names of foods picked by hand (Google Gemini and Cloudflare Workers AI, via our Worker); Google account id, email and name (our Worker only); device id + purchase record (RevenueCat) |

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

## Data safety — declare exactly six types

Sign-in added three of these. Personal info is **collected, not shared**: the
email address and name reach our Worker and go nowhere else.

| Type | Collected | Shared | Ephemeral | Required | Purpose |
|---|---|---|---|---|---|
| Photos and videos → **Photos** | Yes | Yes | **No** | Optional | App functionality |
| Personal info → **Email address** | Yes | **No** | No | Optional | Account management, app functionality |
| Personal info → **Name** | Yes | **No** | No | Optional | Account management, app functionality |
| Personal info → **User IDs** | Yes | **No** | No | Optional | Account management, app functionality |
| **Device or other IDs** | Yes | Yes | No | Required | App functionality |
| Financial info → **Purchase history** | Yes | Yes | No | Optional | App functionality |

All three personal-info types are **Optional**, not Required: the app is fully
usable signed out except for the four AI features. The Google `sub` is a **User
ID** in Play's taxonomy, not a Device ID. The profile picture is **not**
collected — it is rendered straight from Google's URL and never reaches our
server, so there is no Photos entry for it.

Everything else: **No**. Notably **Health and fitness: No** — the rule engine
runs on the phone and meal history is never uploaded. The server keeps a count
that a scan happened, with no photo and no food names in it.

- Encrypted in transit: **yes**
- **Does your app allow users to create an account? → Yes.** This makes the
  deletion URL mandatory rather than optional.
- Users can request deletion: **yes** — in-app, Settings → **Delete my account
  and data**, which removes the account itself and not only the device record
- Deletion URL: `https://ramy888.github.io/PlateApp/delete-data.html`

### Two external gates, and the order they have to happen in

Neither is in this repo, and sign-in fails without them:

1. **OAuth consent screen must be In production**, not Testing. While it is in
   Testing only the listed test users can sign in; everyone else is refused.
   Scopes are `openid email profile`, which are non-sensitive, so no Google
   verification review is needed.
2. **Publish `docs/` before the release build reaches users.** Disclosing the
   account before the app collects it is fine; the reverse is a policy breach.

**Do not tick "processed ephemerally" for Photos.** True of recognition, false
of previews — a generated preview lives in storage for up to 24 hours.

## The rest

| Declaration | Answer |
|---|---|
| App access | **All functionality available without special access** still holds — the four AI features need a Google account, but any Google account works, so there are no credentials to give a reviewer |
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
