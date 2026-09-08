-- Chat replies, so a generated one can be rated and reported.
--
-- Deliberately holds no words: not the user's message and not the model's
-- reply. Those stay on the phone, the same as every meal in this app. What is
-- here is an id, whose device it belongs to, whether a picture came with it,
-- and how it was received.
CREATE TABLE IF NOT EXISTS chat_messages (
  id         TEXT PRIMARY KEY,
  device_id  TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  had_image  INTEGER NOT NULL DEFAULT 0,
  rating     TEXT,
  rated_at   INTEGER
);

-- Deleting a device deletes its ratings, and the sweep prunes old rows.
CREATE INDEX IF NOT EXISTS chat_messages_device ON chat_messages (device_id);
CREATE INDEX IF NOT EXISTS chat_messages_created ON chat_messages (created_at);
