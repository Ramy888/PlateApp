import { authenticateDevice, quotaFor, recordEvent } from './device';
import { ApiError, json } from './http';

/**
 * Credentials for a voice session.
 *
 * The AssemblyAI key never reaches the app. The phone asks for a token, this
 * Worker mints a short-lived one-time token with the key it holds, and the app
 * opens the WebSocket with that. Same shape as every other credential here:
 * the client gets the least it can do the job with.
 *
 * A voice session is metered like a scan, because it is the same question
 * answered out loud — see chat.ts for why that is one allowance and not two.
 */

const TOKEN_ENDPOINT = 'https://agents.assemblyai.com/v1/token';

/** Long enough to open a socket, short enough to be worthless if intercepted. */
const TOKEN_TTL_SECONDS = 60;

const now = () => Math.floor(Date.now() / 1000);

export async function postVoiceToken(request: Request, env: Env): Promise<Response> {
  const t = now();
  const device = await authenticateDevice(request, env, t);

  if (!env.ASSEMBLYAI_API_KEY) {
    throw new ApiError(503, 'voice_unavailable', 'Voice is not available right now.');
  }

  // Charged up front. A session that is opened and abandoned still cost us the
  // connection, and refunding on a socket that may never close cleanly would
  // be a hole rather than a kindness.
  const stub = quotaFor(env, device.id);
  const spend = await stub.spend('scan', t);
  if (!spend.ok) {
    throw new ApiError(
      402,
      'quota_exhausted',
      spend.quota.pro
        ? 'You have used this month’s allowance.'
        : spend.quota.trialActive
          ? 'You have used today’s allowance. A few more tomorrow.'
          : 'Your free week has ended. Subscribe to keep talking to The Plate.',
    );
  }

  const started = Date.now();
  let token: string;
  try {
    const response = await fetch(`${TOKEN_ENDPOINT}?expires_in_seconds=${TOKEN_TTL_SECONDS}`, {
      headers: { authorization: `Bearer ${env.ASSEMBLYAI_API_KEY}` },
    });
    if (!response.ok) {
      throw new Error(`token endpoint said ${response.status}`);
    }
    const body = (await response.json()) as { token?: string };
    if (!body.token) throw new Error('no token in response');
    token = body.token;
  } catch {
    await stub.refund('scan', t);
    await recordEvent(
      env,
      {
        deviceId: device.id,
        kind: 'voice',
        model: 'assemblyai-voice-agent',
        durationMs: Date.now() - started,
        outcome: 'error',
      },
      t,
    );
    throw new ApiError(503, 'voice_unavailable', 'Voice is busy right now. Try again shortly.');
  }

  await recordEvent(
    env,
    {
      deviceId: device.id,
      kind: 'voice',
      model: 'assemblyai-voice-agent',
      durationMs: Date.now() - started,
      outcome: 'ok',
    },
    t,
  );

  return json({
    token,
    expiresAt: t + TOKEN_TTL_SECONDS,
    quota: spend.quota,
  });
}
