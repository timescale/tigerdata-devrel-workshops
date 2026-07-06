-- ============================================================================
-- ## Drop any existing tables (safe to re-run)
-- ============================================================================
DROP TABLE IF EXISTS tag_history CASCADE;
DROP TABLE IF EXISTS tag_meta CASCADE;

-- ============================================================================
-- ## Metadata table: one row per tag (equipment / asset context)
-- ============================================================================
-- A plain Postgres table describing each sensor "tag". `uns_path` mirrors the
-- MQTT topic hierarchy (the Unified Namespace), so a reading can always be
-- traced back to the plant / line / asset that produced it.
CREATE TABLE tag_meta (
  tag_id      TEXT PRIMARY KEY,   -- e.g. 'T-101'
  uns_path    TEXT NOT NULL,      -- e.g. 'plant1/line-a/mixer/temperature'
  asset       TEXT NOT NULL,      -- e.g. 'mixer'
  metric      TEXT NOT NULL,      -- e.g. 'temperature'
  unit        TEXT,               -- e.g. '°C'
  description TEXT
);

-- ============================================================================
-- ## Readings table: the hypertable (time-series facts)
-- ============================================================================
-- The `WITH (tsdb.hypertable, ...)` clause turns this into a TimescaleDB
-- hypertable at creation time — no separate create_hypertable() call needed.
-- A hypertable is a regular table that's automatically partitioned by time
-- into "chunks", which is what keeps ingestion and time-range queries fast.
CREATE TABLE tag_history (
  ts       TIMESTAMPTZ      NOT NULL,
  tag_id   TEXT             NOT NULL REFERENCES tag_meta (tag_id),
  value    DOUBLE PRECISION,
  quality  INT,             -- OPC-UA-style quality code (192 = Good, 0 = Bad)
  PRIMARY KEY (tag_id, ts)
) WITH (
  tsdb.hypertable,
  tsdb.partition_column = 'ts'
--  OPTIONAL PARAMETERS
--    ,
--    tsdb.chunk_interval = '1 day',
--    tsdb.segmentby = 'tag_id',
--    tsdb.orderby = 'ts DESC'
);

-- ============================================================================
-- ## Seed the metadata for our plant
-- ============================================================================
-- The consumer will auto-register any tag it sees, but seeding here gives us
-- friendly units and descriptions up front. These tag_ids match the producer.
INSERT INTO tag_meta (tag_id, uns_path, asset, metric, unit, description) VALUES
  ('T-101', 'plant1/line-a/mixer/temperature',  'mixer',   'temperature', '°C',    'Line A mixer jacket temperature'),
  ('P-101', 'plant1/line-a/mixer/pressure',     'mixer',   'pressure',    'bar',   'Line A mixer vessel pressure'),
  ('M-101', 'plant1/line-a/mixer/motor_state',  'mixer',   'motor_state', 'state', 'Line A mixer motor run state (1=on)'),
  ('T-201', 'plant1/line-b/reactor/temperature','reactor', 'temperature', '°C',    'Line B reactor core temperature'),
  ('P-201', 'plant1/line-b/reactor/pressure',   'reactor', 'pressure',    'bar',   'Line B reactor pressure'),
  ('F-201', 'plant1/line-b/filler/flow_rate',   'filler',  'flow_rate',   'L/min', 'Line B filler outlet flow rate')
ON CONFLICT (tag_id) DO NOTHING;

-- Confirm it worked:
SELECT * FROM tag_meta ORDER BY uns_path;
