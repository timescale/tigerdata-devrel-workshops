-- ============================================================================
-- ## 2. Baseline — measure how bad it is
-- ============================================================================
--
-- Run this against fbfd-original:
--
--   tiger db query "$(scripts/sid fbfd-original)" \
--        -f sql/2-baseline.sql
--
-- Three queries, three different shapes of dashboard panel. Write all three
-- timings down -- they come from the "Execution Time" line at the bottom of each
-- EXPLAIN plan. You will run these exact queries again in sql/3-verify-fix.sql,
-- and the comparison is only honest if the query text is byte-for-byte identical.
--
-- Safe to re-run. Read-only.
-- ============================================================================

SELECT count(*) AS total_rows FROM service_requests;

-- ============================================================================
-- ## Q1 — "yesterday": complaints by type for a single day
-- ============================================================================
-- The most common panel on any dashboard: a narrow, recent time window.
--
-- One day out of four months is roughly 0.8% of the table. A database that
-- understood this column was a timestamp would read about 8,000 rows. Watch how
-- many this one reads.

EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('day', created_date::timestamptz) AS day,
       complaint_type,
       count(*)                                     AS complaints
FROM service_requests
WHERE created_date::timestamptz >= '2024-02-15'
  AND created_date::timestamptz <  '2024-02-16'
GROUP BY 1, 2
ORDER BY complaints DESC
LIMIT 20;

-- ============================================================================
-- ## Q2 — median time to close, by borough, same single day
-- ============================================================================
-- Same window, more work per row: casts both date columns and does interval
-- arithmetic on the results.
--
-- NULLIF(...::text, '') looks over-defensive because it is deliberate: this exact
-- query has to run unchanged against the fixed schema in step 3, where these are
-- real timestamptz columns. Casting to text first makes it valid in both worlds.

EXPLAIN (ANALYZE, BUFFERS)
SELECT borough,
       count(*) AS closed_requests,
       percentile_cont(0.5) WITHIN GROUP (
           ORDER BY EXTRACT(epoch FROM (
               NULLIF(closed_date::text, '')::timestamptz
             - NULLIF(created_date::text, '')::timestamptz
           ))
       ) / 3600.0 AS median_hours_to_close
FROM service_requests
WHERE closed_date IS NOT NULL
  AND created_date::timestamptz >= '2024-02-15'
  AND created_date::timestamptz <  '2024-02-16'
GROUP BY borough
ORDER BY median_hours_to_close DESC;

-- ============================================================================
-- ## Q3 — "zoom out": daily counts across the whole dataset
-- ============================================================================
-- No time filter at all. This one has to touch every row no matter how clever the
-- schema is.
--
-- Keep an eye on this query specifically. In step 3 you will find that fixing the
-- types and adding a hypertable does almost nothing for it, which is not a
-- failure — it is the point. Partitioning helps queries that can skip data. Q3
-- can't skip anything.

EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('day', created_date::timestamptz) AS day,
       complaint_type,
       count(*)                                     AS complaints
FROM service_requests
GROUP BY 1, 2
ORDER BY complaints DESC
LIMIT 20;

-- ============================================================================
-- ## Optional: prove you cannot index your way out
-- ============================================================================
-- Do not run this as part of the script — it is supposed to fail. Paste it into
-- psql by hand if you want to see the error yourself:
--
--   CREATE INDEX ON service_requests ((created_date::timestamptz));
--
--   ERROR:  functions in index expression must be marked IMMUTABLE
--
-- text -> timestamptz depends on the session TimeZone setting, so it is STABLE,
-- not IMMUTABLE, and Postgres refuses to build an index on it. There is no clever
-- index that rescues a wrong data type. You have to fix the type.
--
-- This is the wall your agent is going to hit in step 4. Let it.
