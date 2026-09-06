import {
  createExecutionContext,
  env,
  runInDurableObject,
  waitOnExecutionContext,
} from 'cloudflare:test';
import { beforeEach, describe, expect, it } from 'vitest';

import worker from '../src/index';
import type { QuotaCounter } from '../src/quota';

const BASE = 'https://api.platepatch.app';
const DAY = 24 * 60 * 60;
const MONTH = 30 * DAY;

let ipCounter = 0;

async function call(
  method: string,
  path: string,
  options: { body?: unknown; token?: string; ip?: string } = {},
): Promise<Response> {
  const headers: Record<string, string> = {
    'cf-connecting-ip': options.ip ?? `10.0.${Math.floor(ipCounter / 250)}.${++ipCounter % 250}`,
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

interface Quota {
  scans: number;
  previews: number;
  resetsAt: number;
  pro: boolean;
  trialActive: boolean;
  trialEndsAt: number;
  trialDaysLeft: number;
}

async function register(platform = 'android') {
  const response = await call('POST', '/v1/device', { body: { platform } });
  expect(response.status).toBe(201);
  return (await response.json()) as { deviceToken: string; quota: Quota };
}

/** The Durable Object behind a device, for testing the counter directly. */
async function quotaStub(deviceToken: string) {
  const hash = await sha256Hex(deviceToken);
  const row = await env.DB.prepare('SELECT id FROM devices WHERE token_hash = ?')
    .bind(hash)
    .first<{ id: string }>();
  const id = env.QUOTA.idFromName(row!.id);
  return env.QUOTA.get(id);
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM reports'),
    env.DB.prepare('DELETE FROM scan_events'),
    env.DB.prepare('DELETE FROM devices'),
    env.DB.prepare('DELETE FROM rate_limits'),
    env.DB.prepare('DELETE FROM challenges'),
  ]);
});

describe('health', () => {
  it('reports whether attestation is actually enforced', async () => {
    const response = await call('GET', '/health');
    const body = (await response.json()) as { ok: boolean; attestation: string };
    expect(body.ok).toBe(true);
    // Without a service account configured, this must say so out loud rather
    // than look healthy while verifying nothing.
    expect(body.attestation).toBe('skipped');
  });

  it('names the models it will call', async () => {
    const body = (await (await call('GET', '/health')).json()) as {
      models: { vision: string; image: string };
    };
    expect(body.models.vision).toBe('gemini-3.7-flash');
    expect(body.models.image).toBe('gemini-3.1-flash-image');
  });
});

describe('device registration', () => {
  it('issues a token and a free allowance', async () => {
    const { deviceToken, quota } = await register();
    expect(deviceToken).toBeTruthy();
    expect(quota).toMatchObject({ scans: 5, previews: 2, pro: false, trialActive: true });
    expect(quota.trialDaysLeft).toBe(7);
  });

  it('stores only a hash of the token', async () => {
    const { deviceToken } = await register();
    const row = await env.DB.prepare('SELECT token_hash FROM devices').first<{
      token_hash: string;
    }>();
    expect(row?.token_hash).not.toBe(deviceToken);
    expect(row?.token_hash).toBe(await sha256Hex(deviceToken));
  });

  it('rejects an unknown platform', async () => {
    const response = await call('POST', '/v1/device', { body: { platform: 'windows' } });
    expect(response.status).toBe(400);
  });

  it('gives each registration its own token', async () => {
    const a = await register();
    const b = await register();
    expect(a.deviceToken).not.toBe(b.deviceToken);
  });

  it('caps registrations from one address', async () => {
    const ip = '198.51.100.20';
    let limited = false;
    for (let i = 0; i < 12; i++) {
      const response = await call('POST', '/v1/device', { ip, body: { platform: 'android' } });
      if (response.status === 429) {
        limited = true;
        break;
      }
    }
    expect(limited, 'registration was never rate limited').toBe(true);
  });
});

