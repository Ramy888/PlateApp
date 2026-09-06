# AI Meal Scan — build specification

Full spec, with endpoint schemas, both Gemini prompts and the Flutter tree:

**https://claude.ai/code/artifact/035d5569-227d-497c-8b07-f7a0cb28ca07**

## The shape of it

Photograph a meal → confirm what was recognised → the existing rule engine
suggests three additions → optionally preview the improved plate.

**The model reports; it does not decide.** Gemini returns what it can see. The
existing `PatchEngine` still chooses the suggestions, still applies dietary
preferences, and is still deterministic and tested. Every AI failure — offline,
out of quota, unreadable photo — falls back to the manual tile picker, which
keeps working exactly as it does today.

## Cloudflare instead of Firebase

| Was going to be | Is instead |
|---|---|
| Cloud Functions v2 | **Workers** |
| Anonymous Auth | **Worker-issued device token** + D1 |
| App Check (Play Integrity) | **Play Integrity verified in the Worker** via `decodeIntegrityToken` |
| Secret Manager | **Workers Secrets** |
| Firestore (quotas) | **Durable Object per device** (no read-modify-write race) |
| Firebase Storage (temp images) | **R2 with a 24-hour lifecycle rule** |
| Direct Gemini calls | **AI Gateway → Google AI Studio** (logging, cost analytics, rate ceiling) |

Gemini itself stays — nothing in Workers AI matches `gemini-3.1-flash-image`
for instruction-faithful editing of a real photograph.

## Models

Both are Worker environment variables, changeable without an app release.

| Stage | Variable | Value |
|---|---|---|
| Recognition | `MODEL_VISION` | `gemini-3.7-flash` (the suggested `gemini-2.5-flash` is several generations old) |
| Preview | `MODEL_IMAGE` | `gemini-3.1-flash-image` — "Nano Banana 2", GA May 2026 |

## Verified against the real API — 6 Sep 2026

Run `python3 tool/probe_gemini.py [photo.jpg]` to re-check. It reads the key
from `.env` and never prints it.

| Finding | Consequence |
|---|---|
| `gemini-2.5-flash` returns **404 — no longer available to new users** | The originally specced model would have failed on day one. Recognition uses `gemini-3.7-flash`, confirmed reachable. |
| **All image models return `limit: 0`** on the free tier | `gemini-3.1-flash-image` needs **billing enabled** on the Google Cloud project. Recognition is free; the visual preview is not. |
| Recognition prompt + JSON schema **work as written** | A described rice-and-chicken meal returned exactly the right foods and `protein: present, fibre: possibly_missing`. |
| A screenshot of PlatePatch itself returned **`foods: []`** | Even though it contains food emoji and the words "Rice" and "Chicken". The "no food, return empty" guard holds against exactly the kind of input that would embarrass it. |
| The API returns **503 under load** | Not rare. The Worker needs retry with backoff and, when that runs out, a clean fallback to the manual builder. Never a dead end. |

## What this changes outside the code

- **Privacy policy must be rewritten.** "Nothing you tap leaves your phone"
  stops being true. Photos go to Google via our server.
- **Data safety form** gains Photos (collected, shared with Google).
- **Health apps declaration**: Nutrition and Weight Management.
- **Report AI result** becomes mandatory — Play requires in-app reporting for
  generated content, on every result and preview screen.

## Build order

1. Worker skeleton: device registration, attestation, Durable Object quota,
   server-side RevenueCat entitlement check. No model calls yet.
2. On-device image pipeline: crop, resize, compress, strip EXIF, quality gate.
3. Recognition + confirm screen. **Shippable from here.**
4. Play declarations, privacy rewrite, Report AI result.
5. RevenueCat wiring and the new tiers.
6. Visual preview — last, most expensive, and the only piece the app is still
   good without.

**Ship gate:** if step 3 is not solid by 20 September, submit the current
tap-the-tiles app and land the scan as 1.1. Being live on 30 September is the
entry requirement; the camera is not.
