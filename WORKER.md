# PlatePatch scan API

Deployed at `https://platepatch-api.ramy-comm.workers.dev`.

Holds the Gemini key, enforces quotas a patched app cannot lie its way past,
and proxies the two model calls. **It stores no photographs and no meal data** —
what anyone ate stays on their phone.

Build spec: [`AI_SCAN_SPEC.md`](AI_SCAN_SPEC.md).

> This replaces the accounts API that briefly lived here. That was torn down
> when accounts were dropped; `crypto.ts` and `http.ts` survive it.

## Status

| Step | State |
|---|---|
| 1 · Device registration, quota, reporting | **Done, deployed, 32 tests** |
| 2 · On-device image pipeline | Not started |
| 3 · Recognition (`/v1/scan`) | Not started |
| 4 · Play declarations, privacy rewrite | Not started |
| 5 · RevenueCat wiring | Partially — server check written, needs the secret |
| 6 · Visual preview (`/v1/preview`) | Not started |

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/health` | Liveness, and whether attestation is actually enforced |
| `POST` | `/v1/device` | Register an anonymous device, return a token and quota |
| `DELETE` | `/v1/device` | Forget the device, its quota, events and reports |
| `GET` | `/v1/quota` | Current allowance, without spending any |
| `POST` | `/v1/report` | Report an AI result — **required by Google Play** |

## Design decisions

**Quota lives in a Durable Object, one per device.** Spending a scan is a
read-modify-write; in D1 two requests can both read "1 left" and both spend it.
A Durable Object is single-threaded per id, so the race cannot occur — no
transactions, no optimistic retries. Free runs a weekly window, Pro a monthly
one, and the window rolls on read.

**The client's `isPro` is never consulted.** The app keeps that flag to decide
what UI to show. Before any model call the Worker asks RevenueCat's REST API
whether the device's app user id holds `platepatch_pro`, caches the answer in
the Durable Object for an hour, and enforces the quota itself. The check
**fails closed** — an outage downgrades to free rather than handing out Pro.

**A failed model call refunds the quota.** The user should not pay for our
error.

**Play Integrity is verified here, not through Firebase App Check.** App Check
is a wrapper around `decodeIntegrityToken`; the Worker signs a service-account
JWT with WebCrypto, exchanges it for an access token, and calls Google directly.
One fewer vendor and no Firebase project.

**Reports can never fail in front of a user.** `/v1/report` returns 202
unconditionally and logs any storage failure. Someone reporting offensive
content must not meet an error.

## Configuration

Set with `wrangler secret put`:

| Secret | State | Without it |
|---|---|---|
| `GEMINI_API_KEY` | **set** | No model calls |
| `REVENUECAT_SECRET_KEY` | not set | Everyone is free tier — the check fails closed |
| `PLAY_INTEGRITY_SA` | not set | **Attestation is skipped.** `/health` reports `"attestation": "skipped"` and every registration logs a warning |

> `PLAY_INTEGRITY_SA` must be set before production. The health endpoint
> reports the real state so a misconfigured deployment is visible from outside
> rather than discovered by a user.

Non-secret settings are in `wrangler.jsonc`. Both model ids are variables, so a
model can be swapped without an app release.

## Resources

| | |
|---|---|
| D1 | `platepatch-scan` — devices, scan_events, reports, rate_limits |
| R2 | `platepatch-previews` — lifecycle rule expires `p/` after 24 hours, verified |
| Durable Object | `QuotaCounter`, one per device |

The R2 expiry is enforced by the bucket, so "automatic deletion of temporary
generated images" is a property of the infrastructure rather than something the
code has to remember.

## Working on it

```bash
cd worker
npm install
npx wrangler d1 migrations apply platepatch-scan --remote
npx vitest run          # 32 tests, real D1 and Durable Objects in Miniflare
npx wrangler deploy
npx wrangler tail       # live logs
```

`.dev.vars` holds local secrets and is gitignored. `python3 ../tool/probe_gemini.py`
checks what the Gemini key can reach.

## Known gaps

- **iOS does not attest.** Android sends a Play Integrity token; iOS registers
  without one. App Attest needs wiring before an iOS release.
- **Rate limiting is per IP and coarse.** The per-device quota is the real
  control; the IP limit only slows down bulk registration.
- **Nothing calls `/v1/scan` yet** — it does not exist. Step 3.
