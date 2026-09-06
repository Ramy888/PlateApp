-- PlatePatch scan API.
--
-- There is no user table and no meal table. A device is an anonymous row that
-- exists only to hold a quota; what anyone ate stays on their phone.

CREATE TABLE IF NOT EXISTS devices (
  id            TEXT PRIMARY KEY,
  token_hash    TEXT NOT NULL UNIQUE,   -- SHA-256 of the bearer token
  platform      TEXT NOT NULL,          -- 'android' | 'ios'
  created_at    INTEGER NOT NULL,
  last_seen_at  INTEGER NOT NULL,
  rc_user_id    TEXT                    -- RevenueCat app user id
);
CREATE INDEX IF NOT EXISTS devices_seen ON devices(last_seen_at);

-- Counts only. No image, no food names, nothing about the meal — just enough
-- to see cost, latency and how often recognition comes back empty.
CREATE TABLE IF NOT EXISTS scan_events (
  id              TEXT PRIMARY KEY,
  device_id       TEXT NOT NULL,
  kind            TEXT NOT NULL,        -- 'scan' | 'preview'
  created_at      INTEGER NOT NULL,
  model           TEXT NOT NULL,
  duration_ms     INTEGER NOT NULL,
  outcome         TEXT NOT NULL,        -- 'ok' | 'empty' | 'error'
  matched_count   INTEGER NOT NULL DEFAULT 0,
  unmatched_count INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS scan_events_device ON scan_events(device_id);
CREATE INDEX IF NOT EXISTS scan_events_time ON scan_events(created_at);

-- Google Play requires in-app reporting of AI-generated content.
CREATE TABLE IF NOT EXISTS reports (
  id          TEXT PRIMARY KEY,
  device_id   TEXT NOT NULL,
  target_type TEXT NOT NULL,            -- 'scan' | 'preview'
  target_id   TEXT NOT NULL,
  reason      TEXT NOT NULL,
  note        TEXT,
  created_at  INTEGER NOT NULL,
  resolved_at INTEGER
);
CREATE INDEX IF NOT EXISTS reports_open ON reports(resolved_at, created_at);

-- Coarse abuse limiting on top of the per-device quota, keyed on IP.
CREATE TABLE IF NOT EXISTS rate_limits (
  bucket     TEXT PRIMARY KEY,
  count      INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
