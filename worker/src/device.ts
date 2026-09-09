import { randomToken, sha256Hex } from './crypto';
import { ApiError, bearerToken } from './http';
import type { QuotaCounter, QuotaView } from './quota';

/**
 * Anonymous device identity.
 *
 * This is not an account. There is no email, no password and nothing to sign
 * into — a device gets an opaque token on first launch so the server can hold
 * a quota against something. Deleting the device deletes everything the server
 * knows.
 */

export interface DeviceRow {
  id: string;
  platform: string;
  rc_user_id: string | null;

  /// Null for a guest. Set once they sign in on this device.
  user_id: string | null;
}

const PLATFORMS = new Set(['android', 'ios']);

export function normalizePlatform(value: unknown): string {
  const platform = typeof value === 'string' ? value.toLowerCase() : '';
  if (!PLATFORMS.has(platform)) {
    throw new ApiError(400, 'invalid_platform', 'platform must be android or ios.');
  }
  return platform;
}

export async function registerDevice(
  env: Env,
  platform: string,
  rcUserId: string | null,
  now: number,
): Promise<{ token: string; device: DeviceRow }> {
  const token = randomToken();
  const device: DeviceRow = {
    id: crypto.randomUUID(),
    platform,
    rc_user_id: rcUserId,
    user_id: null,
  };
  await env.DB.prepare(
    `INSERT INTO devices (id, token_hash, platform, created_at, last_seen_at, rc_user_id)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(device.id, await sha256Hex(token), platform, now, now, rcUserId)
    .run();
  return { token, device };
}

/**
 * Resolves the bearer token to a device. Also refreshes `last_seen_at`, which
 * is the only thing that lets abandoned devices be swept later.
 */
export async function authenticateDevice(
  request: Request,
  env: Env,
  now: number,
): Promise<DeviceRow> {
  const token = bearerToken(request);
  const row = await env.DB.prepare(
    'SELECT id, platform, rc_user_id, user_id FROM devices WHERE token_hash = ?',
  )
    .bind(await sha256Hex(token))
    .first<DeviceRow>();

  if (!row) {
    throw new ApiError(401, 'unknown_device', 'This device is not registered.');
  }
  await env.DB.prepare('UPDATE devices SET last_seen_at = ? WHERE id = ?')
    .bind(now, row.id)
    .run();
  return row;
}

/**
 * Refuses a guest.
 *
 * Everything that costs a model call goes through here. Browsing the app,
 * picking a meal and building a plate by hand never do — those work signed
 * out, offline, and always will.
 */
export function requireUser(env: Env, device: DeviceRow): string {
  if (device.user_id) return device.user_id;

  // Behind a flag because the app and the Worker cannot ship at the same
  // instant, and either order breaks somebody: a new app against an old Worker
  // finds no /v1/auth routes, an old app against a strict Worker is refused an
  // error code it has never heard of. So the Worker accepts guests until the
  // signed-in build has propagated, and the flag is flipped after.
  //
  // The gate that matters to the product is in the app, which asks before it
  // sends. This one is the anti-bypass, and it can lag safely.
  if (env.SIGN_IN_REQUIRED !== 'true') return device.id;

  throw new ApiError(
    401,
    'sign_in_required',
    'Sign in to use the AI features. Building a meal by hand stays free.',
  );
}

/** The Durable Object holding this device's allowance. */
export function quotaFor(env: Env, deviceId: string): DurableObjectStub<QuotaCounter> {
  return env.QUOTA.get(env.QUOTA.idFromName(deviceId));
}

export async function forgetDevice(env: Env, device: DeviceRow): Promise<void> {
  await quotaFor(env, device.id).forget();

  // The account goes with it. Play requires an app that has accounts to offer
  // a way to delete one from inside the app, and "delete my data" that left
  // the account standing would be the wrong answer to the question anyway.
  const owner = device.user_id;
  if (owner) {
    await quotaFor(env, owner).forget();
  }

  await env.DB.batch([
    env.DB.prepare('DELETE FROM reports WHERE device_id = ?').bind(device.id),
    env.DB.prepare('DELETE FROM scan_events WHERE device_id = ?').bind(device.id),
    env.DB.prepare('DELETE FROM chat_messages WHERE device_id = ?').bind(device.id),
    env.DB.prepare('DELETE FROM devices WHERE id = ?').bind(device.id),
  ]);

  if (owner) {
    // Any other phone still signed into this account is signed out by the
    // account disappearing, rather than left pointing at nothing.
    await env.DB.batch([
      env.DB.prepare('UPDATE devices SET user_id = NULL WHERE user_id = ?').bind(owner),
      env.DB.prepare('DELETE FROM users WHERE sub = ?').bind(owner),
    ]);
  }
}

/** Records an attempt. Counts only — never what the meal was. */
export async function recordEvent(
  env: Env,
  fields: {
    deviceId: string;
    kind: 'scan' | 'preview' | 'chat' | 'voice' | 'plate';
    model: string;
    durationMs: number;
    outcome: 'ok' | 'empty' | 'error';
    matched?: number;
    unmatched?: number;
  },
  now: number,
): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO scan_events
       (id, device_id, kind, created_at, model, duration_ms, outcome, matched_count, unmatched_count)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      crypto.randomUUID(),
      fields.deviceId,
      fields.kind,
      now,
      fields.model,
      fields.durationMs,
      fields.outcome,
      fields.matched ?? 0,
      fields.unmatched ?? 0,
    )
    .run();
}

export type { QuotaView };
