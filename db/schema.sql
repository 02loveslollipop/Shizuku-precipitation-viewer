-- ============================================================================
-- SIATA Contamination Viewer - Complete Database Schema
-- Version: 2.1 (Standard PostgreSQL)
-- Date: October 4, 2025
-- ============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS postgis;

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- Function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Core Tables
-- ============================================================================

-- Sensors metadata
CREATE TABLE IF NOT EXISTS sensors (
    id              TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    provider_id     TEXT,
    lat             DOUBLE PRECISION NOT NULL,
    lon             DOUBLE PRECISION NOT NULL,
    elevation_m     DOUBLE PRECISION,
    city            TEXT,
    subbasin        TEXT,
    barrio          TEXT,
    metadata        JSONB DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER sensors_set_updated_at
BEFORE UPDATE ON sensors
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX sensors_location_idx ON sensors USING GIST (ST_MakePoint(lon, lat));
CREATE INDEX sensors_city_idx ON sensors(city);

COMMENT ON TABLE sensors IS 'Precipitation sensor stations metadata';
COMMENT ON COLUMN sensors.provider_id IS 'External provider identifier (e.g., SIATA station ID)';

-- ============================================================================
-- Measurement Tables
-- ============================================================================

-- Raw measurements from external sources
CREATE TABLE IF NOT EXISTS raw_measurements (
    id              BIGSERIAL PRIMARY KEY,
    sensor_id       TEXT NOT NULL REFERENCES sensors(id) ON DELETE CASCADE,
    ts              TIMESTAMPTZ NOT NULL,
    value_mm        DOUBLE PRECISION,
    quality         INTEGER,
    variable        TEXT,
    source          TEXT DEFAULT 'current',
    ingested_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_measurements_unique_measurement UNIQUE (sensor_id, ts, source)
);

CREATE TRIGGER raw_measurements_set_updated_at
BEFORE UPDATE ON raw_measurements
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX raw_measurements_sensor_ts_idx ON raw_measurements(sensor_id, ts DESC);
CREATE INDEX raw_measurements_ts_idx ON raw_measurements(ts DESC);
CREATE INDEX raw_measurements_source_idx ON raw_measurements(source);

-- Partitioning hint: For very large datasets, consider partitioning by date range
-- Example: PARTITION BY RANGE (ts)

COMMENT ON TABLE raw_measurements IS 'Raw precipitation measurements from external sources';
COMMENT ON COLUMN raw_measurements.source IS 'Data source: "current" for real-time, "historic" for backfilled data';

-- Clean measurements after QC and imputation
CREATE TABLE IF NOT EXISTS clean_measurements (
    id                  BIGSERIAL PRIMARY KEY,
    sensor_id           TEXT NOT NULL REFERENCES sensors(id) ON DELETE CASCADE,
    ts                  TIMESTAMPTZ NOT NULL,
    value_mm            DOUBLE PRECISION,
    qc_flags            INTEGER DEFAULT 0,
    imputation_method   TEXT,
    version             INTEGER DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT clean_measurements_unique_version UNIQUE (sensor_id, ts, version)
);

CREATE TRIGGER clean_measurements_set_updated_at
BEFORE UPDATE ON clean_measurements
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX clean_measurements_sensor_ts_idx ON clean_measurements(sensor_id, ts DESC);
CREATE INDEX clean_measurements_ts_idx ON clean_measurements(ts DESC);
CREATE INDEX clean_measurements_imputation_idx ON clean_measurements(imputation_method) WHERE imputation_method IS NOT NULL;

-- Partitioning hint: For very large datasets, consider partitioning by date range
-- Example: PARTITION BY RANGE (ts)

COMMENT ON TABLE clean_measurements IS 'Quality-controlled precipitation measurements with imputation';
COMMENT ON COLUMN clean_measurements.qc_flags IS 'Quality control flags bitmap';
COMMENT ON COLUMN clean_measurements.imputation_method IS 'Method used for imputation: "ARIMA" or "zero" (fallback)';
COMMENT ON COLUMN clean_measurements.version IS 'Version number for reprocessing tracking';

-- ============================================================================
-- Grid Processing Tables
-- ============================================================================

-- Grid runs metadata and status
CREATE TABLE IF NOT EXISTS grid_runs (
    id                  BIGSERIAL PRIMARY KEY,
    ts                  TIMESTAMPTZ NOT NULL,
    res_m               INTEGER NOT NULL,
    bbox                JSONB NOT NULL DEFAULT '[]'::jsonb,
    crs                 TEXT DEFAULT 'EPSG:3857',
    blob_url_json       TEXT,
    blob_url_contours   TEXT,
    status              TEXT NOT NULL DEFAULT 'pending',
    message             TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT grid_runs_unique_slot UNIQUE (ts, res_m)
);

CREATE TRIGGER grid_runs_set_updated_at
BEFORE UPDATE ON grid_runs
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX grid_runs_ts_idx ON grid_runs(ts DESC);
CREATE INDEX grid_runs_status_idx ON grid_runs(status);

COMMENT ON TABLE grid_runs IS 'Metadata for interpolated precipitation grids';
COMMENT ON COLUMN grid_runs.blob_url_json IS 'URL to grid.json.gz in blob storage';
COMMENT ON COLUMN grid_runs.blob_url_contours IS 'URL to contours.geojson in blob storage';
COMMENT ON COLUMN grid_runs.status IS 'Processing status: pending, done, failed';

-- Grid sensor aggregates (NEW in v2.0)
CREATE TABLE IF NOT EXISTS grid_sensor_aggregates (
    id                  BIGSERIAL PRIMARY KEY,
    grid_run_id         BIGINT NOT NULL REFERENCES grid_runs(id) ON DELETE CASCADE,
    sensor_id           TEXT NOT NULL REFERENCES sensors(id) ON DELETE CASCADE,
    ts_start            TIMESTAMPTZ NOT NULL,
    ts_end              TIMESTAMPTZ NOT NULL,
    avg_mm_h            DOUBLE PRECISION NOT NULL,
    measurement_count   INTEGER NOT NULL,
    min_value_mm        DOUBLE PRECISION,
    max_value_mm        DOUBLE PRECISION,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT grid_sensor_aggregates_unique UNIQUE (grid_run_id, sensor_id)
);

CREATE TRIGGER grid_sensor_aggregates_set_updated_at
BEFORE UPDATE ON grid_sensor_aggregates
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX grid_sensor_aggregates_grid_run_idx ON grid_sensor_aggregates(grid_run_id);
CREATE INDEX grid_sensor_aggregates_sensor_idx ON grid_sensor_aggregates(sensor_id);
CREATE INDEX grid_sensor_aggregates_ts_idx ON grid_sensor_aggregates(ts_start, ts_end);

COMMENT ON TABLE grid_sensor_aggregates IS 'Pre-calculated sensor aggregates for each grid period (v2.0 - API optimization)';
COMMENT ON COLUMN grid_sensor_aggregates.avg_mm_h IS 'Average precipitation rate in mm/hour for the grid period';
COMMENT ON COLUMN grid_sensor_aggregates.measurement_count IS 'Number of clean measurements used in calculation';

-- ============================================================================
-- Views
-- ============================================================================

-- Latest clean measurement per sensor
CREATE OR REPLACE VIEW latest_clean_measurements AS
SELECT DISTINCT ON (sensor_id)
    sensor_id,
    ts,
    value_mm,
    qc_flags,
    imputation_method,
    version
FROM clean_measurements
ORDER BY sensor_id, ts DESC, version DESC;

COMMENT ON VIEW latest_clean_measurements IS 'Most recent clean measurement for each sensor';

