import { createExecutionContext, env, fetchMock, waitOnExecutionContext } from 'cloudflare:test';
import { beforeAll, beforeEach, describe, expect, it } from 'vitest';

import worker from '../src/index';

const BASE = 'https://api.platepatch.app';
const GOOGLE = 'https://www.googleapis.com';

let ipCounter = 0;

async function send(request: Request): Promise<Response> {
  const ctx = createExecutionContext();
  const response = await worker.fetch(request, env, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

/** A registered device that has *not* signed in. */
async function guest(): Promise<string> {
  const response = await send(
    new Request(`${BASE}/v1/device`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'cf-connecting-ip': `10.20.${Math.floor(++ipCounter / 250)}.${ipCounter % 250}`,
      },
      body: JSON.stringify({ platform: 'android' }),
    }),
  );
  return ((await response.json()) as { deviceToken: string }).deviceToken;
}

// ------------------------------------------------------------------ signing

/**
 * A throwaway RSA key standing in for Google's. The Worker fetches the key set
 * from Google, so a test can hand it this one and mint tokens that verify —
 * which is the only way to prove the signature check actually runs rather than
 * being skipped.
 */
let keyPair: CryptoKeyPair;
let jwk: JsonWebKey;

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

const encodeJson = (value: unknown) =>
  b64url(new TextEncoder().encode(JSON.stringify(value)));

async function mintToken(claims: Record<string, unknown>, kid = 'test-key'): Promise<string> {
  const header = encodeJson({ alg: 'RS256', typ: 'JWT', kid });
  const payload = encodeJson(claims);
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    keyPair.privateKey,
    new TextEncoder().encode(`${header}.${payload}`) as BufferSource,
  );
  return `${header}.${payload}.${b64url(new Uint8Array(signature))}`;
}

/**
 * Google's key set, available for as many fetches as happen to occur.
 *
 * The Worker caches these for an hour, so in practice only the first
 * verification in this file reaches the network — which is the behaviour we
 * want in production and the reason this file does not assert on unused
 * interceptors. What the tests assert is the status code.
 */
function interceptKeys(times = 30) {
  fetchMock
    .get(GOOGLE)
    .intercept({ path: (p) => p.includes('/oauth2/v3/certs'), method: 'GET' })
    .reply(200, { keys: [{ ...jwk, kid: 'test-key', alg: 'RS256', use: 'sig' }] })
    .times(times);
}

const AUD = '639333556684-6aqi4fughbj3p264q2lr8325c5j6uug4.apps.googleusercontent.com';

function claims(overrides: Record<string, unknown> = {}) {
  const t = Math.floor(Date.now() / 1000);
  return {
    iss: 'https://accounts.google.com',
    aud: AUD,
    sub: 'google-user-1',
    email: 'someone@example.com',
    name: 'Someone',
    exp: t + 3600,
    ...overrides,
  };
}

