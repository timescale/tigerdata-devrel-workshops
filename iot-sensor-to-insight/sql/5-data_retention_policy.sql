-- ============================================================================
-- ## Step 14 — Retention policy
-- ============================================================================
-- Drop data older than 21 days automatically. The policy runs in the
-- background, but we'll call drop_chunks() directly so you can see it
-- fire right now.
SELECT add_retention_policy('tag_history', INTERVAL '21 days');

-- Manually invoke the equivalent of the policy.
SELECT drop_chunks('tag_history', INTERVAL '21 days');

-- Verify: the oldest chunks are gone.
SELECT
  chunk_name,
  range_start,
  range_end
FROM timescaledb_information.chunks
WHERE hypertable_name = 'tag_history'
ORDER BY range_start;