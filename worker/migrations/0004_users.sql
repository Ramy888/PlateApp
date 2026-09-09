-- Google accounts.
--
-- Signing in is what unlocks the model calls, so the account — not the phone —
-- becomes the thing an allowance belongs to. A device is a session against it,
-- and a reinstall no longer hands out a fresh free week.
CREATE TABLE IF NOT EXISTS users (
  sub          TEXT PRIMARY KEY,   -- Google's per-app subject id
  email        TEXT,
  name         TEXT,
  created_at   INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL
);

-- Null for a guest. Everything except the model calls works without one.
ALTER TABLE devices ADD COLUMN user_id TEXT;

CREATE INDEX IF NOT EXISTS devices_user ON devices (user_id);
