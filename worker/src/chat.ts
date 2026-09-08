import { ADDITION_PHRASES } from './additions';
import { authenticateDevice, quotaFor, recordEvent } from './device';
import { FOOD_NAMES } from './foods';
import { GeminiError, generateJson } from './gemini';
import { ApiError, json, readJson, requireString } from './http';
import { CHAT_SCHEMA, CHAT_SYSTEM, chatImagePrompt } from './prompts';
import { PREVIEW_DISCLAIMER } from './preview';

/**
 * The chat turn.
 *
 * The user types what they are eating; Gemini says it back and picks one
 * addition; Flux draws the plate with that addition on it.
 *
 * The whole design of this file exists to keep one promise: **nothing the user
 * types reaches the image model.** Gemini answers in ids from the app's
 * catalogue, this Worker looks those ids up in a generated closed set, and the
 * picture prompt is a fixed template over the names it found. There is no
 * interpolation point where a typed sentence could reach Flux, which is the
 * only version of this that survives contact with someone trying.
 */

/** Long enough to describe a dinner, short enough not to be a payload. */
const MAX_MESSAGE_CHARS = 500;

/** Flux tops out at 8. Four is the model's default and reads fine at this size. */
const IMAGE_STEPS = 4;

const now = () => Math.floor(Date.now() / 1000);

interface ChatReply {
  reply: string;
  foodIds: string[];
  additionId: string;
}

/**
 * The lists the model is allowed to answer from. Sent as data, not as part of
 * the instruction, and regenerated from the catalogue so they cannot drift.
 */
function catalogueBrief(): string {
  const foods = Object.entries(FOOD_NAMES)
    .map(([id, name]) => `${id}=${name}`)
    .join(', ');
  const additions = Object.entries(ADDITION_PHRASES)
    .map(([id, phrase]) => `${id}=${phrase}`)
    .join(', ');
  return `FOOD IDS: ${foods}\n\nADDITION IDS: ${additions}`;
}

export async function postChat(request: Request, env: Env): Promise<Response> {
  const t = now();
  const device = await authenticateDevice(request, env, t);

  const body = await readJson(request);
  const message = requireString(body, 'message', { max: MAX_MESSAGE_CHARS }).trim();
  if (message.length === 0) {
    throw new ApiError(400, 'empty_message', 'Say what you are eating.');
  }

  // A chat turn costs a scan, not a preview. It answers the same question a
  // photo does — "what am I eating?" — so it draws on the same allowance, and
  // there is no second budget for a user to reason about.
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
          : 'Your free week has ended. Subscribe to keep chatting about meals.',
    );
  }

  const started = Date.now();
  let result: ChatReply;
  try {
    result = await generateJson<ChatReply>(env, {
      model: env.MODEL_CHAT,
      system: CHAT_SYSTEM,
      schema: CHAT_SCHEMA,
      prompt: `${catalogueBrief()}\n\nUSER MESSAGE:\n${message}`,
    });
  } catch (error) {
    await stub.refund('scan', t);
    await recordEvent(
      env,
      {
        deviceId: device.id,
        kind: 'chat',
        model: env.MODEL_CHAT,
        durationMs: Date.now() - started,
        outcome: 'error',
      },
      t,
    );
    if (error instanceof GeminiError && error.status === 422) {
      throw new ApiError(422, 'chat_blocked', 'That message could not be answered.');
    }
    throw new ApiError(503, 'chat_unavailable', 'The assistant is busy. Try again shortly.');
  }

  // Ids the model invented are dropped rather than trusted. An empty result is
  // a fine outcome — it just means the picture is of a generic plate.
  const foodIds = (Array.isArray(result.foodIds) ? result.foodIds : [])
    .filter((id) => typeof id === 'string' && id in FOOD_NAMES)
    .slice(0, 8);
  const additionId =
    typeof result.additionId === 'string' && result.additionId in ADDITION_PHRASES
      ? result.additionId
      : '';

  const reply = String(result.reply ?? '').slice(0, 800);

  // The picture is a bonus. A failure here still returns the words, the same
  // way a failed preview leaves the patch untouched.
  let imageUrl: string | null = null;
  if (additionId) {
    const prompt = chatImagePrompt(
      foodIds.map((id) => FOOD_NAMES[id]),
      ADDITION_PHRASES[additionId],
    );
    try {
      const drawn = (await env.AI.run(env.MODEL_CHAT_IMAGE as never, {
        prompt,
        steps: IMAGE_STEPS,
      } as never)) as { image?: string };

      if (drawn?.image) {
        const bytes = Uint8Array.from(atob(drawn.image), (c) => c.charCodeAt(0));
        const key = `p/${crypto.randomUUID()}.jpg`;
        await env.PREVIEWS.put(key, bytes, {
          httpMetadata: { contentType: 'image/jpeg' },
          // Travels with the object, so the label cannot be separated from it.
          customMetadata: { disclaimer: PREVIEW_DISCLAIMER, createdAt: String(t) },
        });
        imageUrl = `${new URL(request.url).origin}/v1/preview/${encodeURIComponent(key.slice(2))}`;
      }
    } catch {
      // Deliberately swallowed: the reply is the product, the picture is not.
      imageUrl = null;
    }
  }

  const messageId = crypto.randomUUID();
  await env.DB.prepare(
    `INSERT INTO chat_messages (id, device_id, created_at, had_image) VALUES (?, ?, ?, ?)`,
  )
    .bind(messageId, device.id, t, imageUrl ? 1 : 0)
    .run();

  await recordEvent(
    env,
    {
      deviceId: device.id,
      kind: 'chat',
      model: env.MODEL_CHAT,
      durationMs: Date.now() - started,
      outcome: 'ok',
    },
    t,
  );

  return json({
    messageId,
    reply,
    foodIds,
    additionId,
    imageUrl,
    disclaimer: PREVIEW_DISCLAIMER,
    quota: spend.quota,
  });
}

/**
 * How a generated reply was received.
 *
 * Play requires generated content to be rateable and reportable. Reporting is
 * `/v1/report`, which routes a complaint to a human; this is the quieter
 * signal — a thumb, stored against the message id and nothing else. No message
 * text is kept here, on purpose: the words stay on the phone.
 */
export async function postRating(request: Request, env: Env): Promise<Response> {
  const t = now();
  const device = await authenticateDevice(request, env, t);

  const body = await readJson(request);
  const messageId = requireString(body, 'messageId', { max: 64 });
  const rating = requireString(body, 'rating', { max: 8 });
  if (rating !== 'up' && rating !== 'down') {
    throw new ApiError(400, 'invalid_rating', 'A rating is up or down.');
  }

  // Rating your own message only. Re-rating replaces, so a changed mind is not
  // two votes.
  const updated = await env.DB.prepare(
    `UPDATE chat_messages SET rating = ?, rated_at = ?
     WHERE id = ? AND device_id = ?`,
  )
    .bind(rating, t, messageId, device.id)
    .run();

  if (!updated.meta.changes) {
    throw new ApiError(404, 'unknown_message', 'That reply is no longer available to rate.');
  }
  return json({ ok: true });
}
