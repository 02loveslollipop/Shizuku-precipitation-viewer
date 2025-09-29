# Grid ETL Service

Python cron job that fetches cleaned precipitation snapshots, converts them into a gridded field using Lanczos-4 interpolation, uploads artifacts to Vercel Blob, and records progress in `grid_runs`.

## Responsibilities
- Discover pending grid slots (hourly by default) by cross-referencing `clean_measurements` with `grid_runs`.
- Build a Web Mercator grid (default 500 m resolution) with Lanczos-4 interpolation and nearest-neighbour fill.
- Upload artifacts to Vercel Blob storage: `.npz` (numerical grid), `.json.gz` (client payload), and `contours.geojson` (vector lines), plus update `grids/latest.json` pointer.
- Update `grid_runs` status (`pending` → `done` / `failed`) with blob URLs and bbox metadata.

## Environment variables
| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | ✅ | — | PostgreSQL connection string (`sslmode=require`). |
| `VERCEL_BLOB_RW_TOKEN` | ✅ | — | Read/write token generated in Vercel (keep secret). |
| `VERCEL_BLOB_BASE_URL` | ✅ | — | Public base URL for blobs (e.g. `https://*.vercel-storage.com`). |
| `GRID_INTERVAL_MIN` | ❌ | `60` | Width of each snapshot window in minutes. |
| `GRID_RESOLUTION_M` | ❌ | `500` | Grid spacing in metres. |
| `GRID_PADDING_M` | ❌ | `2000` | Extra padding around sensor bounds (metres). |
| `ETL_MAX_SLOTS` | ❌ | `3` | Maximum slots processed per run. |
| `ETL_BACKFILL_HOURS` | ❌ | `48` | How far back to auto-enqueue missing slots. |
| `DRY_RUN` | ❌ | `false` | When true, skip uploads and just mark success with `dry-run` message. |

## Running locally
```bash
conda activate <env>
export DATABASE_URL=postgres://...
export VERCEL_BLOB_RW_TOKEN=vercel_blob_rw_...
export VERCEL_BLOB_BASE_URL=https://<id>.public.blob.vercel-storage.com
python -m services.etl.main
```

## Heroku Scheduler
1. Ensure the repo is deployed with the Python buildpack (`heroku/python`).
2. Set the config vars listed above (plus `PYTHONPATH=.` if needed).
3. Add a Scheduler job with command:
   ```bash
   python -m services.etl.main
   ```
   Choose the cadence (hourly recommended after watchers/cleaners run).

## Outputs
- `grids/<timestamp>/grid.npz`
- `grids/<timestamp>/grid.json.gz`
- `grids/<timestamp>/contours.geojson`
- `grids/latest.json` pointer

Client applications can fetch `grids/latest.json` to discover the freshest grid URLs.
