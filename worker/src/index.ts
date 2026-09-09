/**
 * The Plate scan API.
 *
 * Holds the Gemini key, enforces quotas that a patched app cannot lie its way
 * past, and proxies the two model calls. It stores no photographs and no meal
 * data — what anyone ate stays on their phone.
 */
import { authenticateDevice, forgetDevice, normalizePlatform, ownerOf, quotaFor, registerDevice } from './device';
import { checkEntitlement } from './entitlement';
import {
  ApiError,
  clientIp,
  errorResponse,
  json,
  noContent,
  readJson,
  requireString,
} from './http';
import { issueChallenge, verifyIntegrity } from './integrity';
import { postAuthGoogle, postAuthSignOut } from './auth';
import { postChat, postPlate, postRating, postVoice } from './chat';
import { getPreview, postPreview } from './preview';
import { postScan } from './scan';

export { QuotaCounter } from './quota';

const now = () => Math.floor(Date.now() / 1000);

const REPORT_REASONS = new Set(['wrong_food', 'offensive', 'unrealistic', 'other']);

// ---------------------------------------------------------------- limiting

/** Coarse per-IP ceiling, on top of the per-device quota. */
async function enforceLimit(
  env: Env,
  key: string,
  limit: number,
  windowSeconds: number,
): Promise<void> {
  const t = now();
  const bucket = `${key}:${Math.floor(t / windowSeconds)}`;
  const row = await env.DB.prepare(
    `INSERT INTO rate_limits (bucket, count, expires_at) VALUES (?, 1, ?)
     ON CONFLICT(bucket) DO UPDATE SET count = count + 1
     RETURNING count`,
  )
    .bind(bucket, t + windowSeconds)
    .first<{ count: number }>();

  if ((row?.count ?? 1) > limit) {
    throw new ApiError(429, 'rate_limited', 'Too many requests. Try again shortly.');
  }
}

async function sweep(env: Env): Promise<void> {
  const t = now();
  await env.DB.batch([
    env.DB.prepare('DELETE FROM rate_limits WHERE expires_at < ?').bind(t),
    env.DB.prepare('DELETE FROM challenges WHERE expires_at < ?').bind(t),
    // Ratings age out with the replies they were about; nothing here is
    // worth keeping once the conversation is long gone from the phone.
    env.DB.prepare('DELETE FROM chat_messages WHERE created_at < ?').bind(t - 60 * 60 * 24 * 90),
  ]);
}

// ---------------------------------------------------------------- entitlement

/**
 * Refreshes the cached Pro flag when it has gone stale, then returns the
 * device's allowance. The app's own opinion of `isPro` is never consulted.
 */
async function currentQuota(env: Env, deviceId: string, rcUserId: string | null) {
  const stub = quotaFor(env, deviceId);
  const t = now();

  if (rcUserId && (await stub.needsEntitlementCheck(t))) {
    const isPro = await checkEntitlement(env, rcUserId);
    return stub.setPro(isPro, t);
  }
  return stub.peek(t);
}

// -------------------------------------------------------------------- routes

async function postDevice(request: Request, env: Env): Promise<Response> {
  await enforceLimit(env, `register:${clientIp(request)}`, 10, 3600);

  const body = await readJson(request);
  const platform = normalizePlatform(body.platform);
  const rcUserId = typeof body.rcUserId === 'string' ? body.rcUserId.slice(0, 200) : null;

  // Android must attest. iOS has no equivalent wired up yet, so it registers
  // without one — noted here rather than pretended otherwise.
  if (platform === 'android') {
    const integrityToken = typeof body.integrityToken === 'string' ? body.integrityToken : '';
    const attestation = await verifyIntegrity(env, integrityToken);
    if (!attestation.ok) {
      throw new ApiError(403, 'attestation_failed', 'This app installation could not be verified.');
    }
  }

  const { token, device } = await registerDevice(env, platform, rcUserId, now());
  const quota = await currentQuota(env, device.id, rcUserId);
  return json({ deviceToken: token, quota }, 201);
}

/// Handed out before registration so the integrity token can be bound to it.
async function postChallenge(request: Request, env: Env): Promise<Response> {
  await enforceLimit(env, `challenge:${clientIp(request)}`, 30, 3600);
  return json(await issueChallenge(env), 201);
}

async function getQuota(request: Request, env: Env): Promise<Response> {
  const device = await authenticateDevice(request, env, now());
  return json(await currentQuota(env, ownerOf(device), device.rc_user_id));
}

async function deleteDevice(request: Request, env: Env): Promise<Response> {
  const device = await authenticateDevice(request, env, now());
  await forgetDevice(env, device);
  console.log(JSON.stringify({ event: 'device_forgotten', at: now() }));
  return noContent();
}

