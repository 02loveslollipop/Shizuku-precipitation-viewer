# Cleaning Service

Python cron job that reads raw precipitation measurements, applies quality control and imputation, and writes canonical rows to `clean_measurements`.

## Responsibilities
- Pull recent `raw_measurements` (default last 72 hours) that have not yet been cleaned.
- Flag and drop outliers outside configurable bounds (min/max mm) or below a quality threshold.
- Impute gaps primarily via gradient-boosted forecasting (HistGradientBoostingRegressor) with temporal features, falling back to interpolation and medians.
- Persist results into `clean_measurements` with QC flags and imputation metadata.

## Environment variables
| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | ✅ | — | PostgreSQL DSN. |
| `CLEANER_LOOKBACK_HOURS` | ❌ | `72` | Time window (hours) of raw data to consider. |
| `CLEANER_MIN_VALUE_MM` | ❌ | `0.0` | Lower bound for precipitation (values below flagged as outliers). |
| `CLEANER_MAX_VALUE_MM` | ❌ | `150.0` | Upper bound for precipitation (values above flagged as outliers). |
| `CLEANER_MIN_QUALITY` | ❌ | — | Minimum accepted `quality` (if provided). Entries below are flagged and treated as missing. |
| `CLEANER_INTERPOLATION_LIMIT` | ❌ | `6` | Maximum consecutive missing points (in samples) to interpolate when forecasting fails. |
| `CLEANER_GBM_ENABLED` | ❌ | `true` | Disable to skip forecasting (falls back to interpolation/medians). |
| `CLEANER_GBM_MAX_DEPTH` | ❌ | `3` | Tree depth for `HistGradientBoostingRegressor`. |
| `CLEANER_GBM_LEARNING_RATE` | ❌ | `0.1` | Learning rate for the GBM forecaster. |
| `CLEANER_GBM_MIN_TRAIN` | ❌ | `48` | Minimum training samples required to fit the forecaster. |
| `CLEANER_GBM_MAX_ITERS` | ❌ | `10` | Max forecasting refinement passes over missing values. |
| `CLEANER_GBM_RANDOM_STATE` | ❌ | — | Optional seed for deterministic forecasts. |
| `DRY_RUN` | ❌ | `false` | When `true`, compute cleaned rows but skip writing to the DB. |

## Running locally
```bash
conda activate <env>  # ensure requirements.txt installed
export DATABASE_URL=postgres://...
python -m services.cleaner.main
```

## Heroku Scheduler
1. Ensure the repo is deployed (Python buildpack auto-detected or add `heroku/python`).
2. Set config vars listed above, plus `PYTHONPATH=.` if needed.
3. Add a Scheduler job with command:
   ```bash
   python -m services.cleaner.main
   ```
   Choose cadence (e.g., hourly).

## QC flags
- `1` (`OUTLIER_FLAG`): Value outside configured min/max bounds.
- `2` (`IMPUTED_FLAG`): Value was imputed.
- `4` (`POOR_QUALITY_FLAG`): Value had a quality score below threshold and was replaced.

The `imputation_method` column records the fill strategy: `gbm_forecast`, `time_interp`, `hour_median`, or `global_median`.
