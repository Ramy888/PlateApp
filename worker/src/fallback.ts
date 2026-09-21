/**
 * What answers when Gemini will not.
 *
 * Three times in eight days a billing problem on one Google project took every
 * AI feature in the app down at once — scanning, chat, voice and the drawn
 * plate — because they all go through the same key. The app itself survives
 * that (the suggestion engine is pure and the plate is drawn on the phone),
 * but all four ways *in* stop working, which is what anyone opening the app
 * would see.
 *
 * So this is not about cost. Lifetime Gemini spend across every scan, chat and
 * voice turn ever made is about thirty-five cents. It is about a single point
 * of failure that has already fired three times, on an app that has to stand
 * up unattended.
 *
 * Workers AI is already wired for the plate pictures and already paid for, so
 * the fallback costs nothing extra and adds no new account to go wrong.
 *
 * It is deliberately second, not primary: these models read a plate less well
 * than Gemini does, and a slightly worse answer is only better than no answer.
 */

/**
 * JSON mode works on a handful of text models and on none of the vision ones,
 * so the two paths differ in how hard the schema is enforced.
 */
const TEXT_MODEL = '@cf/meta/llama-3.3-70b-instruct-fp8-fast';
const VISION_MODEL = '@cf/meta/llama-3.2-11b-vision-instruct';

/** Whether a Gemini failure is the kind another provider could answer. */
export function worthFallingBackFrom(status: number): boolean {
  // Only the two that have actually happened: 402 prepay credits gone, 403
  // billing denied. Both mean the account is shut off, which no amount of
  // retrying fixes and which takes every AI feature down at once.
  //
  // Deliberately *not* 5xx or 429. Those are load, and `call` already retries
  // them three times with backoff — Gemini recovers from them on its own, and
  // handing them to a weaker model would trade a good answer a moment later
  // for a worse one now.
  //
  // Deliberately not 422 either: that is a safety refusal, and quietly asking
  // someone else is using a fallback to get an answer that was declined.
  return status === 402 || status === 403;
}

/**
 * Pulls an object out of a reply that may be wrapped in prose or a code fence.
 *
 * Needed only on the vision path, where no schema can be enforced and the
 * model will sometimes explain itself before answering.
 */
function parseLoosely<T>(text: string): T {
  const trimmed = text.trim().replace(/^```(?:json)?/i, '').replace(/```$/, '');
  try {
    return JSON.parse(trimmed) as T;
  } catch {
    const start = trimmed.indexOf('{');
    const end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return JSON.parse(trimmed.slice(start, end + 1)) as T;
    }
    throw new Error('fallback returned nothing parseable');
  }
}

export async function fallbackJson<T>(
  env: Env,
  {
    system,
    schema,
    image,
    prompt,
  }: { system: string; schema: unknown; image?: Uint8Array; prompt?: string },
): Promise<T> {
  if (image) {
    // No JSON mode on vision models, so the schema goes in the prompt and the
    // answer is parsed leniently. Worse than an enforced schema, and still
    // better than telling someone recognition is unavailable.
    const reply = (await env.AI.run(VISION_MODEL as never, {
      image: [...image],
      prompt:
        `${system}\n\nAnswer with JSON only, matching this schema exactly. ` +
        `No explanation, no code fence.\n${JSON.stringify(schema)}` +
        (prompt ? `\n\n${prompt}` : ''),
      max_tokens: 1024,
    } as never)) as { description?: string; response?: string };

    const text = reply?.response ?? reply?.description ?? '';
    return parseLoosely<T>(text);
  }

  const reply = (await env.AI.run(TEXT_MODEL as never, {
    messages: [
      { role: 'system', content: system },
      { role: 'user', content: prompt ?? '' },
    ],
    response_format: { type: 'json_schema', json_schema: schema },
    max_tokens: 1024,
  } as never)) as { response?: unknown };

  const answer = reply?.response;
  if (typeof answer === 'string') return parseLoosely<T>(answer);
  if (answer && typeof answer === 'object') return answer as T;
  throw new Error('fallback returned nothing usable');
}
