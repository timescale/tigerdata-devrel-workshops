-- ============================================================================
-- ## 1. The bad schema
-- ============================================================================
--
-- Run this against fbfd-original BEFORE the workshop:
--
--   tiger db query "$(scripts/sid fbfd-original)" \
--        -f sql/1-bad-schema.sql
--
-- Everything wrong with this table is wrong on purpose. It is not a strawman —
-- this is what a table looks like when someone loaded a CSV in a hurry and
-- shipped it. Every column is text because every column in a CSV is text.
--
-- Safe to re-run.
-- ============================================================================

DROP TABLE IF EXISTS service_requests CASCADE;

CREATE TABLE service_requests (
    unique_key      text,   -- should be bigint
    created_date    text,   -- should be timestamptz   <-- this is the whole workshop
    closed_date     text,   -- should be timestamptz
    agency          text,   -- fine as text
    complaint_type  text,   -- fine as text
    descriptor      text,   -- fine as text
    borough         text,   -- fine as text
    incident_zip    text,   -- fine as text (leading zeros are real)
    latitude        text,   -- should be double precision
    longitude       text    -- should be double precision
);

-- Note what is NOT here:
--   * no primary key
--   * no indexes of any kind
--   * no hypertable, so no chunking, no columnstore, no continuous aggregates
--
-- The interesting one is `created_date text`. An agent's first instinct will be to
-- reach for an index on it. Postgres will not let it — see sql/2-baseline.sql.

-- ============================================================================
-- ## Confirm the damage
-- ============================================================================
-- Ten text columns, no keys, no indexes. The Tiger CLI will show you:
--
--   tiger db schema "$(scripts/sid fbfd-original)"

