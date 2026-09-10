import { ADDITION_FACTS, ADDITION_PHRASES } from './additions';
import { authenticateDevice, quotaFor, recordEvent, requireUser } from './device';
import { FOOD_NAMES } from './foods';
import { GeminiError, generateJson } from './gemini';
import { ApiError, json, readJson, requireString } from './http';
import {
  CHAT_SCHEMA,
  CHAT_SYSTEM,
  chatImagePrompt,
  PLATE_SYSTEM,
  VOICE_SCHEMA,
  VOICE_SYSTEM,
} from './prompts';
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

/** About a minute of speech at the app's recording settings. */
const MAX_AUDIO_BYTES = 2 * 1024 * 1024;

const ALLOWED_AUDIO = new Set(['audio/wav', 'audio/x-wav', 'audio/mp4', 'audio/aac', 'audio/mpeg']);

const now = () => Math.floor(Date.now() / 1000);

interface ChatReply {
  reply: string;
  foodIds: string[];
  additionId: string;

  /// Only present on a spoken turn: what the model heard.
  transcript?: string;
}

/** What the model was given, and how a failure should be described. */
interface TurnInput {
  prompt?: string;
  audio?: Uint8Array;
  audioMimeType?: string;
  kind: 'chat' | 'voice' | 'plate';

  /// Set where the caller already decided the ids. The model's echo is then
  /// ignored, so a caption cannot quietly change what was suggested.
  fixedFoodIds?: string[];
  fixedAdditionId?: string;
}

/**
 * What the person has said they do not want, read off the request.
 *
 * The same four the on-device engine knows. Anything unrecognised is dropped
 * rather than guessed at, so a client cannot invent a rule.
 */
const DIET_PREFS = ['vegetarian', 'dairy_free', 'gluten_free', 'low_cost'] as const;
type DietPref = (typeof DIET_PREFS)[number];

export function readDietPrefs(body: Record<string, unknown>): DietPref[] {
  const raw = body.avoid;
  if (!Array.isArray(raw)) return [];
  return DIET_PREFS.filter((p) => raw.includes(p));
}

/**
 * Whether a preference rules an addition out.
 *
 * Deliberately the same rule as `PatchEngine.blockedByPrefs` on the phone. If
 * these two ever disagree, the manual answer and the AI answer disagree about
 * the same person — and the AI is the one that will suggest a vegetarian a
 * piece of chicken.
 */
function blockedByPrefs(id: string, prefs: readonly DietPref[]): boolean {
  const facts = ADDITION_FACTS[id];
  if (!facts) return false;
  if (prefs.includes('vegetarian') &&
      (facts.tags.includes('meat') || facts.tags.includes('fish'))) {
    return true;
  }
  if (prefs.includes('dairy_free') && facts.tags.includes('dairy')) return true;
  if (prefs.includes('gluten_free') && facts.tags.includes('gluten')) return true;
  if (prefs.includes('low_cost') && facts.cost >= 3) return true;
  return false;
}

/** What each goal asks the model to lean towards, in its own words. */
const GOAL_HINTS: Readonly<Record<string, string>> = {
  feel_satisfied: 'They want to stop feeling hungry an hour later — lean towards protein and fibre.',
  more_energy: 'They want to avoid the slump after a meal — lean towards fibre and healthy fats.',
  better_meals: 'They want a rounder plate — close whatever gap is biggest.',
};

/**
 * The lists the model is allowed to answer from. Sent as data, not as part of
 * the instruction, and regenerated from the catalogue so they cannot drift.
 *
 * Additions someone has ruled out are removed from the list rather than
 * mentioned in the instruction: a model cannot pick what it was never shown,
 * and an instruction is only ever a request.
 */
function catalogueBrief(prefs: readonly DietPref[] = [], goal?: string): string {
  const foods = Object.entries(FOOD_NAMES)
    .map(([id, name]) => `${id}=${name}`)
    .join(', ');
  const additions = Object.entries(ADDITION_PHRASES)
    .filter(([id]) => !blockedByPrefs(id, prefs))
    .map(([id, phrase]) => `${id}=${phrase}`)
    .join(', ');
  const hint = goal && GOAL_HINTS[goal] ? `\n\nWHAT THEY ARE AFTER: ${GOAL_HINTS[goal]}` : '';
  return `FOOD IDS: ${foods}\n\nADDITION IDS: ${additions}${hint}`;
}

export async function postChat(request: Request, env: Env): Promise<Response> {
  return runTurn(request, env, 'chat', async () => {
    const body = await readJson(request);
    const message = requireString(body, 'message', { max: MAX_MESSAGE_CHARS }).trim();
    if (message.length === 0) {
      throw new ApiError(400, 'empty_message', 'Say what you are eating.');
    }
    const prefs = readDietPrefs(body);
    const goal = typeof body.goal === 'string' ? body.goal : undefined;
    return { prompt: `${catalogueBrief(prefs, goal)}\n\nUSER MESSAGE:\n${message}` };
  });
}

/**
 * The spoken turn.
 *
 * One model call does the listening and the understanding together: Gemini
 * takes the audio and answers in the same shape a typed message does, plus what
 * it heard. Nothing about the closed set changes — the words the picture prompt
 * is built from still come from the catalogue, never from the recording.
 */
