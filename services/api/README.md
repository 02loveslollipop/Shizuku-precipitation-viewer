# REST API

Go (Gin) service exposing precipitation metadata and measurements.

## Endpoints

- `GET /healthz` – readiness probe.
- `GET /sensor` – list sensors.
- `GET /sensor/:sensor_id` – fetch measurements with optional filters:
  - `clean` (bool, default `true`)
  - `last_n` (int)
  - `last_n_days` (int)
  - `start`, `end` (RFC3339 timestamps)
- `GET /now` – latest clean measurement per sensor.
- `GET /grid/latest` – returns JSON `{"grid_url": "..."}` pointing to the Vercel blob.

If `API_BEARER_TOKEN` is set, all endpoints require `Authorization: Bearer <token>`.

## Configuration

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL DSN (sslmode=require). |
| `VERCEL_BLOB_BASE_URL` | Base URL of the blob storage (e.g. `https://...vercel-storage.com`). |
| `GRID_LATEST_PATH` | Path to the latest pointer file (default `grids/latest.json`). |
| `API_BEARER_TOKEN` | Optional bearer token for all endpoints. |
| `API_PORT` | Port to listen on (default 8080). |
| `API_DEFAULT_LIMIT` | Default `last_n` limit (default 200). |
| `API_DEFAULT_DAYS` | Default lookback when `last_n_days` omitted (default 7). |

## Running locally

```bash
go run ./services/api
```

Ensure Go 1.21+ is available and env vars are set.
