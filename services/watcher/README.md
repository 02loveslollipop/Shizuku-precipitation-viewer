# Watcher Service (Current Feed Ingest)

Cron-friendly Go program that polls the SIATA current precipitation feed and writes new measurements into the `raw_measurements` table.

## Responsibilities
- Fetch `https://siata.gov.co/data/siata_app/Pluviometrica.json` (override with `CURRENT_URL`).
- Upsert station metadata into `sensors`.
- Insert a new `raw_measurements` row per station when the latest value differs from the previous stored value or the previous entry is older than a configurable interval.
- Skip inserts for sentinel values (`-999`).

## Environment variables
| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | ✅ | — | NeonDB PostgreSQL connection string (`sslmode=require`). |
| `CURRENT_URL` | ❌ | `https://siata.gov.co/data/siata_app/Pluviometrica.json` | JSON endpoint for current stations. |
| `WATCHER_MIN_INTERVAL` | ❌ | `5m` | Minimum duration between stored readings before forcing an insert even if the value is unchanged. |
| `WATCHER_REQUEST_TIMEOUT` | ❌ | `30s` | HTTP request timeout. |
| `WATCHER_VALUE_EPSILON` | ❌ | `0.01` | Tolerance when comparing current vs previous values (mm). |
| `DRY_RUN` | ❌ | `false` | When `true`, log intended operations without writing to the DB. |

Values are loaded via environment; `.env` in the repository root is read automatically for local execution.

## Running locally
```bash
cd services/watcher
# ensure Go toolchain is available, then
export DATABASE_URL=postgres://...
go run ./...
```

## Heroku Scheduler
### One-time setup
1. Create the app with the Go buildpack:
   ```bash
   heroku create <app-name> --buildpack heroku/go
   ```
2. Configure the build target and environment:
   ```bash
   heroku config:set \
     GO_INSTALL_PACKAGE_SPEC=./services/watcher \
     DATABASE_URL="postgres://..." \
     WATCHER_MIN_INTERVAL=5m \
     WATCHER_REQUEST_TIMEOUT=30s \
     WATCHER_VALUE_EPSILON=0.01
   ```
   (Set `DRY_RUN=true` for smoke testing.)
3. Deploy from the repository root:
   ```bash
   git push heroku main
   ```

### Scheduler job
Add a job via the Heroku Scheduler dashboard running:
```bash
bin/watcher
```
Choose an interval (e.g., every 10 minutes). The buildpack installs the binary at `bin/watcher` thanks to the `GO_INSTALL_PACKAGE_SPEC` setting.

### Manual execution
To trigger an ad-hoc run:
```bash
heroku run bin/watcher
```

## Exit codes
- `0`: success or nothing to insert
- non-zero: fatal error (suitable for alerting)

Logs include the number of stations fetched and inserted.