export async function postVoice(request: Request, env: Env): Promise<Response> {
  return runTurn(request, env, 'voice', async () => {
    let form: FormData;
    try {
      form = await request.formData();
    } catch {
      throw new ApiError(400, 'invalid_body', 'Expected a multipart upload.');
    }

    const file = form.get('audio');
    if (!(file instanceof File)) {
      throw new ApiError(400, 'missing_audio', 'No recording was attached.');
    }
    if (file.size === 0 || file.size > MAX_AUDIO_BYTES) {
      throw new ApiError(413, 'audio_too_large', 'That recording is the wrong size to send.');
    }
    const mimeType = file.type || 'audio/wav';
    if (!ALLOWED_AUDIO.has(mimeType)) {
      throw new ApiError(415, 'unsupported_type', 'Send a WAV, MP4 or AAC recording.');
    }

    // Multipart, so the preferences arrive as fields rather than JSON.
    const avoid = form.get('avoid');
    const prefs = readDietPrefs({
      avoid: typeof avoid === 'string' ? avoid.split(',') : [],
    });
    const goalField = form.get('goal');
    const goal = typeof goalField === 'string' ? goalField : undefined;

    return {
      audio: new Uint8Array(await file.arrayBuffer()),
      audioMimeType: mimeType,
      prompt: `${catalogueBrief(prefs, goal)}\n\nThe audio is the user describing their meal.`,
    };
  });
}

/**
 * One turn, however it arrived.
 *
 * The caller is authenticated *before* its body is read, so an unauthenticated
 * request is refused without this Worker buffering a megabyte of audio for it.
 * The body is therefore passed as a thunk rather than a value.
 */
/**
 * A plate the user built by hand, written up and drawn.
 *
 * The safest endpoint here: the request is nothing but catalogue ids, every one
 * of them checked against the closed set before anything happens, so there is
 * no text a client controls anywhere in it.
 */
export async function postPlate(request: Request, env: Env): Promise<Response> {
  return runTurn(request, env, 'plate', async () => {
    const body = await readJson(request);

    const rawFoods = Array.isArray(body.foodIds) ? body.foodIds : [];
    const foodIds = rawFoods
      .filter((id): id is string => typeof id === 'string')
      .slice(0, 12);
    const unknown = foodIds.find((id) => !(id in FOOD_NAMES));
    if (unknown !== undefined) {
      throw new ApiError(400, 'invalid_food', 'That is not a food this app knows.');
    }

    const additionId = requireString(body, 'additionId', { max: 64 });
    if (!(additionId in ADDITION_PHRASES)) {
      throw new ApiError(400, 'invalid_addition', 'That is not a food this app suggests.');
    }

    const plate = foodIds.length > 0
      ? foodIds.map((id) => FOOD_NAMES[id]).join(', ')
      : 'a simple everyday meal';
    return {
      prompt: `On the plate: ${plate}.\nAdding: ${ADDITION_PHRASES[additionId]}.`,
      fixedFoodIds: foodIds,
      fixedAdditionId: additionId,
    };
  });
}

async function runTurn(
  request: Request,
  env: Env,
  kind: 'chat' | 'voice' | 'plate',
  readInput: () => Promise<Omit<TurnInput, 'kind'>>,
): Promise<Response> {
  const t = now();
  const device = await authenticateDevice(request, env, t);
  const owner = requireUser(env, device);
  const input: TurnInput = { ...(await readInput()), kind };

  // A chat turn costs a scan, not a preview. It answers the same question a
  // photo does — "what am I eating?" — so it draws on the same allowance, and
  // there is no second budget for a user to reason about.
  const stub = quotaFor(env, owner);
  const spend = await stub.spend('scan', t);
  if (!spend.ok) {
    throw new ApiError(
      402,
      'quota_exhausted',
      spend.quota.pro
        ? 'You have used this month’s allowance.'
        : spend.quota.trialActive
          ? 'You have used today’s allowance. A few more tomorrow.'
          : 'You have used your three free AI meals. Subscribe to keep chatting.',
    );
  }

  const started = Date.now();
  let result: ChatReply;
  try {
    result = await generateJson<ChatReply>(env, {
      model: env.MODEL_CHAT,
      system:
        input.kind === 'voice'
          ? VOICE_SYSTEM
          : input.kind === 'plate'
            ? PLATE_SYSTEM
            : CHAT_SYSTEM,
      schema: input.kind === 'voice' ? VOICE_SCHEMA : CHAT_SCHEMA,
      prompt: input.prompt,
      image: input.audio,
      mimeType: input.audioMimeType,
    });
  } catch (error) {
    await stub.refund('scan', t);
    await recordEvent(
      env,
      {
        deviceId: device.id,
        kind: input.kind,
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
  // Where the caller decided the ids, the model's echo is ignored entirely: a
  // caption must not be able to change what was suggested.
  const foodIds =
    input.fixedFoodIds ??
    (Array.isArray(result.foodIds) ? result.foodIds : [])
      .filter((id) => typeof id === 'string' && id in FOOD_NAMES)
      .slice(0, 8);
  const additionId =
    input.fixedAdditionId ??
    (typeof result.additionId === 'string' && result.additionId in ADDITION_PHRASES
      ? result.additionId
      : '');

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
      kind: input.kind,
      model: env.MODEL_CHAT,
      durationMs: Date.now() - started,
      outcome: 'ok',
    },
    t,
  );

  return json({
    messageId,
    transcript: String(result.transcript ?? '').slice(0, 800),
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
