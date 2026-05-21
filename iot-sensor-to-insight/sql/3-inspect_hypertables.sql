-- ============================================================================
-- ## Manually run compression policy
-- ============================================================================
-- The policy runs in the background. For demo purposes we'll trigger
-- compression now so we don't have to wait for the scheduler.
SELECT compress_chunk(c, true) FROM show_chunks('tag_history') c;

-- ============================================================================
-- ## View Timescale partitions
-- ============================================================================
-- Hypertables automatically split data into "chunks" by time. With 30 days
-- of data and the default 7-day chunk interval, you'll see ~6 chunks.
SELECT
  chunk_name,
  range_start,
  range_end,
  is_compressed
FROM timescaledb_information.chunks
WHERE hypertable_name = 'tag_history'
ORDER BY range_start;

-- ============================================================================
-- ## Compare storage requirements
-- ============================================================================
-- The actual compression ratio depends on the nature of the data. With real 
-- data (which is often very uniform) it'll typically be 5-10x

SELECT
  (SELECT COUNT(*) FROM tag_history) AS n_rows,
  pg_size_pretty(before_compression_total_bytes) AS before,
  pg_size_pretty(after_compression_total_bytes)  AS after_,
  ROUND(
    before_compression_total_bytes::NUMERIC /
    NULLIF(after_compression_total_bytes::NUMERIC, 0),
    2
  ) AS compression_ratio
FROM hypertable_compression_stats('tag_history');