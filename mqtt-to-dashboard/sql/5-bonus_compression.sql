-- ============================================================================
-- ## Bonus: columnar compression + retention (run if there's time)
-- ============================================================================
-- These are the knobs that keep this stack cheap and fast in production. We
-- don't dwell on them in the 60-minute session, but they're one command each.

-- ----------------------------------------------------------------------------
-- ## Columnstore (hypercore) — typically 5-10x smaller AND faster for analytics
-- ----------------------------------------------------------------------------
-- Segment by tag_id so each tag's history compresses together; order by time.
ALTER TABLE tag_history SET (
  timescaledb.enable_columnstore = true,
  timescaledb.segmentby          = 'tag_id',
  timescaledb.orderby            = 'ts DESC'
);

-- Automatically move chunks older than 7 days into the columnstore.
-- (add_columnstore_policy is a procedure, so it's called with CALL.)
CALL add_columnstore_policy('tag_history', after => INTERVAL '7 days', if_not_exists => true);

-- See what's compressed:
SELECT * FROM timescaledb_information.hypertable_columnstore_settings;

-- ----------------------------------------------------------------------------
-- ## Retention — drop raw data older than 30 days
-- ----------------------------------------------------------------------------
-- The continuous aggregate keeps the long-term trend, so you can safely expire
-- the high-resolution raw readings underneath it.
SELECT add_retention_policy('tag_history', drop_after => INTERVAL '30 days', if_not_exists => true);

-- Review the policies you've created (the columnstore job may be named
-- policy_compression or policy_columnstore depending on your version):
SELECT job_id, proc_name, hypertable_name, schedule_interval
FROM timescaledb_information.jobs
WHERE proc_name IN ('policy_compression', 'policy_columnstore',
                    'policy_retention', 'policy_refresh_continuous_aggregate');
