-- Why an install was refused, kept long enough to read it.
--
-- A live `wrangler tail` only works if someone is watching at the exact
-- moment a phone tries, which turned a five-minute diagnosis into an
-- afternoon. Nothing here identifies a person: a verdict, a reason, and a
-- truncated random nonce.
CREATE TABLE IF NOT EXISTS attestation_failures (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  at INTEGER NOT NULL,
  reason TEXT NOT NULL,
  detail TEXT
);
CREATE INDEX IF NOT EXISTS attestation_failures_at ON attestation_failures (at);
