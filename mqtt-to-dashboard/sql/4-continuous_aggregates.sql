-- ============================================================================
-- ## Why a continuous aggregate?
-- ============================================================================
-- The time_bucket() queries in file 3 re-scan raw readings every time they run.
-- That's fine now, but as data and devices pile up, a dashboard hitting them
-- every few seconds gets slow. A continuous aggregate is a materialized view
-- that TimescaleDB keeps up to date automatically as new data arrives — you
-- query pre-computed buckets instead of raw rows.

-- ============================================================================
-- ## Drop existing view (safe to re-run)
-- ============================================================================
DROP MATERIALIZED VIEW IF EXISTS tag_history_1m;

-- ============================================================================
-- ## Create the continuous aggregate
-- ============================================================================
-- `materialized_only = false` means queries also see the most recent raw data
-- that hasn't been materialized yet — so the dashboard is never stale.
CREATE MATERIALIZED VIEW tag_history_1m
WITH (timescaledb.continuous, timescaledb.materialized_only = false) AS
SELECT
  time_bucket('1 minute', ts) AS bucket,
  tag_id,
  avg(value) AS avg_value,
  max(value) AS max_value,
  min(value) AS min_value
FROM tag_history
GROUP BY bucket, tag_id;

-- ============================================================================
-- ## Add a refresh policy
-- ============================================================================
-- Keep buckets from the last hour fresh, refreshing every minute. `end_offset`
-- leaves the newest minute to the real-time layer (materialized_only = false).
SELECT add_continuous_aggregate_policy('tag_history_1m',
  start_offset      => INTERVAL '1 hour',
  end_offset        => INTERVAL '1 minute',
  schedule_interval => INTERVAL '1 minute');

-- ============================================================================
-- ## Query it — same shape as file 3, but reading pre-computed buckets
-- ============================================================================
SELECT
  m.bucket,
  a.uns_path,
  m.avg_value,
  a.unit
FROM tag_history_1m m
JOIN tag_meta a ON a.tag_id = m.tag_id
WHERE a.metric = 'temperature'
  AND m.bucket > now() - INTERVAL '30 minutes'
ORDER BY m.bucket DESC, a.uns_path;

-- Tip: point the Grafana temperature/pressure panels at tag_history_1m instead of
-- the raw tag_history table once this view exists — same data, faster dashboards.
