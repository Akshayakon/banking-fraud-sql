-- Indexes that serve the window-function partitions and the lookups above.
-- Window functions PARTITION BY name_orig ORDER BY step, txn_id -> a composite index
-- in that exact order lets the engine skip its sort step.
CREATE INDEX IF NOT EXISTS idx_orig_step ON transactions(name_orig, step, txn_id);
CREATE INDEX IF NOT EXISTS idx_dest_step ON transactions(name_dest, step);
CREATE INDEX IF NOT EXISTS idx_fraud     ON transactions(is_fraud) WHERE is_fraud = 1;  -- partial index
