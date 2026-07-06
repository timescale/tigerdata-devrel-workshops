-- ============================================================================
-- ## Is data landing?
-- ============================================================================
-- Run this a few seconds after the consumer connects. The count should climb
-- every time you re-run it.
SELECT count(*) AS total_readings FROM tag_history;

-- The most recent readings, newest first.
SELECT ts, tag_id, value, quality
FROM tag_history
ORDER BY ts DESC
LIMIT 10;

-- ============================================================================
-- ## Join readings to their metadata (facts + context)
-- ============================================================================
-- The hypertable stores compact facts; tag_meta gives them meaning. Joining
-- the two is the everyday pattern for an operational query.
SELECT
  r.ts,
  a.uns_path,
  a.asset,
  a.metric,
  r.value,
  a.unit,
  r.quality
FROM tag_history r
JOIN tag_meta a ON a.tag_id = r.tag_id
ORDER BY r.ts DESC
LIMIT 15;

-- ============================================================================
-- ## How much data per tag?
-- ============================================================================
SELECT
  a.uns_path,
  count(*)        AS readings,
  min(r.ts)       AS first_seen,
  max(r.ts)       AS last_seen
FROM tag_history r
JOIN tag_meta a ON a.tag_id = r.tag_id
GROUP BY a.uns_path
ORDER BY a.uns_path;

-- ============================================================================
-- ## Any bad-quality readings?
-- ============================================================================
-- The producer emits an occasional Bad (0) quality code. In production you'd
-- filter or flag these; here it's a good excuse to write a WHERE clause.
SELECT a.uns_path, r.ts, r.value, r.quality
FROM tag_history r
JOIN tag_meta a ON a.tag_id = r.tag_id
WHERE r.quality <> 192
ORDER BY r.ts DESC
LIMIT 10;
