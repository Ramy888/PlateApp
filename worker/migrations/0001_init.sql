-- PlatePatch accounts. Deliberately small: an account exists to move saved
-- patches between devices, nothing more. No names, no profiles, no analytics.

CREATE TABLE IF NOT EXISTS users (
  id            TEXT PRIMARY KEY,
  email         TEXT NOT NULL UNIQUE,   -- always stored lowercased and trimmed
  password_hash TEXT NOT NULL,          -- pbkdf2$<iterations>$<salt_b64>$<hash_b64>
  created_at    INTEGER NOT NULL
);

-- Opaque session tokens. Only the SHA-256 of a token is stored, so a database
-- dump cannot be replayed against the API.
CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);
CREATE INDEX IF NOT EXISTS sessions_expiry ON sessions(expires_at);

-- Password reset tokens: hashed, single use, short lived.
CREATE TABLE IF NOT EXISTS password_resets (
  token_hash TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at INTEGER NOT NULL,
  used_at    INTEGER
);
CREATE INDEX IF NOT EXISTS resets_user ON password_resets(user_id);

-- One row per user: the whole synced document, last write wins. Meal data is
-- opaque to the server; it is stored exactly as the app sent it.
CREATE TABLE IF NOT EXISTS sync_documents (
  user_id    TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  payload    TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Fixed-window rate limiting. Cheap, and good enough to stop credential
-- stuffing and reset-email abuse from a single address.
CREATE TABLE IF NOT EXISTS rate_limits (
  bucket     TEXT PRIMARY KEY,
  count      INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
