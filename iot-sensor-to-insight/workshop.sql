-- ============================================================================
-- From Sensor to Insight: Real-Time IoT Analytics with TimescaleDB
-- 60-minute hands-on workshop
-- ============================================================================
-- You'll build a working IoT analytics pipeline on Tiger Cloud:
--   1. Create a hypertable to store sensor data
--   2. Generate a 30-day dataset (~2M rows)
--   3. Run time-series queries with time_bucket() and hyperfunctions
--   4. Enable columnar compression and compare query performance
--   5. Create a continuous aggregate for real-time dashboards
--   6. Add a retention policy
--
-- Run sections one at a time. Each is independent — if you fall behind,
-- the next section will still work.
-- ============================================================================


-- ============================================================================
-- ## Setup: drop any existing tables (safe to re-run)
-- ============================================================================
DROP TABLE IF EXISTS sensors CASCADE;
DROP TABLE IF EXISTS sensor_data CASCADE;


-- ============================================================================
-- ## Step 1 — Create the tables
-- ============================================================================
-- A regular Postgres heap table for sensor metadata.
CREATE TABLE sensors (
  id SERIAL PRIMARY KEY,
  type VARCHAR(50),
  location VARCHAR(50)
);

-- A hypertable to store the actual time-series data.
-- We'll enable columnar compression explicitly in Step 8 — not here —
-- so you can see the before/after performance difference.
CREATE TABLE sensor_data (
  time TIMESTAMPTZ NOT NULL,
  sensor_id INTEGER,
  temperature DOUBLE PRECISION,
  cpu DOUBLE PRECISION,
  FOREIGN KEY (sensor_id) REFERENCES sensors (id)
) WITH (
  tsdb.hypertable,
  tsdb.partition_column = 'time',
  tsdb.segmentby = 'sensor_id',
  tsdb.orderby = 'time DESC'
);

-- Hypertables auto-index on the time column. Add a secondary index on
-- sensor_id so the (sensor_id, time) filter pattern is fast.
CREATE INDEX ON sensor_data (sensor_id, time);


-- ============================================================================
-- ## Step 2 — Populate the metadata table
-- ============================================================================
INSERT INTO sensors (type, location) VALUES
  ('a', 'floor'),
  ('a', 'ceiling'),
  ('b', 'floor'),
  ('b', 'ceiling');

SELECT * FROM sensors;
-- Expected: 4 rows


-- ============================================================================
-- ## Step 3 — Generate 30 days of sensor data
-- ============================================================================
-- 4 sensors × 1 reading every 5 seconds × 30 days = ~2.07M rows.
-- On the smallest paid Tiger Cloud SKU this takes ~30–40 seconds.
INSERT INTO sensor_data (time, sensor_id, cpu, temperature)
SELECT
  time,
  sensor_id,
  random() AS cpu,
  random() * 100 AS temperature
FROM
  generate_series(now() - INTERVAL '30 days', now(), INTERVAL '5 seconds') AS g1(time),
  generate_series(1, 4, 1) AS g2(sensor_id);


-- ============================================================================
-- ## Step 4 — See how Timescale partitioned your data
-- ============================================================================
-- Hypertables automatically split data into "chunks" by time. With 30 days
-- of data and the default 7-day chunk interval, you'll see ~5 chunks.
SELECT
  chunk_name,
  range_start,
  range_end,
  is_compressed
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sensor_data'
ORDER BY range_start;

-- Quick row count sanity check
SELECT COUNT(*) FROM sensor_data;


-- ============================================================================
-- ## Step 5 — Time-series queries: time_bucket() and hyperfunctions
-- ============================================================================
-- time_bucket() is like date_trunc() but more flexible — any interval works.
-- last() is a hyperfunction that grabs the most recent value within a group.
SELECT
  time_bucket('30 minutes', time) AS period,
  AVG(temperature) AS avg_temp,
  last(temperature, time) AS last_temp,
  AVG(cpu) AS avg_cpu
FROM sensor_data
GROUP BY period
ORDER BY period DESC
LIMIT 20;


-- ============================================================================
-- ## Step 6 — JOIN the hypertable with the metadata table
-- ============================================================================
-- Hypertables are full-featured Postgres tables. You can JOIN, GROUP BY,
-- subquery — anything you'd do in vanilla Postgres just works.
SELECT
  sensors.location,
  time_bucket('30 minutes', time) AS period,
  AVG(temperature) AS avg_temp,
  last(temperature, time) AS last_temp,
  AVG(cpu) AS avg_cpu
FROM sensor_data
JOIN sensors ON sensor_data.sensor_id = sensors.id
GROUP BY period, sensors.location
ORDER BY period DESC
LIMIT 20;


-- ============================================================================
-- ## Step 7 — Baseline: query against UNCOMPRESSED data
-- ============================================================================
-- Note the timing. We'll run this exact same query against compressed
-- data in Step 10 and compare.
--
-- (In psql, run `\timing on` once at the start of your session to see
-- query times. Otherwise, watch the wall clock or use EXPLAIN ANALYZE.)
SELECT
  time_bucket('1 day', time) AS period,
  AVG(temperature) AS avg_temp,
  last(temperature, time) AS last_temp,
  AVG(cpu) AS avg_cpu