function signInRequest(deviceToken: string, idToken: string): Request {
  return new Request(`${BASE}/v1/auth/google`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${deviceToken}`,
      'content-type': 'application/json',
      'cf-connecting-ip': `10.21.${Math.floor(++ipCounter / 250)}.${ipCounter % 250}`,
    },
    body: JSON.stringify({ idToken }),
  });
}

beforeAll(async () => {
  fetchMock.activate();
  fetchMock.disableNetConnect();
  keyPair = (await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true,
    ['sign', 'verify'],
  )) as CryptoKeyPair;
  jwk = (await crypto.subtle.exportKey('jwk', keyPair.publicKey)) as JsonWebKey;
  delete (jwk as { key_ops?: unknown }).key_ops;
  delete (jwk as { ext?: unknown }).ext;
  interceptKeys();
});

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM scan_events'),
    env.DB.prepare('DELETE FROM chat_messages'),
    env.DB.prepare('DELETE FROM devices'),
    env.DB.prepare('DELETE FROM users'),
    env.DB.prepare('DELETE FROM rate_limits'),
    env.DB.prepare('DELETE FROM challenges'),
  ]);
});

describe('signing in with Google', () => {
  it('records the account and binds the device to it', async () => {
    const device = await guest();

    const response = await send(signInRequest(device, await mintToken(claims())));
    expect(response.status).toBe(200);

    const body = (await response.json()) as { user: { id: string; email: string; name: string } };
    expect(body.user.id).toBe('google-user-1');
    expect(body.user.email).toBe('someone@example.com');

    const row = await env.DB.prepare('SELECT email, name FROM users WHERE sub = ?')
      .bind('google-user-1')
      .first<{ email: string; name: string }>();
    expect(row?.email).toBe('someone@example.com');
    expect(row?.name).toBe('Someone');
  });

  // Without the audience check, a token minted for any other Google app would
  // be accepted here. This is the whole point of the web client id.
  it('refuses a token minted for a different app', async () => {
    const device = await guest();

    const response = await send(
      signInRequest(device, await mintToken(claims({ aud: 'someone-elses-app.apps.googleusercontent.com' }))),
    );
    expect(response.status).toBe(401);
    expect(await response.text()).toContain('different app');
  });

  it('refuses an expired token', async () => {
    const device = await guest();

    const t = Math.floor(Date.now() / 1000);
    const response = await send(signInRequest(device, await mintToken(claims({ exp: t - 60 }))));
    expect(response.status).toBe(401);
    expect(await response.text()).toContain('token_expired');
  });

  it('refuses a token from the wrong issuer', async () => {
    const device = await guest();

    const response = await send(
      signInRequest(device, await mintToken(claims({ iss: 'https://evil.example' }))),
    );
    expect(response.status).toBe(401);
  });

  it('refuses a token signed by a key Google does not know', async () => {
    const device = await guest();

    const response = await send(signInRequest(device, await mintToken(claims(), 'other-key')));
    expect(response.status).toBe(401);
  });

  it('refuses something that is not a token at all', async () => {
    const device = await guest();
    const response = await send(signInRequest(device, 'not-a-jwt'));
    expect(response.status).toBe(401);
  });

  it('needs a registered device', async () => {
    const response = await send(
      new Request(`${BASE}/v1/auth/google`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'cf-connecting-ip': '10.22.0.1' },
        body: JSON.stringify({ idToken: 'x' }),
      }),
    );
    expect(response.status).toBe(401);
  });
});

describe('the guest gate', () => {
  it('refuses a chat turn from someone signed out', async () => {
    const device = await guest();
    const response = await send(
      new Request(`${BASE}/v1/chat`, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${device}`,
          'content-type': 'application/json',
          'cf-connecting-ip': '10.23.0.1',
        },
        body: JSON.stringify({ message: 'rice' }),
      }),
    );
    expect(response.status).toBe(401);
    expect(await response.text()).toContain('sign_in_required');
  });

  it('refuses a drawn result from someone signed out', async () => {
    const device = await guest();
    const response = await send(
      new Request(`${BASE}/v1/plate`, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${device}`,
          'content-type': 'application/json',
          'cf-connecting-ip': '10.23.0.2',
        },
        body: JSON.stringify({ foodIds: ['white_rice'], additionId: 'side_salad' }),
      }),
    );
    expect(response.status).toBe(401);
  });

  // Everything that is not a model call has to keep working signed out.
  it('still lets a guest read their quota', async () => {
    const device = await guest();
    const response = await send(
      new Request(`${BASE}/v1/quota`, {
        headers: { authorization: `Bearer ${device}`, 'cf-connecting-ip': '10.23.0.3' },
      }),
    );
    expect(response.status).toBe(200);
  });
});

describe('signing out', () => {
  it('unbinds the device but leaves the account standing', async () => {
    const device = await guest();
    await send(signInRequest(device, await mintToken(claims())));

    const response = await send(
      new Request(`${BASE}/v1/auth/signout`, {
        method: 'POST',
        headers: { authorization: `Bearer ${device}`, 'cf-connecting-ip': '10.24.0.1' },
      }),
    );
    expect(response.status).toBe(200);

    const still = await env.DB.prepare('SELECT sub FROM users WHERE sub = ?')
      .bind('google-user-1')
      .first();
    expect(still).not.toBeNull();

    // And the gate is back up on this device.
    const gated = await send(
      new Request(`${BASE}/v1/chat`, {
        method: 'POST',
        headers: {
          authorization: `Bearer ${device}`,
          'content-type': 'application/json',
          'cf-connecting-ip': '10.24.0.2',
        },
        body: JSON.stringify({ message: 'rice' }),
      }),
    );
    expect(gated.status).toBe(401);
  });
});

describe('deleting everything', () => {
  it('takes the account with the device', async () => {
    const device = await guest();
    await send(signInRequest(device, await mintToken(claims())));

    const response = await send(
      new Request(`${BASE}/v1/device`, {
        method: 'DELETE',
        headers: { authorization: `Bearer ${device}`, 'cf-connecting-ip': '10.25.0.1' },
      }),
    );
    expect(response.status).toBeLessThan(300);

    const user = await env.DB.prepare('SELECT sub FROM users WHERE sub = ?')
      .bind('google-user-1')
      .first();
    expect(user).toBeNull();
  });
});
