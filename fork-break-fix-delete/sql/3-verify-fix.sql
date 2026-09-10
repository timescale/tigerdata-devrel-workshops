-- ============================================================================
-- ## 3. Verify — did the agent actually make it faster?
-- ============================================================================
--
-- Run this against fbfd-FORK, after your agent has finished:
--
--   tiger db query "$(scripts/sid fbfd-fork)" \
--        -f sql/3-verify-fix.sql
--
-- Q1, Q2 and Q3 below are copied verbatim from sql/2-baseline.sql. Do not
-- "improve" them. An agent that made the schema faster should not need the query
-- rewritten to prove it.
--
-- Safe to re-run. Read-only.
-- ============================================================================

SELECT count(*) AS total_rows FROM service_requests;

-- ============================================================================
-- ## Q1 — "yesterday" (identical to baseline)
-- ============================================================================
-- Expect a large win. Correct types make the column indexable; the hypertable
-- lets the planner throw away every chunk outside the window before it reads
-- anything.

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
-- ## Q2 — median time to close (identical to baseline)
-- ============================================================================
-- Same story as Q1. Also worth checking that the numbers it returns are the same
-- ones the baseline returned — a fix that changes your answers is not a fix.

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
-- ## Q3 — "zoom out" (identical to baseline)
-- ============================================================================
-- This is the interesting one, and it is interesting because it barely moved.
--
-- If your number here is roughly what it was before the fix: correct. Q3 has to
-- aggregate every row in the table. Chunk exclusion has nothing to exclude, and
-- an index on a column you are not filtering on is dead weight.
--
-- Partitioning makes queries faster by letting them read less. When a query
-- genuinely needs all the data, the only way to read less is to have done the
-- work in advance. See Q4.

EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('day', created_date::timestamptz) AS day,
       complaint_type,
       count(*)                                     AS complaints
FROM service_requests
GROUP BY 1, 2
ORDER BY complaints DESC
LIMIT 20;

-- ============================================================================
-- ## Q4 — the same zoom-out, answered by a continuous aggregate
-- ============================================================================
-- This one is NOT identical to anything in the baseline, and that is the honest
-- trade being demonstrated: a continuous aggregate cannot silently speed up Q3.
-- Nothing rewrites your query for you. You get the speed by asking a different
-- question — one against a rollup that TimescaleDB keeps up to date for you.
--
-- Adjust the view and column names below if your agent named things differently.
-- If this errors with "relation does not exist", your agent stopped at the
-- hypertable and didn't build a continuous aggregate. That is worth going back
-- and asking it about.

EXPLAIN (ANALYZE, BUFFERS)
SELECT day, complaint_type, sum(complaints) AS complaints
FROM daily_complaints
GROUP BY 1, 2
ORDER BY complaints DESC
LIMIT 20;

-- ============================================================================
-- ## What changed?
-- ============================================================================
-- The Tiger CLI has a single command that reports all of this at once:
--
--   tiger db schema "$(scripts/sid fbfd-original)"
--
-- It works on fbfd-original, and it is the nicer way to look at a schema. It
-- does NOT currently work against a fork of a free service -- any read-only
-- connection to one is refused at connect time, and `tiger db schema` always
-- connects read-only. So for the fork, we ask in SQL.

-- Column types. created_date and closed_date should no longer say "text".
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'service_requests'
ORDER BY ordinal_position;

-- Is it a hypertable now, and how is it chunked?
SELECT h.hypertable_name, h.num_dimensions, count(c.chunk_name) AS chunks
FROM timescaledb_information.hypertables h
LEFT JOIN timescaledb_information.chunks c USING (hypertable_name)
GROUP BY 1, 2;

-- Did it build a continuous aggregate?
SELECT view_name, materialization_hypertable_name, compression_enabled
FROM timescaledb_information.continuous_aggregates;

-- Whatever indexes it decided on.
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'service_requests';
