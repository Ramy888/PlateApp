-- What an unrecognised food is made of, once something has worked it out.
--
-- The catalogue is fifty-one foods and a real plate is not. Rather than grow
-- the catalogue — which is closed on purpose, because it is what reaches the
-- image prompt and the dietary filters — an unknown food is described in the
-- vocabulary the engine already speaks, and the answer is kept here.
--
-- Cached by name so the second plate of pancakes is answered by the first
-- one's reasoning: the app promises the same plate gets the same answer, and
-- asking a model twice would quietly break that.
CREATE TABLE IF NOT EXISTS food_descriptions (
  name        TEXT PRIMARY KEY,   -- lower-cased, trimmed
  protein     INTEGER NOT NULL,
  fibre       INTEGER NOT NULL,
  fat         INTEGER NOT NULL,
  tags        TEXT NOT NULL,      -- comma separated, from a closed vocabulary
  food_group  TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);
