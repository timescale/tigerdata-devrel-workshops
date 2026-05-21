-- ============================================================================
-- ## Clear any existing data (safe to re-run)
-- ============================================================================
TRUNCATE TABLE tag_meta RESTART IDENTITY CASCADE; --restart id generation
TRUNCATE TABLE tag_history CASCADE;

-- ============================================================================
-- ## Populate the metadata table
-- ============================================================================
INSERT INTO tag_meta (name, device, work_cell, prod_area, units) VALUES
    ('speed',        'agitator_01',  'reactor_01',    'mixing',    'rpm'),
    ('flow_rate',    'pump_01',      'filler_01',     'filling',   'lpm'),
    ('total_volume', 'pump_01',      'filler_01',     'filling',   'l'),
    ('speed',        'conveyor_a',   'filler_01',     'filling',   'mpm'),
    ('pressure',     'air_receiver', 'compressor_01', 'utilities', 'kpa'),
    ('current',      'motor_01',     'compressor_01', 'utilities', 'a')
    ;

SELECT * FROM tag_meta;
-- Expected: 10 rows


-- ============================================================================
-- ## Generate 30 days of sensor data
-- ============================================================================
-- 4 sensors × 1 reading every 5 seconds × 30 days = ~2.07M rows.
-- On the smallest paid Tiger Cloud SKU this takes ~30–40 seconds.
INSERT INTO tag_history (time, id, value, quality)
SELECT
    g1.time,
    tag_meta.id,
    random_normal(100,10) AS value,
    192 -- Quality = Good
FROM
  generate_series(now() - INTERVAL '30 days', now(), INTERVAL '1 seconds') AS g1(time),
  tag_meta;