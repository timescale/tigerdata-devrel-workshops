-- ============================================================================
-- ## last() — the current value of every tag
-- ============================================================================
-- `last(value, ts)` returns the value with the most recent timestamp per group.
-- This is the query behind a "current readings" panel on a dashboard.
SELECT
  a.uns_path,
  last(r.value, r.ts) AS current_value,
  a.unit
FROM tag_history r
JOIN tag_meta a ON a.tag_id = r.tag_id
GROUP BY a.uns_path, a.unit
ORDER BY a.uns_path;

-- ============================================================================
-- ## time_bucket() — downsample into fixed intervals
-- ============================================================================
-- Raw readings arrive every couple of seconds. For a trend line you rarely want
-- every point — you want an average per bucket. `time_bucket()` groups rows into
-- evenly spaced time windows (here, 10 seconds).
SELECT
  time_bucket('10 seconds', r.ts) AS bucket,
  a.uns_path,
  avg(r.value) AS avg_value,
  max(r.value) AS max_value,
  min(r.value) AS min_value
FROM tag_history r
JOIN tag_meta a ON a.tag_id = r.tag_id
WHERE a.metric = 'temperature'
  AND r.ts > now() - INTERVAL '10 minutes'
GROUP BY bucket, a.uns_path
ORDER BY bucket DESC, a.uns_path;

-- ============================================================================
-- ## Per-minute trend for a single tag
-- ============================================================================
-- The same idea at 1-minute resolution — this is the shape Grafana charts.
SELECT
  time_bucket('1 minute', r.ts) AS minute,
  avg(r.value) AS avg_value
FROM tag_history r
JOIN tag_meta a ON a.tag_id = r.tag_id
WHERE a.uns_path = 'plant1/line-b/reactor/temperature'
  AND r.ts > now() - INTERVAL '30 minutes'
GROUP BY minute
ORDER BY minute DESC;

-- ============================================================================
-- ## Bonus: only count Good-quality readings
-- ============================================================================
-- Real telemetry is noisy. Filtering by quality inside the aggregate keeps bad
-- points out of your averages.
SELECT
  time_bucket('1 minute', r.ts) AS minute,
  a.uns_path,
  avg(r.value) FILTER (WHERE r.quality = 192) AS avg_good_value,
  count(*)     FILTER (WHERE r.quality <> 192) AS bad_points
FROM tag_history r
JOIN tag_meta a ON a.tag_id = r.tag_id
WHERE a.metric = 'pressure'
  AND r.ts > now() - INTERVAL '15 minutes'
GROUP BY minute, a.uns_path
ORDER BY minute DESC, a.uns_path;
