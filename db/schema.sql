
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Enumerated types ---------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'measurement_source') THEN
        CREATE TYPE measurement_source AS ENUM ('historic', 'current');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'grid_run_status') THEN
        CREATE TYPE grid_run_status AS ENUM ('pending', 'done', 'failed');
    END IF;
END$$;

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS sensors (
    id              TEXT PRIMARY KEY,
    name            TEXT,
    provider_id     TEXT,
    lat             DOUBLE PRECISION NOT NULL,
    lon             DOUBLE PRECISION NOT NULL,
    elevation_m     DOUBLE PRECISION,
    city            TEXT,
    subbasin        TEXT,
    barrio          TEXT,
    metadata        JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER sensors_set_updated_at
BEFORE UPDATE ON sensors
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS raw_measurements (
    id              BIGSERIAL PRIMARY KEY,
    sensor_id       TEXT NOT NULL REFERENCES sensors(id) ON DELETE CASCADE,
    ts              TIMESTAMPTZ NOT NULL,
    value_mm        DOUBLE PRECISION,
    quality         DOUBLE PRECISION,
    variable        TEXT,
    source          measurement_source NOT NULL,
    ingested_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT raw_measurements_sensor_ts_unique UNIQUE (sensor_id, ts)
);

CREATE TRIGGER raw_measurements_set_updated_at
BEFORE UPDATE ON raw_measurements
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS raw_measurements_ts_idx
    ON raw_measurements (ts);

CREATE INDEX IF NOT EXISTS raw_measurements_sensor_ts_desc_idx
    ON raw_measurements (sensor_id, ts DESC);

CREATE TABLE IF NOT EXISTS clean_measurements (
    id                  BIGSERIAL PRIMARY KEY,
    sensor_id           TEXT NOT NULL REFERENCES sensors(id) ON DELETE CASCADE,
    ts                  TIMESTAMPTZ NOT NULL,
    value_mm            DOUBLE PRECISION NOT NULL,
    qc_flags            INTEGER NOT NULL DEFAULT 0,
    imputation_method   TEXT,
    version             INTEGER NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT clean_measurements_sensor_ts_version_unique UNIQUE (sensor_id, ts, version)
);

CREATE TRIGGER clean_measurements_set_updated_at
BEFORE UPDATE ON clean_measurements
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS clean_measurements_ts_idx
    ON clean_measurements (ts);

CREATE INDEX IF NOT EXISTS clean_measurements_sensor_ts_desc_idx
    ON clean_measurements (sensor_id, ts DESC);

CREATE TABLE IF NOT EXISTS grid_runs (
    id                  BIGSERIAL PRIMARY KEY,
    ts                  TIMESTAMPTZ NOT NULL,
    res_m               INTEGER NOT NULL,
    bbox                JSONB NOT NULL,
    crs                 TEXT NOT NULL DEFAULT 'EPSG:3857',
    blob_url_json       TEXT,
    blob_url_npz        TEXT,
    blob_url_contours   TEXT,
    status              grid_run_status NOT NULL DEFAULT 'pending',
    message             TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT grid_runs_ts_res_unique UNIQUE (ts, res_m)
);

CREATE TRIGGER grid_runs_set_updated_at
BEFORE UPDATE ON grid_runs
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS grid_runs_ts_desc_idx
    ON grid_runs (ts DESC);

CREATE INDEX IF NOT EXISTS grid_runs_status_idx
    ON grid_runs (status);

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

