-- ============================================================================
-- ## Drop any existing tables (safe to re-run)
-- ============================================================================
DROP TABLE IF EXISTS tag_meta CASCADE;
DROP TABLE IF EXISTS tag_history CASCADE;

-- ============================================================================
-- ## Create the tables
-- ============================================================================
-- A regular Postgres table for tag metadata.
CREATE TABLE tag_meta (
  id SERIAL PRIMARY KEY,
  name VARCHAR(50),
  device VARCHAR(20),
  work_cell VARCHAR(20),
  prod_area VARCHAR(20),
  units VARCHAR(20),

  full_name TEXT GENERATED ALWAYS AS 
    (prod_area || '.' || work_cell || '.' || device || '.' || name) STORED
);

-- A hypertable to store the actual time-series data.
CREATE TABLE tag_history (
  time TIMESTAMPTZ NOT NULL,
  id INTEGER,
  value DOUBLE PRECISION,
  quality SMALLINT,   --OPCUA Quality Flag
  FOREIGN KEY (id) REFERENCES tag_meta (id)
) WITH (
  tsdb.hypertable
--  OPTIONAL PARAMETERS
--    ,
--    tsdb.hypertable = true | false,
--    tsdb.columnstore = true | false,
--    tsdb.partition_column = 'time',
--    tsdb.chunk_interval = '7 DAYS',
--    tsdb.create_default_indexes = true,
--    tsdb.associated_schema = '_timescaledb_internal',
--    tsdb.associated_table_prefix = '_hyper',
--    tsdb.orderby = 'time DESC',
--    tsdb.segmentby = 'tag_id',
--    tsdb.sparse_index = ''
);