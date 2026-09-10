import { env } from 'cloudflare:test';

/**
 * Signs a registered device into an account, the way `/v1/auth/google` does
 * once it has verified a token.
 *
 * The routes that cost a model call refuse a guest, so almost every test needs
 * a signed-in device. Going through the real endpoint would mean mocking
 * Google's key set in every file; the token verification has its own tests, and
 * these are about what happens after it.
 */
export async function signIn(
  deviceToken: string,
  sub?: string,
  { pro = true }: { pro?: boolean } = {},
): Promise<string> {
  // One account per device by default, so tests stay isolated the way they
  // were when the allowance belonged to the phone.
  sub = sub ?? subFor(deviceToken);
  const hash = await sha256Hex(deviceToken);
  const t = Math.floor(Date.now() / 1000);
  await env.DB.prepare(
    `INSERT INTO users (sub, email, name, created_at, last_seen_at)
     VALUES (?, ?, ?, ?, ?) ON CONFLICT(sub) DO NOTHING`,
  )
    .bind(sub, `${sub}@example.com`, 'Test User', t, t)
    .run();
  await env.DB.prepare('UPDATE devices SET user_id = ? WHERE token_hash = ?')
    .bind(sub, hash)
    .run();
  // Subscribed by default. The app runs no trial of its own any more — the
  // free run at the AI lives on the Play subscription offer — so an account
  // with no subscription is entitled to nothing, and a test about what
  // scanning does would otherwise be a test about being refused. The handful
  // that *are* about being refused pass `pro: false`.
  if (pro) {
    await env.QUOTA.get(env.QUOTA.idFromName(sub)).setPro(
      true,
      Math.floor(Date.now() / 1000),
    );
  }
  return sub;
}

/** The account a device token is signed into by [signIn]. */
export function subFor(deviceToken: string): string {
  return `u_${deviceToken.slice(0, 24)}`;
}

/** The Durable Object a signed-in device's allowance lives in. */
export function quotaForUser(deviceToken: string) {
  return env.QUOTA.get(env.QUOTA.idFromName(subFor(deviceToken)));
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