/**
 * Google Play requires apps that generate content to accept reports in-app.
 * This always returns 202: a user reporting something offensive must never see
 * an error, so failures are logged and swallowed.
 */
async function postReport(request: Request, env: Env): Promise<Response> {
  const device = await authenticateDevice(request, env, now());
  const body = await readJson(request);

  try {
    const targetType = requireString(body, 'targetType', { max: 16 });
    const targetId = requireString(body, 'targetId', { max: 64 });
    const reason = requireString(body, 'reason', { max: 32 });
    const note = typeof body.note === 'string' ? body.note.slice(0, 500) : null;

    await env.DB.prepare(
      `INSERT INTO reports (id, device_id, target_type, target_id, reason, note, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    )
      .bind(
        crypto.randomUUID(),
        device.id,
        targetType === 'preview' ? 'preview' : 'scan',
        targetId,
        REPORT_REASONS.has(reason) ? reason : 'other',
        note,
        now(),
      )
      .run();
  } catch (error) {
    console.error(JSON.stringify({ event: 'report_failed', message: String(error) }));
  }

  return json({ status: 'received' }, 202);
}

// -------------------------------------------------------------------- router

type Handler = (request: Request, env: Env) => Promise<Response>;

/** A per-IP ceiling on paid calls, on top of each device's own quota. */
async function scanRoute(request: Request, env: Env): Promise<Response> {
  await enforceLimit(env, `scan:${clientIp(request)}`, 20, 3600);
  return postScan(request, env);
}

async function previewRoute(request: Request, env: Env): Promise<Response> {
  await enforceLimit(env, `preview:${clientIp(request)}`, 12, 3600);
  return postPreview(request, env);
}

// A chat turn costs a Gemini call and a Flux image, so it sits with the other
// paid routes rather than with the free ones.
async function chatRoute(request: Request, env: Env): Promise<Response> {
  await enforceLimit(env, `chat:${clientIp(request)}`, 30, 3600);
  return postChat(request, env);
}

// Sign-in is cheap but forgeable-looking, so it gets its own per-IP ceiling.
async function authRoute(request: Request, env: Env): Promise<Response> {
  await enforceLimit(env, `auth:${clientIp(request)}`, 30, 3600);
  return postAuthGoogle(request, env);
}

// Writing up and drawing a plate the user built by hand. Same cost as the
// others: one model call and one image.
async function plateRoute(request: Request, env: Env): Promise<Response> {
  await enforceLimit(env, `plate:${clientIp(request)}`, 40, 3600);
  return postPlate(request, env);
}

// A spoken turn is a chat turn with audio in front of it, and costs the same.
async function voiceRoute(request: Request, env: Env): Promise<Response> {
  await enforceLimit(env, `voice:${clientIp(request)}`, 30, 3600);
  return postVoice(request, env);
}

const ROUTES: Record<string, Partial<Record<string, Handler>>> = {
  '/v1/challenge': { POST: postChallenge },
  '/v1/auth/google': { POST: authRoute },
  '/v1/auth/signout': { POST: postAuthSignOut },
  '/v1/device': { POST: postDevice, DELETE: deleteDevice },
  '/v1/scan': { POST: scanRoute },
  '/v1/preview': { POST: previewRoute },
  '/v1/quota': { GET: getQuota },
  '/v1/report': { POST: postReport },
  '/v1/chat': { POST: chatRoute },
  '/v1/rating': { POST: postRating },
  '/v1/voice': { POST: voiceRoute },
  '/v1/plate': { POST: plateRoute },
};

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === '/health') {
      return json({
        ok: true,
        // Surfaced so a misconfigured deployment is obvious from the outside
        // rather than discovered by a user.
        attestation: env.PLAY_INTEGRITY_SA ? 'enforced' : 'skipped',
        signIn: env.GOOGLE_CLIENT_ID
          ? env.SIGN_IN_REQUIRED === 'true'
            ? 'required'
            : 'accepted'
          : 'unconfigured',
        models: { vision: env.MODEL_VISION, image: env.MODEL_IMAGE },
      });
    }

    // Generated previews are served from a path with the object name in it,
    // so it cannot be a fixed route.
    if (url.pathname.startsWith('/v1/preview/') && request.method === 'GET') {
      try {
        return await getPreview(request, env);
      } catch (error) {
        return errorResponse(error);
      }
    }

    const route = ROUTES[url.pathname];
    if (!route) return json({ error: 'not_found', message: 'No such endpoint.' }, 404);

    const handler = route[request.method];
    if (!handler) {
      return json({ error: 'method_not_allowed', message: 'Wrong method.' }, 405, {
        allow: Object.keys(route).join(', '),
      });
    }

    try {
      const response = await handler(request, env);
      ctx.waitUntil(sweep(env).catch(() => {}));
      return response;
    } catch (error) {
      return errorResponse(error);
    }
  },
} satisfies ExportedHandler<Env>;
