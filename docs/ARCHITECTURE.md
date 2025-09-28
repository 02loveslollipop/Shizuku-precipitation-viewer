# Precipitation Grid System — Architecture & Plan

## Summary
Six-component architecture:
1) API watcher (cron job, Go/Gin) ingests current data to DB.
2) NeonDB PostgreSQL stores raw and cleaned data (+ grid run status).
3) Cleaning service (cron job, Python) applies QC + imputation to raw → clean.
4) ETL grid service (cron job, Python) computes/interpolates grids and uploads to Blob (no public API here).
5) REST API (Go/Gin) exposes sensor queries and latest grid link (public).
6) Visualization (Flutter) renders client-side from public Blob + API.

We will progress in gated steps and pause after each milestone for review.

## System Components
1. API Watcher (Go/Gin, cron)
   - Polls current JSON feed on schedule and writes only new measurements to `raw_measurements`.
   - Upserts `sensors` as needed. Idempotent via unique `(sensor_id, ts)`.
2. NeonDB PostgreSQL
   - Tables: `sensors`, `raw_measurements`, `clean_measurements`, `grid_runs`.
   - Optional: PostGIS for geometry; TimescaleDB if supported (else standard indexes).
3. Cleaning Service (Python, cron)
   - Reads recent `raw_measurements`, flags outliers, imputes gaps, writes to `clean_measurements` with QC metadata.
4. ETL Grid Service (Python, cron)
   - Determines unprocessed time slots (from `grid_runs`), builds Cartesian grid (500 m), Lanczos4 interpolation + nearest-fill, uploads artifacts to public Blob, and marks runs done. No external API.
5. REST API (Go/Gin, public)
   - Endpoints to list sensors and query measurements; `GET /grid/latest` returns 200 with `{ "grid_url": "..." }`.
6. Visualization (Flutter)
   - Client-side rendering using `grid_{iso}.json.gz` and contours; map via free tiles (OSM).

## Data Sources
- Historic JSON: https://datosabiertos.metropol.gov.co/sites/default/files/uploaded_resources/Datos_SIATA_Vaisala_precipitacion_0.json
- Current JSON: https://siata.gov.co/data/siata_app/Pluviometrica.json

Assumed fields (to be validated in Step 2):
- `sensor_id` (string), `lat` (float), `lon` (float), `timestamp` (ISO 8601, UTC), `precipitation_mm` (float).

## Stack Overview
- Database: PostgreSQL (on NeonDB). Optional: TimescaleDB if supported by the Neon project/plan; otherwise use standard Postgres indexes.
- Scheduler: Heroku Scheduler (cron-style triggers) for watcher and ETL jobs.
- Services:
  - Go (Gin) watcher: polls current feed and writes new measurements to DB.
  - Python cleaning service: outlier removal + imputation -> clean table.
  - Python ETL grid service: grid generation + Lanczos4 + nearest-fill -> Vercel Blob.
  - Go (Gin) REST API: sensor queries + latest grid link.
- Storage for grids: Vercel Blob (read/write token via env).
- Visualization: Flutter app (`flutter_map` with OSM tiles), contours overlay, and sensor charts.

## Database Choice
Chosen: PostgreSQL (NeonDB hosted).
- Pros: strong schema + constraints, relational integrity (sensors ↔ measurements), rich indexing, time-window queries, mature geospatial (`PostGIS`) if needed, optional TimescaleDB.
- Notes: If TimescaleDB is unavailable on NeonDB plan, proceed with regular Postgres and recommended indexes.

## PostgreSQL Schema (Recommended)
- `sensors`
  - `id` (PK, text)
  - `name` (text, nullable)
  - `provider_id` (text, nullable)
  - `lat` (double precision)
  - `lon` (double precision)
  - `elevation_m` (double precision, nullable)
  - `metadata` (jsonb, nullable)
  - Unique: (`id`)

