import { authenticateDevice, quotaFor } from './device';
import { ApiError, json, readJson, requireString } from './http';

/**
 * Signing in with Google.
 *
 * The app sends the ID token Google gave it; this verifies that token against
 * Google's own public keys and, only then, records who it belongs to. The
 * client secret is never involved — verification needs public keys, not a
 * secret, so there is nothing here worth stealing.
 *
 * The account is the identity and the device is a session against it. That is
 * what makes the allowance follow the person: a reinstall is a new device but
 * the same account, so it no longer hands out a fresh free week.
 */

const JWKS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
const ISSUERS = new Set(['accounts.google.com', 'https://accounts.google.com']);

/** Keys change rarely; refetching per request would be a needless dependency. */
let cachedKeys: { at: number; keys: JsonWebKey[] } | null = null;
const KEY_TTL_SECONDS = 60 * 60;

const now = () => Math.floor(Date.now() / 1000);

interface IdTokenClaims {
  iss?: string;
  aud?: string;
  sub?: string;
  exp?: number;
  email?: string;
  name?: string;
  email_verified?: boolean;
}

function decodeSegment(segment: string): Record<string, unknown> {
  const padded = segment.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(padded + '='.repeat((4 - (padded.length % 4)) % 4));
  return JSON.parse(decodeURIComponent(escape(binary))) as Record<string, unknown>;
}

function toBytes(segment: string): Uint8Array {
  const padded = segment.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(padded + '='.repeat((4 - (padded.length % 4)) % 4));
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

async function googleKeys(t: number): Promise<JsonWebKey[]> {
  if (cachedKeys && t - cachedKeys.at < KEY_TTL_SECONDS) return cachedKeys.keys;
  const response = await fetch(JWKS_URL);
  if (!response.ok) throw new ApiError(503, 'sign_in_unavailable', 'Could not reach Google.');
  const body = (await response.json()) as { keys: JsonWebKey[] };
  cachedKeys = { at: t, keys: body.keys ?? [] };
  return cachedKeys.keys;
}

/**
 * Verifies the token end to end: Google's signature, our audience, Google's
 * issuer, and the expiry. Fails closed — an unverifiable token is refused, not
 * trusted with a warning.
 */
export async function verifyGoogleIdToken(
  env: Env,
  idToken: string,
  t: number,
): Promise<IdTokenClaims> {
  if (!env.GOOGLE_CLIENT_ID) {
    throw new ApiError(503, 'sign_in_unavailable', 'Signing in is not available right now.');
  }

  const parts = idToken.split('.');
  if (parts.length !== 3) {
    throw new ApiError(401, 'invalid_token', 'That sign-in could not be verified.');
  }

  let header: Record<string, unknown>;
  let claims: IdTokenClaims;
  try {
    header = decodeSegment(parts[0]);
    claims = decodeSegment(parts[1]) as IdTokenClaims;
  } catch {
    throw new ApiError(401, 'invalid_token', 'That sign-in could not be verified.');
  }

  const jwk = (await googleKeys(t)).find(
    (k) => (k as { kid?: string }).kid === header.kid,
  );
  if (!jwk) {
    throw new ApiError(401, 'invalid_token', 'That sign-in could not be verified.');
  }

  const key = await crypto.subtle.importKey(
    'jwk',
    jwk,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );
  const signed = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const ok = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    toBytes(parts[2]) as BufferSource,
    signed as BufferSource,
  );
  if (!ok) {
    throw new ApiError(401, 'invalid_token', 'That sign-in could not be verified.');
  }

  // Checked after the signature, so a forged token never reaches these.
  if (!claims.iss || !ISSUERS.has(claims.iss)) {
    throw new ApiError(401, 'invalid_token', 'That sign-in could not be verified.');
  }
  // The audience must be *our* client. Without this, a token minted for any
  // other Google app would be accepted here.
  if (claims.aud !== env.GOOGLE_CLIENT_ID) {
    throw new ApiError(401, 'invalid_token', 'That sign-in was for a different app.');
  }
  if (!claims.exp || claims.exp <= t) {
    throw new ApiError(401, 'token_expired', 'That sign-in has expired. Try again.');
  }
  if (!claims.sub) {
    throw new ApiError(401, 'invalid_token', 'That sign-in could not be verified.');
  }
  return claims;
}

export async function postAuthGoogle(request: Request, env: Env): Promise<Response> {
  const t = now();
  const device = await authenticateDevice(request, env, t);

  const body = await readJson(request);
  const idToken = requireString(body, 'idToken', { max: 4096 });
  const claims = await verifyGoogleIdToken(env, idToken, t);

  const sub = claims.sub!;
  const known = await env.DB.prepare('SELECT sub FROM users WHERE sub = ?')
    .bind(sub)
    .first<{ sub: string }>();

  await env.DB.prepare(
    `INSERT INTO users (sub, email, name, created_at, last_seen_at)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(sub) DO UPDATE SET email = ?, name = ?, last_seen_at = ?`,
  )
    .bind(sub, claims.email ?? null, claims.name ?? null, t, t,
          claims.email ?? null, claims.name ?? null, t)
    .run();

  await env.DB.prepare('UPDATE devices SET user_id = ? WHERE id = ?').bind(sub, device.id).run();

  // A first sign-in carries the trial this phone had already started, rather
  // than restarting it. Someone who has been trying the app for three days
  // should not be handed a fresh week for signing in, and should not lose the
  // four days they have left either.
  if (!known) {
    const from = await quotaFor(env, device.id).peek(t);
    await quotaFor(env, sub).adoptTrial(from.trialEndsAt ?? null, t);
  }

  const quota = await quotaFor(env, sub).peek(t);
  return json({
    user: { id: sub, email: claims.email ?? '', name: claims.name ?? '' },
    quota,
  });
}

/**
 * Ends the session on this device. The account and its allowance survive —
 * signing out is not deleting, and a returning user should find their week
 * where they left it.
 */
export async function postAuthSignOut(request: Request, env: Env): Promise<Response> {
  const t = now();
  const device = await authenticateDevice(request, env, t);
  await env.DB.prepare('UPDATE devices SET user_id = NULL WHERE id = ?').bind(device.id).run();
  return json({ ok: true });
}