describe('challenges', () => {
  it('issues a single-use nonce', async () => {
    const response = await call('POST', '/v1/challenge');
    expect(response.status).toBe(201);
    const body = (await response.json()) as { nonce: string; expiresAt: number };
    expect(body.nonce.length).toBeGreaterThan(20);
    expect(body.expiresAt).toBeGreaterThan(Math.floor(Date.now() / 1000));
  });

  it('never issues the same nonce twice', async () => {
    const a = (await (await call('POST', '/v1/challenge')).json()) as { nonce: string };
    const b = (await (await call('POST', '/v1/challenge')).json()) as { nonce: string };
    expect(a.nonce).not.toBe(b.nonce);
  });

  it('stores it so it can be consumed exactly once', async () => {
    const { nonce } = (await (await call('POST', '/v1/challenge')).json()) as {
      nonce: string;
    };
    const row = await env.DB.prepare(
      'SELECT used_at FROM challenges WHERE nonce = ?',
    )
      .bind(nonce)
      .first<{ used_at: number | null }>();
    expect(row).not.toBeNull();
    expect(row?.used_at).toBeNull();
  });

  it('caps how many can be requested from one address', async () => {
    const ip = '198.51.100.55';
    let limited = false;
    for (let i = 0; i < 35 && !limited; i++) {
      if ((await call('POST', '/v1/challenge', { ip })).status === 429) limited = true;
    }
    expect(limited).toBe(true);
  });
});

describe('quota endpoint', () => {
  it('needs a device token', async () => {
    expect((await call('GET', '/v1/quota')).status).toBe(401);
  });

  it('rejects a made-up token', async () => {
    expect((await call('GET', '/v1/quota', { token: 'nonsense' })).status).toBe(401);
  });

  it('reports the allowance without spending it', async () => {
    const { deviceToken } = await register();
    for (let i = 0; i < 3; i++) {
      const quota = (await (await call('GET', '/v1/quota', { token: deviceToken })).json()) as Quota;
      expect(quota.scans).toBe(5);
    }
  });
});

describe('the seven-day trial', () => {
  it('a new device can scan straight away', async () => {
    const { deviceToken } = await register();
    const stub = await quotaStub(deviceToken);
    await runInDurableObject(stub, async (instance: QuotaCounter) => {
      const t = Math.floor(Date.now() / 1000);
      const first = await instance.spend('scan', t);
      expect(first.ok).toBe(true);
      expect(first.quota.trialActive).toBe(true);
      expect(first.quota.scans).toBe(4);
    });
  });

  it('the daily cap refills the next day', async () => {
    const { deviceToken } = await register();
    const stub = await quotaStub(deviceToken);
    await runInDurableObject(stub, async (instance: QuotaCounter) => {
      const t = Math.floor(Date.now() / 1000);
      for (let i = 0; i < 5; i++) expect((await instance.spend('scan', t)).ok).toBe(true);
      expect((await instance.spend('scan', t)).ok).toBe(false);

      // A day later, and still inside the week.
      expect((await instance.peek(t + DAY + 1)).scans).toBe(5);
    });
  });

  it('scanning stops when the seven days are up', async () => {
    const { deviceToken } = await register();
    const stub = await quotaStub(deviceToken);
    await runInDurableObject(stub, async (instance: QuotaCounter) => {
      const t = Math.floor(Date.now() / 1000);
      const after = t + 7 * DAY + 1;

      const quota = await instance.peek(after);
      expect(quota.trialActive).toBe(false);
      expect(quota.scans).toBe(0);
      expect(quota.previews).toBe(0);
      expect((await instance.spend('scan', after)).ok).toBe(false);
    });
  });

  it('counts down the days left', async () => {
    const { deviceToken } = await register();
    const stub = await quotaStub(deviceToken);
    await runInDurableObject(stub, async (instance: QuotaCounter) => {
      const t = Math.floor(Date.now() / 1000);
      expect((await instance.peek(t)).trialDaysLeft).toBe(7);
      expect((await instance.peek(t + 3 * DAY)).trialDaysLeft).toBe(4);
      expect((await instance.peek(t + 7 * DAY)).trialDaysLeft).toBe(0);
    });
  });

  it('the trial includes previews, sparingly', async () => {
    const { deviceToken } = await register();
    const stub = await quotaStub(deviceToken);
    await runInDurableObject(stub, async (instance: QuotaCounter) => {
      const t = Math.floor(Date.now() / 1000);
      expect((await instance.spend('preview', t)).ok).toBe(true);
      expect((await instance.spend('preview', t)).ok).toBe(true);
      expect((await instance.spend('preview', t)).ok).toBe(false);
    });
  });

  it('the clock starts on first use, not at install', async () => {
    // Someone who downloads and forgets should not lose their week.
    const { deviceToken } = await register();
    const stub = await quotaStub(deviceToken);
    await runInDurableObject(stub, async (instance: QuotaCounter) => {
      const first = await instance.peek(Math.floor(Date.now() / 1000));
      expect(first.trialEndsAt).toBeGreaterThan(Math.floor(Date.now() / 1000));
    });
  });
});