- `raw_measurements`
  - `id` (bigserial PK)
  - `sensor_id` (text, FK -> sensors.id)
  - `ts` (timestamptz)
  - `value_mm` (double precision)
  - `source` (text, enum-like: 'historic' | 'current')
  - `ingested_at` (timestamptz default now())
  - Unique: (`sensor_id`, `ts`)
  - Indexes: (`ts`), (`sensor_id`, `ts` DESC)

- `clean_measurements`
  - `id` (bigserial PK)
  - `sensor_id` (text, FK -> sensors.id)
  - `ts` (timestamptz)
  - `value_mm` (double precision)
  - `qc_flags` (int, bitmask; 0=ok, 1=outlier, 2=imputed, etc.)
  - `imputation_method` (text, e.g., 'linear', 'ets', 'sarima', 'seasonal_median')
  - `version` (int, default 1)
  - Unique: (`sensor_id`, `ts`, `version`)
  - Indexes: (`ts`), (`sensor_id`, `ts` DESC)

- `grid_runs`
  - Represents hourly (or native) time slots and their grid processing status.
  - `id` (bigserial PK)
  - `ts` (timestamptz)
  - `res_m` (int)
  - `bbox` (jsonb [minx, miny, maxx, maxy] projected)
  - `crs` (text, e.g., 'EPSG:3857')
  - `blob_url_npz` (text, nullable)
  - `blob_url_png` (text, nullable)
  - `blob_url_contours` (text, nullable)
  - `status` (text enum: 'pending' | 'done' | 'failed')
  - `created_at` (timestamptz default now())
  - `updated_at` (timestamptz default now())
  - Unique: (`ts`, `res_m`)
  - Indexes: (`ts` DESC), (`status`)

Note: If we adopt PostGIS, `sensors` can carry `geom geometry(Point, 4326)` and `grid_runs` may include an `envelope` polygon.

## MongoDB Collections (Alternative)
- `sensors`: `{ _id, name?, provider_id?, lat, lon, elevation_m?, metadata? }`
- `raw_measurements`: `{ _id, sensor_id, ts (ISO), value_mm, source, ingested_at }` with unique index `{ sensor_id: 1, ts: 1 }`.
- `clean_measurements`: `{ _id, sensor_id, ts, value_mm, qc_flags, imputation_method, version }` with index `{ sensor_id: 1, ts: -1 }`.
- `grid_runs`: `{ _id, ts, res_m, bbox, crs, blob_url_npz?, blob_url_png?, blob_url_contours?, status, created_at, updated_at }` unique `{ ts: 1, res_m: 1 }`.

## Pipelines & Services

### Step 0 — Get the JSONs
- Verify reachability and content types.
- Record example payloads and map source fields → normalized schema.

### Step 1 — Database Design
- Finalize Postgres schema and create migrations.
- Decide on TimescaleDB usage and PostGIS (optional).

### Step 2 — Notebook: Normalize + Upload to DB
- Parse historic + current feeds, harmonize fields: `sensor_id, lat, lon, ts, value_mm, source`.
- No cleaning at this stage; only type coercion, timestamp to UTC, dedupe.
- Upsert `sensors`, insert into `raw_measurements` (conflict ignore on `(sensor_id, ts)`).
- Produce a short profiling summary (counts, coverage).

### Step 3 — API Watcher (Go/Gin) via Heroku Scheduler
- On schedule (e.g., every 5–10 minutes):
  - Fetch current feed; filter out any measurements older than last stored per sensor.
  - Upsert sensors; insert new rows into `raw_measurements`.
  - Idempotency: avoid duplicates via unique constraint.
  - Logging + metrics: counts ingested, last ts per sensor.
- Configuration via env: `CURRENT_URL`, `DATABASE_URL`, `POLL_WINDOW_MIN`.

