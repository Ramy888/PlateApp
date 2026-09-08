import {
  createExecutionContext,
  env,
  fetchMock,
  runInDurableObject,
  waitOnExecutionContext,
} from 'cloudflare:test';
import { afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';

import worker from '../src/index';
import type { QuotaCounter } from '../src/quota';

const BASE = 'https://api.platepatch.app';
const AAI = 'https://agents.assemblyai.com';

let ipCounter = 0;

async function send(request: Request): Promise<Response> {
  const ctx = createExecutionContext();
  const response = await worker.fetch(request, env, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

async function register(): Promise<string> {
  const response = await send(
    new Request(`${BASE}/v1/device`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'cf-connecting-ip': `10.2.${Math.floor(++ipCounter / 250)}.${ipCounter % 250}`,
      },
      body: JSON.stringify({ platform: 'android' }),
    }),
  );
  return ((await response.json()) as { deviceToken: string }).deviceToken;
}

async function quotaStub(token: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  const hash = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
  const row = await env.DB.prepare('SELECT id FROM devices WHERE token_hash = ?')
    .bind(hash)
    .first<{ id: string }>();
  return env.QUOTA.get(env.QUOTA.idFromName(row!.id));
}

function tokenRequest(token: string): Request {
  return new Request(`${BASE}/v1/voice/token`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
      'cf-connecting-ip': `10.3.${Math.floor(++ipCounter / 250)}.${ipCounter % 250}`,
    },
  });
}

function interceptToken(reply: object, status = 200) {
  fetchMock
    .get(AAI)
    .intercept({ path: (p) => p.startsWith('/v1/token'), method: 'GET' })
    .reply(status, reply)
    .times(1);
}

beforeAll(() => {
  fetchMock.activate();
  fetchMock.disableNetConnect();
  // .dev.vars leaves the real key empty, and an empty key means "voice is off".
  // These tests are about what happens when it is on.
  // @ts-expect-error assigning a secret the test controls.
  env.ASSEMBLYAI_API_KEY = 'test-assemblyai-key';
});

afterEach(() => fetchMock.assertNoPendingInterceptors());

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM scan_events'),
    env.DB.prepare('DELETE FROM devices'),
    env.DB.prepare('DELETE FROM rate_limits'),
    env.DB.prepare('DELETE FROM challenges'),
  ]);
});

describe('voice session credentials', () => {
  it('hands back a short-lived token', async () => {
    const device = await register();
    interceptToken({ token: 'aai_temp_abc' });

    const response = await send(tokenRequest(device));
    expect(response.status).toBe(200);

    const body = (await response.json()) as { token: string; expiresAt: number };
    expect(body.token).toBe('aai_temp_abc');
    expect(body.expiresAt).toBeGreaterThan(Math.floor(Date.now() / 1000));
  });

  // The whole reason this endpoint exists.
  it('never returns the account key itself', async () => {
    const device = await register();
    interceptToken({ token: 'aai_temp_abc' });

    const raw = await (await send(tokenRequest(device))).text();
    expect(raw).not.toContain('test-assemblyai-key');
    expect(raw).toContain('aai_temp_abc');
  });

  it('needs a device token', async () => {
    const response = await send(
      new Request(`${BASE}/v1/voice/token`, {
        method: 'POST',
        headers: { 'cf-connecting-ip': '10.11.0.1' },
      }),
    );
    expect(response.status).toBe(401);
  });

  it('spends one scan for the session', async () => {
    const device = await register();
    const stub = await quotaStub(device);
    const before = await runInDurableObject(stub, (i: QuotaCounter) =>
      i.peek(Math.floor(Date.now() / 1000)),
    );

    interceptToken({ token: 'aai_temp_abc' });
    await send(tokenRequest(device));

    const after = await runInDurableObject(stub, (i: QuotaCounter) =>
      i.peek(Math.floor(Date.now() / 1000)),
    );
    expect(before.scans - after.scans).toBe(1);
  });

  it('gives the scan back when the token cannot be minted', async () => {
    const device = await register();
    const stub = await quotaStub(device);
    const before = await runInDurableObject(stub, (i: QuotaCounter) =>
      i.peek(Math.floor(Date.now() / 1000)),
    );

    interceptToken({}, 500);

    const response = await send(tokenRequest(device));
    expect(response.status).toBe(503);

    const after = await runInDurableObject(stub, (i: QuotaCounter) =>
      i.peek(Math.floor(Date.now() / 1000)),
    );
    expect(after.scans).toBe(before.scans);
  });

  it('says voice is unavailable rather than failing oddly when unconfigured', async () => {
    const device = await register();
    const saved = env.ASSEMBLYAI_API_KEY;
    // @ts-expect-error the test is deliberately unsetting a configured secret.
    env.ASSEMBLYAI_API_KEY = '';
    try {
      const response = await send(tokenRequest(device));
      expect(response.status).toBe(503);
      expect(await response.text()).toContain('voice_unavailable');
    } finally {
      // Restored in a finally: the success path spends this too.
      // @ts-expect-error see above.
      env.ASSEMBLYAI_API_KEY = saved;
    }
  });
});
