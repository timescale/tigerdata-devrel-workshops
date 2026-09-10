-- ============================================================================
-- ## 4. Compare — prove the original never moved
-- ============================================================================
--
-- Run this against fbfd-ORIGINAL:
--
--   psql "$(scripts/conn fbfd-original)" \
--        -f sql/4-compare-original.sql
--
-- Your agent just did genuinely destructive work — rewrote column types, created
-- and dropped tables, added indexes. This is the file that shows none of it
-- reached the service you forked from.
--
-- Safe to re-run. Read-only.
-- ============================================================================

-- Still every column text?
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'service_requests'
ORDER BY ordinal_position;

-- Still not a hypertable? (Expect zero rows.)
SELECT hypertable_name
FROM timescaledb_information.hypertables;

-- Still no continuous aggregates? (Expect zero rows.)
SELECT view_name
FROM timescaledb_information.continuous_aggregates;

-- Still no indexes beyond whatever you started with? (Expect zero rows.)
SELECT indexname
FROM pg_indexes
WHERE tablename = 'service_requests';

-- Same row count as before.
SELECT count(*) AS total_rows FROM service_requests;

-- ============================================================================
-- ## The point
-- ============================================================================
-- Nothing above changed. The agent had full write access to a real database with
-- a million rows of real data in it, and the thing you care about is untouched —
-- not because the agent was careful, but because it was never pointed at it.
--
-- That is the whole trick. The guardrail is not "be careful". The guardrail is
-- "the blast radius is disposable".
--
-- Now go delete the fork:
--
--   tiger service delete fbfd-fork --confirm