### Step 4 — Notebook: Imputation Experiments
- EDA on gaps per sensor, coverage.
- Outlier rules: physical bounds (>=0), Hampel/IQR; flag but don’t drop until cleaning service.
- Imputation strategies:
  - Small gaps ≤ N steps: time-aware linear/spline.
  - Larger gaps: ETS/SARIMA; fallback seasonal median by hour-of-day/month.
- Backtesting with rolling-origin; choose thresholds and default model.

### Step 5 — Cleaning Service (Python)
- Reads `raw_measurements`, applies QC (outlier to NaN, flags), imputes per sensor.
- Writes to `clean_measurements` with `qc_flags` and `imputation_method`.
- Idempotent updates for new time windows only (e.g., last X days).
- Env: `DATABASE_URL`, cleaning params (thresholds), parallelism options.

### Step 6 — Notebook: Grid & Interpolation Validation
- Project to EPSG:3857; define bbox with padding, `res_m` (e.g., 500m).
- Seed grid from sensor points to nearest cell; tie-break by mean or IDW.
- Lanczos4 masked convolution (a=4), renormalize per neighborhood.
- Nearest-fill remaining NaNs using KDTree on seeded cells.
- Visual validation (raster, contours) and basic residual analysis.

### Step 7 — ETL Grid Service (Python)
- Scheduler: Heroku Scheduler hourly (or match native data cadence).
- Backfill: if first run, iterate all available hourly slots; else only `grid_runs.status='pending'`.
- For each timeslot:
  - Read `clean_measurements` for that hour; build grid; interpolate.
  - Save `.npz` (data, x, y, CRS, meta) to Vercel Blob for Python workflows.
  - Additionally publish a client-consumable `grid_{iso}.json.gz` with:
    `{ "data": float32 array (row-major, HxW, base64 or array), "x": [W], "y": [H], "crs": "EPSG:3857", "timestamp": "...", "bbox": [minx,miny,maxx,maxy], "res_m": 500 }`.
    - Rendering will be performed on the client using this JSON (preferred).
  - Optionally export `.png` raster for debugging; `contours.geojson` kept as an overlay artifact.
  - Update `grid_runs` with blob URLs and `status='done'`.
  - Maintain a `grids/latest.json` pointer in Blob: `{ timestamp, grid_url, bbox, res_m }`.
- Env: `DATABASE_URL`, `VERCEL_BLOB_RW_TOKEN`, `GRID_RES_M`, `BBOX_PADDING_M`, `TIME_INTERVAL_MIN`.

### Step 8 — REST API (Go + Gin)
- Endpoints:
  - `GET /sensor` — list sensors.
  - `GET /sensor/:sensor_id` — all measurements for `sensor_id` (raw or clean; default clean; `?clean=false` for raw).
  - `GET /sensor/:sensor_id?last_n=N` — last N measurements.
  - `GET /sensor/:sensor_id?last_n_days=D` — last D days.
  - `GET /now` — last measurement per sensor (from clean).
  - `GET /grid/latest` — returns only 200 and JSON body with `{"grid_url": "..."}`.
- Responses: JSON; pagination supported via `limit/offset` where applicable.
- Security: Public reads (no auth) as requested.

### Step 9 — Visualization (Flutter)
- Map via `flutter_map` with OpenStreetMap tiles (free).
- Layers:
  - Client-side rendering: fetch `grid_{timestamp}.json.gz`, decode grid floats, apply colormap in app, and display as image overlay with bounds in EPSG:4326.
  - Contours: fetch GeoJSON and draw polylines, styled by `level`.
  - Sensor pins: tap to show current value and a modal with time series chart (`fl_chart`).
- Data fetching:
  - Sensors and timeseries via REST API.
  - Latest grid via `/grid/latest` response.

## Algorithms
- Outlier detection: physical bounds (>=0), Hampel filter (k=3–7, t≈3σ), and/or IQR rule.
- Imputation:
  - Small gaps: linear/spline within max window.
  - Large gaps: ETS/SARIMA; fallback seasonal median by hour-of-day/month; clip to [0, cap].
