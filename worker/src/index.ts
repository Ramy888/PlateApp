/**
 * PlatePatch accounts API.
 *
 * An account exists for one reason: to move saved patches to a new phone. The
 * server therefore stores an email address, a password hash, and one opaque
 * blob of meal data it never inspects. Nothing else.
 */
import {
  hashPassword,
  randomToken,
  sha256Hex,
  timingSafeEqualHex,
  verifyPassword,
} from './crypto';
import {
  ApiError,
  bearerToken,
  clientIp,
  errorResponse,
  json,
  noContent,
  normalizeEmail,
  readJson,
  requireString,
  validatePassword,
} from './http';

const SESSION_TTL_SECONDS = 60 * 60 * 24 * 30; // 30 days
const RESET_TTL_SECONDS = 60 * 60; // 1 hour
const MAX_SYNC_PAYLOAD_BYTES = 32 * 1024;

interface UserRow {
  id: string;
  email: string;
  password_hash: string;
  created_at: number;
}

const now = () => Math.floor(Date.now() / 1000);

// ---------------------------------------------------------------- limiting

/**
 * Fixed-window limiter in D1. Coarse by design — its job is to make credential
 * stuffing and reset-email abuse expensive, not to be precise.
 */
async function enforceLimit(
  env: Env,
  key: string,
  limit: number,
  windowSeconds: number,
): Promise<void> {
  const t = now();
  const bucket = `${key}:${Math.floor(t / windowSeconds)}`;
  const expiresAt = t + windowSeconds;

  const row = await env.DB.prepare(
    `INSERT INTO rate_limits (bucket, count, expires_at) VALUES (?, 1, ?)
     ON CONFLICT(bucket) DO UPDATE SET count = count + 1
     RETURNING count`,
  )
    .bind(bucket, expiresAt)
    .first<{ count: number }>();

  if ((row?.count ?? 1) > limit) {
    throw new ApiError(429, 'rate_limited', 'Too many attempts. Try again shortly.');
  }
}

/** Opportunistic cleanup so expired rows do not accumulate forever. */
async function sweep(env: Env): Promise<void> {
  const t = now();
  await env.DB.batch([
    env.DB.prepare('DELETE FROM rate_limits WHERE expires_at < ?').bind(t),
    env.DB.prepare('DELETE FROM sessions WHERE expires_at < ?').bind(t),
    env.DB.prepare('DELETE FROM password_resets WHERE expires_at < ?').bind(t),
  ]);
}

// ----------------------------------------------------------------- session

async function createSession(env: Env, userId: string) {
  const token = randomToken();
  const expiresAt = now() + SESSION_TTL_SECONDS;
  await env.DB.prepare(
    'INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)',
  )
    .bind(await sha256Hex(token), userId, now(), expiresAt)
    .run();
  return { token, expiresAt };
}

async function authenticate(request: Request, env: Env): Promise<UserRow> {
  const token = bearerToken(request);
  const row = await env.DB.prepare(
    `SELECT u.id, u.email, u.password_hash, u.created_at, s.expires_at, s.token_hash
       FROM sessions s JOIN users u ON u.id = s.user_id
      WHERE s.token_hash = ?`,
  )
    .bind(await sha256Hex(token))
    .first<UserRow & { expires_at: number; token_hash: string }>();

  if (!row || row.expires_at < now()) {
    throw new ApiError(401, 'unauthorized', 'Your session has expired. Sign in again.');
  }
  // The lookup was by primary key, so this only guards against a future change
  // that widens the query; it costs nothing.
  if (!timingSafeEqualHex(row.token_hash, await sha256Hex(token))) {
    throw new ApiError(401, 'unauthorized', 'Sign in to continue.');
  }
  return row;
}

const publicUser = (user: UserRow) => ({
  id: user.id,
  email: user.email,
  createdAt: user.created_at,
});

// ------------------------------------------------------------------ routes

