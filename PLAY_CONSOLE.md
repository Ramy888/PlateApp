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
| Leaves the device | Meal photos (Google Gemini, via our Worker), anonymous device id + purchase record (RevenueCat) |
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
