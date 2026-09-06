# PlatePatch accounts API

> **Status: built, deployed, and unused.**
>
> This was built to add sign in, register, forgot password and account
> deletion. That decision was then reversed — PlatePatch ships with no
> accounts. Nothing in the Flutter app calls this API, and no auth screens
> exist. **If accounts stay dropped, tear this down** (see below) rather than
> leaving it running.

Deployed at `https://platepatch-api.ramy-comm.workers.dev`.

## What it does

A Cloudflare Worker over D1. An account exists for exactly one reason — to move
saved patches to a new phone — so the server stores an email address, a password
hash, and one blob of meal data it never inspects.

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/v1/auth/register` | Create an account, return a session |
| `POST` | `/v1/auth/login` | Exchange credentials for a session |
| `POST` | `/v1/auth/logout` | End the calling session |
| `POST` | `/v1/auth/forgot` | Mint a reset token and email it |
| `POST` | `/v1/auth/reset` | Set a new password from a reset token |
| `GET` | `/v1/account` | The signed-in user |
| `DELETE` | `/v1/account` | Erase the user and everything of theirs |
| `GET`/`PUT` | `/v1/sync` | Read/write the synced document |
| `GET` | `/health` | Liveness |

## Security decisions

- **Passwords**: PBKDF2-HMAC-SHA256, 210,000 iterations (OWASP 2023), 16-byte
  random salt. The iteration count is stored inside the hash so it can be raised
  later without invalidating existing hashes.
- **Sessions**: 32 random bytes from `crypto.getRandomValues`. Only the SHA-256
  is stored, so a database dump cannot be replayed against the API.
- **Timing**: a login for an unknown address still runs a full PBKDF2
  derivation, and hash comparison is constant-time, so a missing account and a
  wrong password are indistinguishable.
- **Enumeration**: `/v1/auth/forgot` returns the same 202 body whether or not
  the address exists. `/v1/auth/register` does return 409 on a duplicate — the
  usual trade-off, and the one place enumeration is possible.
- **Resets**: hashed, single-use, one-hour expiry. A successful reset deletes
  every session for that user, so a reset also evicts anyone else signed in.
- **Rate limits**: fixed-window counters in D1 — login 10 per 15 min per IP,
  register 5/hour per IP, forgot 5/hour per IP *and* 3/hour per address.
- **Errors**: internal failures log the detail and return a generic message.

## Testing

```bash
cd worker && npm install && npx vitest run   # 43 tests
```

Runs against a real D1 in Miniflare with the production migrations applied.
Covers registration, login, sessions, sync isolation between accounts, the full
reset flow including single-use enforcement, account deletion, rate limiting,
and request hardening.

## Known gap: email is unverified

`/v1/auth/forgot` mints a token and calls the `EMAIL` binding, but **no email
has ever actually been delivered**, because Cloudflare Email Sending needs a
verified domain and this account has none. The local emulator only supports raw
MIME sends, so it cannot verify the send path either.

The failure is contained — a send error is logged and the request still returns
202, so a mail outage can never become an account lockout — and a test asserts
that. But before shipping any reset flow:

1. Add a domain to the Cloudflare account.
2. `npx wrangler email sending enable <domain>`
3. Set `EMAIL_FROM` in `wrangler.jsonc` to an address on it.
4. Point `RESET_LINK_BASE` at a real reset page and send yourself a live email.

## Operating it

```bash
cd worker
npx wrangler d1 migrations apply platepatch --remote   # schema
npx wrangler deploy                                    # ship
npx wrangler tail                                      # live logs
```

## Tearing it down

If accounts stay dropped, remove both — an unused public endpoint is a liability,
not a spare part:

```bash
npx wrangler delete --name platepatch-api
npx wrangler d1 delete platepatch
```

Then delete `worker/` and this file. The history keeps it if it is ever wanted.