async function register(request: Request, env: Env): Promise<Response> {
  await enforceLimit(env, `register:${clientIp(request)}`, 5, 3600);

  const body = await readJson(request);
  const email = normalizeEmail(requireString(body, 'email', { max: 254 }));
  const password = validatePassword(body.password);

  const existing = await env.DB.prepare('SELECT id FROM users WHERE email = ?')
    .bind(email)
    .first<{ id: string }>();
  if (existing) {
    throw new ApiError(
      409,
      'email_taken',
      'That email already has an account. Try signing in.',
    );
  }

  const user: UserRow = {
    id: crypto.randomUUID(),
    email,
    password_hash: await hashPassword(password),
    created_at: now(),
  };
  await env.DB.prepare(
    'INSERT INTO users (id, email, password_hash, created_at) VALUES (?, ?, ?, ?)',
  )
    .bind(user.id, user.email, user.password_hash, user.created_at)
    .run();

  const session = await createSession(env, user.id);
  return json({ ...session, user: publicUser(user) }, 201);
}

async function login(request: Request, env: Env): Promise<Response> {
  const ip = clientIp(request);
  await enforceLimit(env, `login:${ip}`, 10, 900);

  const body = await readJson(request);
  const email = normalizeEmail(requireString(body, 'email', { max: 254 }));
  const password = validatePassword(body.password);

  const user = await env.DB.prepare(
    'SELECT id, email, password_hash, created_at FROM users WHERE email = ?',
  )
    .bind(email)
    .first<UserRow>();

  // Hash against a dummy record when the user is absent, so a missing account
  // and a wrong password take the same time.
  const stored = user?.password_hash ?? (await hashPassword(randomToken()));
  const ok = await verifyPassword(password, stored);

  if (!user || !ok) {
    throw new ApiError(401, 'invalid_credentials', 'That email or password is not right.');
  }

  const session = await createSession(env, user.id);
  return json({ ...session, user: publicUser(user) });
}

async function logout(request: Request, env: Env): Promise<Response> {
  const token = bearerToken(request);
  await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?')
    .bind(await sha256Hex(token))
    .run();
  return noContent();
}

async function forgotPassword(request: Request, env: Env): Promise<Response> {
  const ip = clientIp(request);
  await enforceLimit(env, `forgot:${ip}`, 5, 3600);

  const body = await readJson(request);
  const email = normalizeEmail(requireString(body, 'email', { max: 254 }));
  await enforceLimit(env, `forgot-email:${await sha256Hex(email)}`, 3, 3600);

  const user = await env.DB.prepare('SELECT id, email FROM users WHERE email = ?')
    .bind(email)
    .first<{ id: string; email: string }>();

  if (user) {
    const token = randomToken();
    await env.DB.prepare(
      'INSERT INTO password_resets (token_hash, user_id, expires_at) VALUES (?, ?, ?)',
    )
      .bind(await sha256Hex(token), user.id, now() + RESET_TTL_SECONDS)
      .run();
    await sendResetEmail(env, user.email, token);
  }

  // Identical response whether or not the account exists: the endpoint must
  // not be usable to discover who has an account.
  return json({ status: 'sent' }, 202);
}

async function resetPassword(request: Request, env: Env): Promise<Response> {
  await enforceLimit(env, `reset:${clientIp(request)}`, 10, 3600);

  const body = await readJson(request);
  const token = requireString(body, 'token', { min: 16, max: 200 });
  const password = validatePassword(body.password);

  const row = await env.DB.prepare(
    'SELECT token_hash, user_id, expires_at, used_at FROM password_resets WHERE token_hash = ?',
  )
    .bind(await sha256Hex(token))
    .first<{ token_hash: string; user_id: string; expires_at: number; used_at: number | null }>();

  if (!row || row.used_at !== null || row.expires_at < now()) {
    throw new ApiError(400, 'invalid_token', 'That reset link has expired. Request a new one.');
  }

  await env.DB.batch([
    env.DB.prepare('UPDATE users SET password_hash = ? WHERE id = ?').bind(
      await hashPassword(password),
      row.user_id,
    ),
    env.DB.prepare('UPDATE password_resets SET used_at = ? WHERE token_hash = ?').bind(
      now(),
      row.token_hash,
    ),
    // Changing a password ends every existing session. If the reset was
    // triggered because someone else had access, this is what removes them.
    env.DB.prepare('DELETE FROM sessions WHERE user_id = ?').bind(row.user_id),
  ]);

  return noContent();
}

async function getAccount(request: Request, env: Env): Promise<Response> {
  const user = await authenticate(request, env);
  return json({ user: publicUser(user) });
}