describe('subscribing', () => {
  it('replaces the daily trial with a monthly allowance', async () => {
    const { deviceToken } = await register();
    const stub = await quotaStub(deviceToken);
    await runInDurableObject(stub, async (instance: QuotaCounter) => {
      const t = Math.floor(Date.now() / 1000);
      const quota = await instance.setPro(true, t);
      expect(quota).toMatchObject({ scans: 30, previews: 10, pro: true, trialActive: false });
      expect(quota.resetsAt).toBe(t + MONTH);
    });
  });

  it('brings scanning back after the trial has ended', async () => {
    const { deviceToken } = await register();
    const stub = await quotaStub(deviceToken);
    await runInDurableObject(stub, async (instance: QuotaCounter) => {
      const t = Math.floor(Date.now() / 1000);
      const after = t + 8 * DAY;
      expect((await instance.spend('scan', after)).ok).toBe(false);

      await instance.setPro(true, after);
      expect((await instance.spend('scan', after)).ok).toBe(true);
    });
  });

  it('cancelling does not hand out a fresh seven days', async () => {
    // The trial start is never reset, or subscribing and cancelling would be a
    // way to scan free forever.
    const { deviceToken } = await register();
    const stub = await quotaStub(deviceToken);
    await runInDurableObject(stub, async (instance: QuotaCounter) => {
      const t = Math.floor(Date.now() / 1000);
      const later = t + 20 * DAY;
      await instance.setPro(true, later);
      const quota = await instance.setPro(false, later);

      expect(quota.trialActive).toBe(false);
      expect(quota.scans).toBe(0);
    });
  });

  it('a repeated check does not hand back a spent allowance', async () => {
    const { deviceToken } = await register();
    const stub = await quotaStub(deviceToken);
    await runInDurableObject(stub, async (instance: QuotaCounter) => {
      const t = Math.floor(Date.now() / 1000);
      await instance.setPro(true, t);
      await instance.spend('scan', t);
      const quota = await instance.setPro(true, t + 3600);
      expect(quota.scans).toBe(29);
    });
  });

  it('is re-checked at most once an hour', async () => {
    const { deviceToken } = await register();
    const stub = await quotaStub(deviceToken);
    await runInDurableObject(stub, async (instance: QuotaCounter) => {
      const t = Math.floor(Date.now() / 1000);
      await instance.setPro(false, t);
      expect(await instance.needsEntitlementCheck(t + 60)).toBe(false);
      expect(await instance.needsEntitlementCheck(t + 3601)).toBe(true);
    });
  });
});

describe('quota bookkeeping', () => {
  it('refunds a unit when the model fails after it was taken', async () => {
    const { deviceToken } = await register();
    const stub = await quotaStub(deviceToken);
    await runInDurableObject(stub, async (instance: QuotaCounter) => {
      const t = Math.floor(Date.now() / 1000);
      await instance.spend('scan', t);
      expect((await instance.peek(t)).scans).toBe(4);
      await instance.refund('scan', t);
      expect((await instance.peek(t)).scans).toBe(5);
    });
  });

  it('a refund cannot mint allowance out of nothing', async () => {
    const { deviceToken } = await register();
    const stub = await quotaStub(deviceToken);
    await runInDurableObject(stub, async (instance: QuotaCounter) => {
      const t = Math.floor(Date.now() / 1000);
      await instance.refund('scan', t);
      await instance.refund('scan', t);
      expect((await instance.peek(t)).scans).toBe(5);
    });
  });

  it('keeps one device out of another', async () => {
    const a = await register();
    const b = await register();
    const stubA = await quotaStub(a.deviceToken);
    await runInDurableObject(stubA, async (instance: QuotaCounter) => {
      const t = Math.floor(Date.now() / 1000);
      for (let i = 0; i < 5; i++) await instance.spend('scan', t);
    });

    const quotaB = (await (await call('GET', '/v1/quota', { token: b.deviceToken })).json()) as Quota;
    expect(quotaB.scans).toBe(5);
  });
});