- Grid & Interpolation:
  - Project to EPSG:3857; create grid with `res_m` spacing.
  - Lanczos4 kernel: separable 2D `L(x) = sinc(pi x) * sinc(pi x / a)` for `|x| < a`, `a=4`; mask-aware convolution and renormalization.
  - Nearest-fill: KDTree nearest seeded cell for remaining NaNs.
  - Optional smoothing pass with small Gaussian if needed.

## Blob Artifacts & Schemas
- `grids/grid_{iso}.npz` — keys: `data: float32[H,W]`, `x: float64[W]`, `y: float64[H]`, `crs: 'EPSG:3857'`, `timestamp`, `bbox`, `res_m` (for Python).
- `grids/grid_{iso}.json.gz` — client payload for Flutter (public): same fields but with `data` as a float array (compressed) or base64-encoded binary; x/y as arrays.
- `grids/latest.json` — `{ "timestamp": "...", "grid_url": "...", "bbox": [minx,miny,maxx,maxy], "res_m": 500 }` (public).
- `contours/contours_{iso}.geojson` — MultiLineString features with `level` property (public).
- `sensors/{sensor_id}.parquet|jsonl` (optional) — time series export for offline consumption.

## Configuration & Secrets
- `DATABASE_URL` — NeonDB Postgres DSN (ensure TLS/`sslmode=require`).
- `HISTORIC_URL`, `CURRENT_URL` — source endpoints.
- `VERCEL_BLOB_RW_TOKEN` — write token for Vercel Blob.
- `GRID_RES_M`, `BBOX_PADDING_M`, `TIME_INTERVAL_MIN`, `MAX_GAP_SIMPLE`, `MODEL_TYPE` — algorithmic params.
- In local dev, use `.env` and `dotenv` loaders for Python/Go as appropriate.

## Deployment & Scheduling
- Heroku apps:
  - Watcher (Go): scheduled every 5–10 minutes.
  - Cleaning (Python): scheduled hourly (or on a short cadence focused on recent data).
  - Grid ETL (Python): scheduled hourly; backfills pending `grid_runs`.
  - REST API (Go): always-on dyno.
- Logging + retention: stdout aggregated; optional Sentry/OTEL.
- Blob access: public read for artifacts (Vercel Blob public bucket/URLs).

## Testing & Acceptance Criteria
- Unit tests: outlier filters, imputation selection, mask-aware Lanczos, nearest-fill, CRS transforms.
- Integration tests: watcher ingests without duplicates; cleaning writes expected flags; ETL creates artifacts and updates `grid_runs`.
- API tests: endpoint contracts, pagination, error paths.
- Acceptance per step:
  - Step 2: DB contains normalized historic/current data, deduped.
  - Step 5: Clean table populated with QC flags; imputation metrics within targets.
  - Step 7: Blob has grid npz/png + latest.json; `grid_runs` marked done.
  - Step 8: REST endpoints return expected payloads; `/grid/latest` returns 200 with `grid_url`.
  - Step 9: Flutter shows map overlay, contours, and per-sensor charts.

## Open Questions
- Confirm PostgreSQL vs MongoDB; is TimescaleDB acceptable?
- Target grid resolution (default 500 m) and time interval (default 1 hour).
- Public vs private Blob access for the Flutter app.
- Do we pre-render grid PNG on server or render colormap in-app?
- Do API reads require auth or remain public?

## Milestones (Gated)
- 0) Get JSONs (validate payloads)
- 1) Database design (schemas/migrations)
- 2) Notebook: normalize + load to DB
- 3) Watcher (Go) + scheduler
- 4) Notebook: imputation experiments
- 5) Cleaning service (Python)
- 6) Notebook: grid & interpolation validation
- 7) ETL grid service (Python)
- 8) REST API (Go + Gin)
- 9) Flutter visualization