FROM sensor_data
WHERE sensor_id = 4
  AND time >= NOW() - INTERVAL '14 days'
GROUP BY period
ORDER BY period;


-- ============================================================================
-- ## Step 8 — Enable columnar compression
-- ============================================================================
-- The columnstore policy compresses chunks older than the cutoff. We use
-- 7 days here so most chunks get compressed but the most recent one stays
-- on the row store (typical pattern — keep recent data cheap to write to,
-- compress older data for storage savings and faster analytical queries).
CALL add_columnstore_policy('sensor_data', after => INTERVAL '7 days');

-- The policy runs in the background. For demo purposes we'll trigger
-- compression now so we don't have to wait for the scheduler.
SELECT compress_chunk(c, true) FROM show_chunks('sensor_data') c;


-- ============================================================================
-- ## Step 9 — See how much space compression saved
-- ============================================================================
-- Compression ratio on randomly-generated data like ours is the worst
-- case (high entropy → little to compress). Expect roughly 5–10×.
-- Real correlated sensor data typically does better.
SELECT
  pg_size_pretty(before_compression_total_bytes) AS before,
  pg_size_pretty(after_compression_total_bytes)  AS after_,
  ROUND(
    before_compression_total_bytes::NUMERIC /
    NULLIF(after_compression_total_bytes::NUMERIC, 0),
    2
  ) AS ratio_x
FROM hypertable_compression_stats('sensor_data');


-- ============================================================================
-- ## Step 10 — Re-run the Step 7 query, now on COMPRESSED data
-- ============================================================================
-- Same query as Step 7. Compare the time against your baseline.
SELECT
  time_bucket('1 day', time) AS period,
  AVG(temperature) AS avg_temp,
  last(temperature, time) AS last_temp,
  AVG(cpu) AS avg_cpu
FROM sensor_data
WHERE sensor_id = 4
  AND time >= NOW() - INTERVAL '14 days'
GROUP BY period
ORDER BY period;


-- ============================================================================
-- ## Step 11 — Continuous aggregates
-- ============================================================================
-- A continuous aggregate is a materialized view that auto-updates as new
-- data arrives. You query it like a regular table, but it's pre-computed.
CREATE MATERIALIZED VIEW one_day_summary
WITH (timescaledb.continuous, timescaledb.materialized_only = false) AS
SELECT
  time_bucket('1 day', time) AS period,
  sensor_id,
  AVG(temperature) AS avg_temp,
  last(temperature, time) AS last_temp,
  AVG(cpu) AS avg_cpu
FROM sensor_data
GROUP BY period, sensor_id;

-- Attach a refresh policy so it stays current automatically.
SELECT add_continuous_aggregate_policy('one_day_summary',
  start_offset      => INTERVAL '3 days',
  end_offset        => INTERVAL '1 day',
  schedule_interval => INTERVAL '1 day');


-- ============================================================================
-- ## Step 12 — Query the continuous aggregate
-- ============================================================================
-- Same kind of question as Step 10, but answered from the pre-aggregated
-- materialized view — typically sub-millisecond.
SELECT *
FROM one_day_summary
WHERE sensor_id = 4
  AND period >= NOW() - INTERVAL '14 days'
ORDER BY period;


-- ============================================================================
-- ## Step 13 — Watch the CAGG auto-update in real time
-- ============================================================================
-- Insert a synthetic future reading. Because we set
-- materialized_only = false on the view, the CAGG transparently includes
-- the new row immediately — no manual refresh needed.
INSERT INTO sensor_data (time, sensor_id, cpu, temperature)
VALUES (NOW() + INTERVAL '1 day', 4, 5, 150);

SELECT *
FROM one_day_summary
WHERE sensor_id = 4
  AND period >= NOW()
ORDER BY period;


-- ============================================================================
-- ## Step 14 — Retention policy
-- ============================================================================
-- Drop data older than 21 days automatically. The policy runs in the
-- background, but we'll call drop_chunks() directly so you can see it
-- fire right now.
SELECT add_retention_policy('sensor_data', INTERVAL '21 days');

-- Manually invoke the equivalent of the policy.
SELECT drop_chunks('sensor_data', INTERVAL '21 days');

-- Verify: the oldest chunks are gone.
SELECT
  chunk_name,
  range_start,
  range_end
FROM timescaledb_information.chunks
WHERE hypertable_name = 'sensor_data'
ORDER BY range_start;


-- ============================================================================
-- ## You're done!
-- ============================================================================
-- What we covered:
--   * Hypertables (Step 1)
--   * Time-series queries: time_bucket, last() (Steps 5-6)
--   * Columnar compression with 5-10x ratio + faster queries (Steps 7-10)
--   * Continuous aggregates with real-time updates (Steps 11-13)
--   * Retention policies (Step 14)
--
-- What we skipped for time:
--   * Tiered storage to S3 — docs.tigerdata.com/use-timescale/latest/data-tiering
--   * Sparse index tuning for compressed chunks
--   * Migrating an existing Postgres table to a hypertable
--
-- Your service is still up. Trial credits last a while — keep playing.
-- ============================================================================