describe('reporting AI results', () => {
  it('accepts a report and stores it', async () => {
    const { deviceToken } = await register();
    const response = await call('POST', '/v1/report', {
      token: deviceToken,
      body: { targetType: 'preview', targetId: 'sc_1', reason: 'unrealistic', note: 'not my plate' },
    });
    expect(response.status).toBe(202);

    const row = await env.DB.prepare('SELECT reason, target_type FROM reports').first<{
      reason: string;
      target_type: string;
    }>();
    expect(row).toMatchObject({ reason: 'unrealistic', target_type: 'preview' });
  });

  it('normalises an unknown reason rather than rejecting it', async () => {
    const { deviceToken } = await register();
    await call('POST', '/v1/report', {
      token: deviceToken,
      body: { targetType: 'scan', targetId: 'sc_2', reason: 'something else entirely' },
    });
    const row = await env.DB.prepare('SELECT reason FROM reports').first<{ reason: string }>();
    expect(row?.reason).toBe('other');
  });

  it('never fails in front of the user, even on a malformed body', async () => {
    // Reporting offensive content must not be the thing that errors.
    const { deviceToken } = await register();
    const response = await call('POST', '/v1/report', { token: deviceToken, body: {} });
    expect(response.status).toBe(202);
  });

  it('still needs a registered device', async () => {
    expect((await call('POST', '/v1/report', { body: { targetId: 'x' } })).status).toBe(401);
  });
});

describe('deleting a device', () => {
  it('removes the row, its events and its reports', async () => {
    const { deviceToken } = await register();
    await call('POST', '/v1/report', {
      token: deviceToken,
      body: { targetType: 'scan', targetId: 'sc_3', reason: 'other' },
    });

    expect((await call('DELETE', '/v1/device', { token: deviceToken })).status).toBe(204);

    for (const table of ['devices', 'reports', 'scan_events']) {
      const row = await env.DB.prepare(`SELECT COUNT(*) AS n FROM ${table}`).first<{ n: number }>();
      expect(row?.n, `${table} still has rows`).toBe(0);
    }
  });

  it('invalidates the token it was called with', async () => {
    const { deviceToken } = await register();
    await call('DELETE', '/v1/device', { token: deviceToken });
    expect((await call('GET', '/v1/quota', { token: deviceToken })).status).toBe(401);
  });

  it('clears the quota, so a re-register does not inherit a spent one', async () => {
    const { deviceToken } = await register();
    const stub = await quotaStub(deviceToken);
    await runInDurableObject(stub, async (instance: QuotaCounter) => {
      const t = Math.floor(Date.now() / 1000);
      for (let i = 0; i < 5; i++) await instance.spend('scan', t);
    });

    await call('DELETE', '/v1/device', { token: deviceToken });

    await runInDurableObject(stub, async (instance: QuotaCounter) => {
      expect((await instance.peek(Math.floor(Date.now() / 1000))).scans).toBe(5);
    });
  });
});

describe('routing', () => {
  it('404s an unknown path', async () => {
    expect((await call('GET', '/v1/nope')).status).toBe(404);
  });

  it('405s a wrong method and says what is allowed', async () => {
    const response = await call('PUT', '/v1/quota');
    expect(response.status).toBe(405);
    expect(response.headers.get('allow')).toContain('GET');
  });

  it('never caches', async () => {
    expect((await call('GET', '/health')).headers.get('cache-control')).toBe('no-store');
  });

  it('does not leak internals in an error body', async () => {
    const text = await (await call('POST', '/v1/device', { body: {} })).text();
    expect(text).not.toMatch(/sqlite|D1_|stack|at Object/i);
  });
});