async function deleteAccount(request: Request, env: Env): Promise<Response> {
  const user = await authenticate(request, env);
  // Explicit deletes rather than relying on cascade: D1 requires foreign keys
  // to be enabled per connection, and this must work regardless.
  await env.DB.batch([
    env.DB.prepare('DELETE FROM sync_documents WHERE user_id = ?').bind(user.id),
    env.DB.prepare('DELETE FROM password_resets WHERE user_id = ?').bind(user.id),
    env.DB.prepare('DELETE FROM sessions WHERE user_id = ?').bind(user.id),
    env.DB.prepare('DELETE FROM users WHERE id = ?').bind(user.id),
  ]);
  console.log(JSON.stringify({ event: 'account_deleted', at: now() }));
  return noContent();
}

async function getSync(request: Request, env: Env): Promise<Response> {
  const user = await authenticate(request, env);
  const row = await env.DB.prepare(
    'SELECT payload, updated_at FROM sync_documents WHERE user_id = ?',
  )
    .bind(user.id)
    .first<{ payload: string; updated_at: number }>();

  if (!row) return json({ payload: null, updatedAt: 0 });
  return json({ payload: JSON.parse(row.payload), updatedAt: row.updated_at });
}

async function putSync(request: Request, env: Env): Promise<Response> {
  const user = await authenticate(request, env);
  const body = await readJson(request);

  const payload = body.payload;
  if (payload === undefined || payload === null || typeof payload !== 'object') {
    throw new ApiError(400, 'invalid_payload', 'payload must be an object.');
  }
  const serialized = JSON.stringify(payload);
  if (serialized.length > MAX_SYNC_PAYLOAD_BYTES) {
    throw new ApiError(413, 'payload_too_large', 'That is more data than an account holds.');
  }

  // Last write wins. Two phones editing the same meal history is not a
  // conflict worth a merge algorithm.
  const updatedAt = now();
  await env.DB.prepare(
    `INSERT INTO sync_documents (user_id, payload, updated_at) VALUES (?, ?, ?)
     ON CONFLICT(user_id) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at`,
  )
    .bind(user.id, serialized, updatedAt)
    .run();

  return json({ updatedAt });
}

// ------------------------------------------------------------------- email

async function sendResetEmail(env: Env, to: string, token: string): Promise<void> {
  const link = `${env.RESET_LINK_BASE}?token=${encodeURIComponent(token)}`;
  const text = [
    'Someone asked to reset the password on your PlatePatch account.',
    '',
    'Open this link within the hour to choose a new one:',
    link,
    '',
    'If that was not you, ignore this email — nothing has changed.',
  ].join('\n');

  try {
    await env.EMAIL.send({
      from: { name: 'PlatePatch', email: env.EMAIL_FROM },
      to,
      subject: 'Reset your PlatePatch password',
      text,
      html: `<p>Someone asked to reset the password on your PlatePatch account.</p>
<p><a href="${link}">Choose a new password</a> — the link works for one hour.</p>
<p>If that was not you, ignore this email; nothing has changed.</p>`,
    });
  } catch (error) {
    // A send failure must not tell the caller whether the account exists, and
    // must not fail the request. It is logged and nothing else.
    console.error(JSON.stringify({ event: 'reset_email_failed', message: String(error) }));
  }
}

// ------------------------------------------------------------------ router

type Handler = (request: Request, env: Env) => Promise<Response>;

const ROUTES: Record<string, Partial<Record<string, Handler>>> = {
  '/v1/auth/register': { POST: register },
  '/v1/auth/login': { POST: login },
  '/v1/auth/logout': { POST: logout },
  '/v1/auth/forgot': { POST: forgotPassword },
  '/v1/auth/reset': { POST: resetPassword },
  '/v1/account': { GET: getAccount, DELETE: deleteAccount },
  '/v1/sync': { GET: getSync, PUT: putSync },
};

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === '/health') {
      return json({ ok: true });
    }

    const route = ROUTES[url.pathname];
    if (!route) {
      return json({ error: 'not_found', message: 'No such endpoint.' }, 404);
    }
    const handler = route[request.method];
    if (!handler) {
      return json({ error: 'method_not_allowed', message: 'Wrong method.' }, 405, {
        allow: Object.keys(route).join(', '),
      });
    }

    try {
      const response = await handler(request, env);
      // Housekeeping runs after the response is on its way out.
      ctx.waitUntil(sweep(env).catch(() => {}));
      return response;
    } catch (error) {
      return errorResponse(error);
    }
  },
} satisfies ExportedHandler<Env>;
