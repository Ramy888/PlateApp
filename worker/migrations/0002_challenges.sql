-- Single-use nonces for Play Integrity.
--
-- Without a server-issued nonce, attestation is theatre: a token captured once
-- can be replayed forever. The app asks for a challenge, requests an integrity
-- token bound to it, and the Worker checks the nonce came from here and has not
-- been used before.
CREATE TABLE IF NOT EXISTS challenges (
  nonce      TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  used_at    INTEGER
);
CREATE INDEX IF NOT EXISTS challenges_expiry ON challenges(expires_at);
