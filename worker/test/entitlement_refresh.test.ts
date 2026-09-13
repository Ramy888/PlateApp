import { env } from 'cloudflare:test';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import worker from '../src/index';

const BASE = 'https://api.platepatch.app';

let ipCounter = 0;

async function call(
  method: string,
  path: string,
  options: { body?: unknown; token?: string } = {},
): Promise<Response> {
  const headers: Record<string, string> = {
    'cf-connecting-ip': `10.9.${Math.floor(ipCounter / 250)}.${++ipCounter % 250}`,
  };
  if (options.body !== undefined) headers['content-type'] = 'application/json';
  if (options.token) headers.authorization = `Bearer ${options.token}`;
  return worker.fetch(
    new Request(`${BASE}${path}`, {
      method,
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
    }),
    env,
    { waitUntil() {}, passThroughOnException() {} } as ExecutionContext,
  );
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function register(): Promise<string> {
  const response = await call('POST', '/v1/device', { body: { platform: 'android' } });
  expect(response.status).toBe(201);
  return ((await response.json()) as { deviceToken: string }).deviceToken;
}

async function deviceRow(token: string) {
  return env.DB.prepare('SELECT id, rc_user_id FROM devices WHERE token_hash = ?')
    .bind(await sha256Hex(token))
    .first<{ id: string; rc_user_id: string | null }>();
}

/** Stands in for RevenueCat. Records who was asked about. */
const realFetch = globalThis.fetch;
let asked: string[] = [];
let entitled = false;

beforeEach(() => {
  asked = [];
  entitled = false;
  // The secret has to be present or checkEntitlement short-circuits to false
  // and the test would pass for the wrong reason.
  (env as { REVENUECAT_SECRET_KEY?: string }).REVENUECAT_SECRET_KEY = 'sk_test';
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === 'string' ? input : input.toString();
    if (url.includes('api.revenuecat.com')) {
      asked.push(url.split('/').pop()!);
      return new Response(
        JSON.stringify({
          subscriber: entitled
            ? { entitlements: { [env.RC_ENTITLEMENT]: { expires_date: null } } }
            : { entitlements: {} },
        }),
        { status: 200, headers: { 'content-type': 'application/json' } },
      );
    }
    return realFetch(input as RequestInfo, init);
  }) as typeof fetch;
});

afterEach(() => {
  globalThis.fetch = realFetch;
});

describe('entitlement refresh after a purchase', () => {
  it('adopts a RevenueCat id that registration never captured', async () => {
    const token = await register();
    // This is the state seventeen of the first nineteen installs were in: the
    // SDK configures after the app has already registered, so the id is null
    // and the server can never ask RevenueCat anything.
    expect((await deviceRow(token))?.rc_user_id).toBeNull();

    entitled = true;
    const response = await call('POST', '/v1/quota/refresh', {
      token,
      body: { rcUserId: 'rcu_bought_just_now' },
    });

    expect(response.status).toBe(200);
    expect((await response.json() as { pro: boolean }).pro).toBe(true);
    expect(asked).toContain('rcu_bought_just_now');
    // Adopted, so every later request can verify it too.
    expect((await deviceRow(token))?.rc_user_id).toBe('rcu_bought_just_now');
  });

  it('re-checks immediately instead of waiting out the cache', async () => {
    const token = await register();
    // A "not Pro" answer cached a moment ago — which is exactly what someone
    // has when they tap buy.
    await call('POST', '/v1/quota/refresh', { token, body: { rcUserId: 'rcu_buyer' } });
    expect(asked).toEqual(['rcu_buyer']);

    entitled = true;
    const response = await call('POST', '/v1/quota/refresh', {
      token,
      body: { rcUserId: 'rcu_buyer' },
    });
    expect((await response.json() as { pro: boolean }).pro).toBe(true);
    expect(asked).toEqual(['rcu_buyer', 'rcu_buyer']);
  });

  it('never takes the app at its word', async () => {
    const token = await register();
    entitled = false;
    const response = await call('POST', '/v1/quota/refresh', {
      token,
      body: { rcUserId: 'rcu_liar', pro: true },
    });
    expect((await response.json() as { pro: boolean }).pro).toBe(false);
  });

  it('reports the allowance honestly when there is no id to check', async () => {
    const token = await register();
    const response = await call('POST', '/v1/quota/refresh', { token, body: {} });
    expect(response.status).toBe(200);
    expect((await response.json() as { pro: boolean }).pro).toBe(false);
    expect(asked).toEqual([]);
  });
});
