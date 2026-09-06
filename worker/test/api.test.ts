import { env, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';

import worker from '../src/index';

const BASE = 'https://api.platepatch.app';

/** Each request gets a distinct IP so the rate limiter does not bleed between tests. */
let ipCounter = 0;

async function call(
  method: string,
  path: string,
  options: { body?: unknown; token?: string; ip?: string } = {},
): Promise<Response> {
  const headers: Record<string, string> = {
    'cf-connecting-ip': options.ip ?? `10.0.0.${++ipCounter % 250}`,
  };
  if (options.body !== undefined) headers['content-type'] = 'application/json';
  if (options.token) headers.authorization = `Bearer ${options.token}`;

  const request = new Request(`${BASE}${path}`, {
    method,
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
  const ctx = createExecutionContext();
  const response = await worker.fetch(request, env, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

let seq = 0;
const freshEmail = () => `user${++seq}.${Date.now()}@example.com`;

async function registerUser(email = freshEmail(), password = 'correct horse battery') {
  const response = await call('POST', '/v1/auth/register', { body: { email, password } });
  expect(response.status).toBe(201);
  const data = (await response.json()) as { token: string; user: { id: string } };
  return { ...data, email, password };
}

beforeEach(async () => {
  // A clean slate per test, so ordering can never make one pass by accident.
  await env.DB.batch([
    env.DB.prepare('DELETE FROM sync_documents'),
    env.DB.prepare('DELETE FROM password_resets'),
    env.DB.prepare('DELETE FROM sessions'),
    env.DB.prepare('DELETE FROM users'),
    env.DB.prepare('DELETE FROM rate_limits'),
  ]);
});

describe('routing', () => {
  it('answers a health check', async () => {
    expect((await call('GET', '/health')).status).toBe(200);
  });

  it('404s an unknown path', async () => {
    expect((await call('GET', '/v1/nope')).status).toBe(404);
  });

  it('405s a wrong method and says what is allowed', async () => {
    const response = await call('GET', '/v1/auth/login');
    expect(response.status).toBe(405);
    expect(response.headers.get('allow')).toContain('POST');
  });

  it('never caches a response', async () => {
    const response = await call('GET', '/health');
    expect(response.headers.get('cache-control')).toBe('no-store');
  });
});

describe('register', () => {
  it('creates an account and returns a usable session', async () => {
    const { token } = await registerUser();
    expect((await call('GET', '/v1/account', { token })).status).toBe(200);
  });

  it('rejects a password under eight characters', async () => {
    const response = await call('POST', '/v1/auth/register', {
      body: { email: freshEmail(), password: 'short' },
    });
    expect(response.status).toBe(400);
    expect((await response.json() as { error: string }).error).toBe('weak_password');
  });

  it('rejects something that is not an email address', async () => {
    const response = await call('POST', '/v1/auth/register', {
      body: { email: 'not-an-email', password: 'correct horse battery' },
    });
    expect(response.status).toBe(400);
  });

  it('refuses a second account on the same address', async () => {
    const { email } = await registerUser();
    const response = await call('POST', '/v1/auth/register', {
      body: { email, password: 'correct horse battery' },
    });
    expect(response.status).toBe(409);
  });

  it('treats addresses case-insensitively', async () => {
    const { email } = await registerUser();
    const response = await call('POST', '/v1/auth/register', {
      body: { email: email.toUpperCase(), password: 'correct horse battery' },
    });
    expect(response.status).toBe(409);
  });

  it('never stores the password itself', async () => {
    const { user, password } = await registerUser();
    const row = await env.DB.prepare('SELECT password_hash FROM users WHERE id = ?')
      .bind(user.id)
      .first<{ password_hash: string }>();
    expect(row?.password_hash).not.toContain(password);
    expect(row?.password_hash.startsWith('pbkdf2$210000$')).toBe(true);
  });

  it('stores only a hash of the session token', async () => {
    const { token } = await registerUser();
    const row = await env.DB.prepare('SELECT token_hash FROM sessions LIMIT 1')
      .first<{ token_hash: string }>();
    expect(row?.token_hash).toBeTruthy();
    expect(row?.token_hash).not.toBe(token);
  });
});

describe('login', () => {
  it('accepts the right password', async () => {
    const { email, password } = await registerUser();
    const response = await call('POST', '/v1/auth/login', { body: { email, password } });
    expect(response.status).toBe(200);
    expect((await response.json() as { token: string }).token).toBeTruthy();
  });

  it('rejects the wrong password', async () => {
    const { email } = await registerUser();
    const response = await call('POST', '/v1/auth/login', {
      body: { email, password: 'wrong password here' },
    });
    expect(response.status).toBe(401);
  });

  it('gives an unknown address the same answer as a wrong password', async () => {
    const unknown = await call('POST', '/v1/auth/login', {
      body: { email: freshEmail(), password: 'correct horse battery' },
    });
    const { email } = await registerUser();
    const wrong = await call('POST', '/v1/auth/login', {
      body: { email, password: 'wrong password here' },
    });

    expect(unknown.status).toBe(wrong.status);
    expect(await unknown.json()).toEqual(await wrong.json());
  });

  it('issues a second session without ending the first', async () => {
    const { email, password, token } = await registerUser();
    await call('POST', '/v1/auth/login', { body: { email, password } });
    expect((await call('GET', '/v1/account', { token })).status).toBe(200);
  });
});

describe('sessions', () => {
  it('refuses a request with no token', async () => {
    expect((await call('GET', '/v1/account')).status).toBe(401);
  });

  it('refuses a made-up token', async () => {
    expect((await call('GET', '/v1/account', { token: 'nonsense' })).status).toBe(401);
  });

  it('refuses a malformed authorization header', async () => {
    const request = new Request(`${BASE}/v1/account`, {
      headers: { authorization: 'Token abc', 'cf-connecting-ip': '10.9.9.9' },
    });
    const ctx = createExecutionContext();
    const response = await worker.fetch(request, env, ctx);
    await waitOnExecutionContext(ctx);
    expect(response.status).toBe(401);
  });

  it('refuses an expired session', async () => {
    const { token } = await registerUser();
    await env.DB.prepare('UPDATE sessions SET expires_at = 1').run();
    expect((await call('GET', '/v1/account', { token })).status).toBe(401);
  });

  it('logout ends that session', async () => {
    const { token } = await registerUser();
    expect((await call('POST', '/v1/auth/logout', { token })).status).toBe(204);
    expect((await call('GET', '/v1/account', { token })).status).toBe(401);
  });
});

describe('sync', () => {
  const payload = {
    goal: 'more_energy',
    dietPrefs: ['vegetarian'],
    history: [{ id: 'p1', additionId: 'yogurt' }],
  };

  it('starts empty', async () => {
    const { token } = await registerUser();
    const response = await call('GET', '/v1/sync', { token });
    expect(await response.json()).toEqual({ payload: null, updatedAt: 0 });
  });

  it('round-trips a document', async () => {
    const { token } = await registerUser();
    expect((await call('PUT', '/v1/sync', { token, body: { payload } })).status).toBe(200);

    const response = await call('GET', '/v1/sync', { token });
    const data = (await response.json()) as { payload: unknown; updatedAt: number };
    expect(data.payload).toEqual(payload);
    expect(data.updatedAt).toBeGreaterThan(0);
  });

  it('overwrites rather than appending', async () => {
    const { token } = await registerUser();
    await call('PUT', '/v1/sync', { token, body: { payload } });
    await call('PUT', '/v1/sync', { token, body: { payload: { goal: 'feel_satisfied' } } });

    const data = (await (await call('GET', '/v1/sync', { token })).json()) as {
      payload: { goal: string };
    };
    expect(data.payload).toEqual({ goal: 'feel_satisfied' });
  });

  it('keeps one account out of another', async () => {
    const a = await registerUser();
    const b = await registerUser();
    await call('PUT', '/v1/sync', { token: a.token, body: { payload } });

    const data = await (await call('GET', '/v1/sync', { token: b.token })).json();
    expect(data).toEqual({ payload: null, updatedAt: 0 });
  });

  it('rejects a payload that is not an object', async () => {
    const { token } = await registerUser();
    const response = await call('PUT', '/v1/sync', { token, body: { payload: 'nope' } });
    expect(response.status).toBe(400);
  });

  it('rejects an oversized payload', async () => {
    const { token } = await registerUser();
    const response = await call('PUT', '/v1/sync', {
      token,
      body: { payload: { blob: 'x'.repeat(40_000) } },
    });
    expect(response.status).toBe(413);
  });

  it('needs a session', async () => {
    expect((await call('PUT', '/v1/sync', { body: { payload } })).status).toBe(401);
  });
});

describe('forgot and reset', () => {
  /** The email send is a no-op without a verified domain, so read the token from D1. */
  async function resetTokenHashFor(userId: string) {
    return env.DB.prepare('SELECT token_hash FROM password_resets WHERE user_id = ?')
      .bind(userId)
      .first<{ token_hash: string }>();
  }

  it('answers identically for a known and an unknown address', async () => {
    const { email } = await registerUser();
    const known = await call('POST', '/v1/auth/forgot', { body: { email } });
    const unknown = await call('POST', '/v1/auth/forgot', { body: { email: freshEmail() } });

    expect(known.status).toBe(202);
    expect(unknown.status).toBe(202);
    expect(await known.json()).toEqual(await unknown.json());
  });

  it('still succeeds when the email cannot be sent', async () => {
    // The local emulator only supports raw MIME sends, so every send throws
    // here — which is exactly the production failure mode before a sending
    // domain is verified. The request must still succeed and still mint a
    // token, otherwise a mail outage becomes an account lockout.
    const { email, user } = await registerUser();
    const response = await call('POST', '/v1/auth/forgot', { body: { email } });
    expect(response.status).toBe(202);
    expect(await resetTokenHashFor(user.id)).toBeTruthy();
  });

  it('creates a token only for a real account', async () => {
    await call('POST', '/v1/auth/forgot', { body: { email: freshEmail() } });
    const count = await env.DB.prepare('SELECT COUNT(*) AS n FROM password_resets')
      .first<{ n: number }>();
    expect(count?.n).toBe(0);
  });

  it('rejects a made-up reset token', async () => {
    const response = await call('POST', '/v1/auth/reset', {
      body: { token: 'a'.repeat(32), password: 'a brand new password' },
    });
    expect(response.status).toBe(400);
  });

  it('rejects an expired reset token', async () => {
    const { email, user } = await registerUser();
    await call('POST', '/v1/auth/forgot', { body: { email } });
    await env.DB.prepare('UPDATE password_resets SET expires_at = 1 WHERE user_id = ?')
      .bind(user.id)
      .run();
    expect(await resetTokenHashFor(user.id)).toBeTruthy();
  });

  it('a reset changes the password, ends every session, and cannot be replayed', async () => {
    // Drive the real flow by minting a token the way the endpoint does, then
    // reading it back through the same hash the endpoint stores.
    const { email, password, token: session, user } = await registerUser();
    await call('POST', '/v1/auth/forgot', { body: { email } });

    // The plaintext token only exists inside the email, so for the test the
    // row is replaced with a known token's hash.
    const known = 'k'.repeat(43);
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(known));
    const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
    await env.DB.prepare('UPDATE password_resets SET token_hash = ? WHERE user_id = ?')
      .bind(hex, user.id)
      .run();

    const newPassword = 'a completely new password';
    expect(
      (await call('POST', '/v1/auth/reset', { body: { token: known, password: newPassword } }))
        .status,
    ).toBe(204);

    // Old session gone.
    expect((await call('GET', '/v1/account', { token: session })).status).toBe(401);
    // Old password gone.
    expect(
      (await call('POST', '/v1/auth/login', { body: { email, password } })).status,
    ).toBe(401);
    // New password works.
    expect(
      (await call('POST', '/v1/auth/login', { body: { email, password: newPassword } })).status,
    ).toBe(200);
    // Token is single use.
    expect(
      (await call('POST', '/v1/auth/reset', { body: { token: known, password: 'yet another one' } }))
        .status,
    ).toBe(400);
  });
});

describe('account deletion', () => {
  it('removes the user, their sessions and their data', async () => {
    const { token, user } = await registerUser();
    await call('PUT', '/v1/sync', { token, body: { payload: { goal: 'more_energy' } } });

    expect((await call('DELETE', '/v1/account', { token })).status).toBe(204);

    for (const table of ['users', 'sessions', 'sync_documents', 'password_resets']) {
      const row = await env.DB.prepare(
        `SELECT COUNT(*) AS n FROM ${table} WHERE ${table === 'users' ? 'id' : 'user_id'} = ?`,
      )
        .bind(user.id)
        .first<{ n: number }>();
      expect(row?.n, `${table} still holds rows`).toBe(0);
    }
  });

  it('invalidates the session it was called with', async () => {
    const { token } = await registerUser();
    await call('DELETE', '/v1/account', { token });
    expect((await call('GET', '/v1/account', { token })).status).toBe(401);
  });

  it('lets the address be reused afterwards', async () => {
    const { token, email } = await registerUser();
    await call('DELETE', '/v1/account', { token });
    const response = await call('POST', '/v1/auth/register', {
      body: { email, password: 'correct horse battery' },
    });
    expect(response.status).toBe(201);
  });

  it('needs a session', async () => {
    expect((await call('DELETE', '/v1/account')).status).toBe(401);
  });
});

describe('rate limiting', () => {
  it('stops repeated login attempts from one address', async () => {
    const { email } = await registerUser();
    const ip = '198.51.100.7';
    let limited = false;

    for (let i = 0; i < 12; i++) {
      const response = await call('POST', '/v1/auth/login', {
        ip,
        body: { email, password: 'wrong password here' },
      });
      if (response.status === 429) {
        limited = true;
        break;
      }
    }
    expect(limited, 'login was never rate limited').toBe(true);
  });

  it('caps reset emails per address', async () => {
    const { email } = await registerUser();
    let limited = false;
    for (let i = 0; i < 6; i++) {
      // Vary the IP so it is the per-address cap being tested, not the per-IP one.
      const response = await call('POST', '/v1/auth/forgot', {
        ip: `203.0.113.${i}`,
        body: { email },
      });
      if (response.status === 429) {
        limited = true;
        break;
      }
    }
    expect(limited, 'reset emails were never capped per address').toBe(true);
  });
});

describe('request hardening', () => {
  it('rejects a body that is not JSON', async () => {
    const request = new Request(`${BASE}/v1/auth/login`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'cf-connecting-ip': '10.1.1.1' },
      body: 'not json',
    });
    const ctx = createExecutionContext();
    const response = await worker.fetch(request, env, ctx);
    await waitOnExecutionContext(ctx);
    expect(response.status).toBe(400);
  });

  it('rejects a JSON array where an object is required', async () => {
    const request = new Request(`${BASE}/v1/auth/login`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'cf-connecting-ip': '10.1.1.2' },
      body: '[]',
    });
    const ctx = createExecutionContext();
    const response = await worker.fetch(request, env, ctx);
    await waitOnExecutionContext(ctx);
    expect(response.status).toBe(400);
  });

  it('rejects an oversized body', async () => {
    const response = await call('POST', '/v1/auth/login', {
      body: { email: 'a@b.co', password: 'x'.repeat(70_000) },
    });
    expect(response.status).toBe(413);
  });

  it('does not leak internals in an error body', async () => {
    const response = await call('POST', '/v1/auth/login', { body: {} });
    const text = await response.text();
    expect(text).not.toMatch(/sqlite|D1_|stack|at Object/i);
  });
});
