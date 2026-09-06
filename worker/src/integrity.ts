import { fromBase64, randomToken, toBase64Url } from './crypto';

/**
 * Play Integrity, verified here rather than through Firebase App Check.
 *
 * App Check is a wrapper around this call. Doing it directly means one fewer
 * vendor and no Firebase project: the Worker signs a service-account JWT with
 * WebCrypto, exchanges it for an access token, and asks Google to decode the
 * integrity token the app collected.
 */

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/playintegrity';

export type AttestationResult =
  | { ok: true; verdict: 'verified' | 'skipped' }
  | { ok: false; reason: string };

/** How long a challenge stays usable. Long enough for a slow token request. */
const CHALLENGE_TTL_SECONDS = 300;

/**
 * Issues a single-use nonce.
 *
 * Play Integrity binds the token to whatever nonce the app supplied, so a
 * server-issued one is what makes the token unrepeatable. Without it, a token
 * captured once could be replayed indefinitely and attestation would prove
 * nothing.
 */
export async function issueChallenge(env: Env): Promise<{ nonce: string; expiresAt: number }> {
  const now = Math.floor(Date.now() / 1000);
  const nonce = randomToken(32);
  const expiresAt = now + CHALLENGE_TTL_SECONDS;
  await env.DB.prepare(
    'INSERT INTO challenges (nonce, created_at, expires_at) VALUES (?, ?, ?)',
  )
    .bind(nonce, now, expiresAt)
    .run();
  return { nonce, expiresAt };
}

/** Consumes a challenge. Returns false if it is unknown, expired or reused. */
async function consumeChallenge(env: Env, nonce: string): Promise<boolean> {
  const now = Math.floor(Date.now() / 1000);
  const row = await env.DB.prepare(
    'SELECT expires_at, used_at FROM challenges WHERE nonce = ?',
  )
    .bind(nonce)
    .first<{ expires_at: number; used_at: number | null }>();

  if (!row || row.used_at !== null || row.expires_at < now) return false;
  await env.DB.prepare('UPDATE challenges SET used_at = ? WHERE nonce = ?')
    .bind(now, nonce)
    .run();
  return true;
}

interface ServiceAccount {
  client_email: string;
  private_key: string;
}

/** Cached for the life of the isolate; Google's tokens last an hour. */
let cachedToken: { value: string; expiresAt: number } | null = null;

function base64UrlJson(value: unknown): string {
  return toBase64Url(new TextEncoder().encode(JSON.stringify(value)));
}

/** Turns a PEM private key into something WebCrypto will sign with. */
async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  return crypto.subtle.importKey(
    'pkcs8',
    fromBase64(body) as BufferSource,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

async function accessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt > now + 60) return cachedToken.value;

  const claims = {
    iss: account.client_email,
    scope: SCOPE,
    aud: TOKEN_URL,
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${base64UrlJson({ alg: 'RS256', typ: 'JWT' })}.${base64UrlJson(claims)}`;
  const key = await importPrivateKey(account.private_key);
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  const assertion = `${unsigned}.${toBase64Url(new Uint8Array(signature))}`;

  const response = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
    signal: AbortSignal.timeout(5_000),
  });
  if (!response.ok) {
    throw new Error(`token exchange failed: ${response.status}`);
  }

  const body = (await response.json()) as { access_token: string; expires_in: number };
  cachedToken = { value: body.access_token, expiresAt: now + body.expires_in };
  return body.access_token;
}

/**
 * Verifies a Play Integrity token.
 *
 * When `PLAY_INTEGRITY_SA` is not configured, verification is **skipped** and
 * the result says so, so local development and the emulator work. Production
 * must set the secret — the router logs a warning on every unattested call so
 * this cannot be forgotten quietly.
 */
export async function verifyIntegrity(
  env: Env,
  integrityToken: string,
): Promise<AttestationResult> {
  if (!env.PLAY_INTEGRITY_SA) {
    console.warn(JSON.stringify({ event: 'attestation_skipped', reason: 'no_service_account' }));
    return { ok: true, verdict: 'skipped' };
  }
  if (!integrityToken) return { ok: false, reason: 'missing_token' };

  let account: ServiceAccount;
  try {
    account = JSON.parse(env.PLAY_INTEGRITY_SA) as ServiceAccount;
  } catch {
    console.error(JSON.stringify({ event: 'attestation_misconfigured' }));
    return { ok: false, reason: 'misconfigured' };
  }

  try {
    const token = await accessToken(account);
    const response = await fetch(
      `https://playintegrity.googleapis.com/v1/${env.ANDROID_PACKAGE}:decodeIntegrityToken`,
      {
        method: 'POST',
        headers: {
          authorization: `Bearer ${token}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify({ integrity_token: integrityToken }),
        signal: AbortSignal.timeout(8_000),
      },
    );
    if (!response.ok) {
      console.warn(JSON.stringify({ event: 'attestation_rejected', status: response.status }));
      return { ok: false, reason: 'decode_failed' };
    }

    const body = (await response.json()) as {
      tokenPayloadExternal?: {
        appIntegrity?: { appRecognitionVerdict?: string };
        deviceIntegrity?: { deviceRecognitionVerdict?: string[] };
        requestDetails?: { requestPackageName?: string; nonce?: string };
      };
    };
    const payload = body.tokenPayloadExternal;
    if (!payload) return { ok: false, reason: 'empty_payload' };

    // The token must be for our package, not replayed from another app.
    if (payload.requestDetails?.requestPackageName !== env.ANDROID_PACKAGE) {
      return { ok: false, reason: 'wrong_package' };
    }
    if (payload.appIntegrity?.appRecognitionVerdict !== 'PLAY_RECOGNIZED') {
      return { ok: false, reason: 'app_not_recognized' };
    }
    if (!payload.deviceIntegrity?.deviceRecognitionVerdict?.includes('MEETS_DEVICE_INTEGRITY')) {
      return { ok: false, reason: 'device_integrity' };
    }
    // Consumed last, and only once everything cheaper has passed, so a token
    // that fails another check cannot burn a live challenge.
    const nonce = payload.requestDetails?.nonce;
    if (!nonce || !(await consumeChallenge(env, nonce))) {
      return { ok: false, reason: 'bad_nonce' };
    }
    return { ok: true, verdict: 'verified' };
  } catch (error) {
    // Fails closed. An attestation outage should refuse paid model calls, not
    // hand them out.
    console.warn(JSON.stringify({ event: 'attestation_error', message: String(error) }));
    return { ok: false, reason: 'unavailable' };
  }
}
