# Data Archiver Service

Automated service for archiving old measurements and cleaning up the database.

## Purpose

The archiver service manages data lifecycle by:

1. **Deleting old raw measurements** - Removes raw measurements older than 24 hours (configurable)
2. **Archiving clean measurements** - Exports clean measurements older than 30 days (configurable) to blob storage
3. **Cleaning up database** - Deletes archived measurements from the database to save space

## Archive Format

Archives are stored as gzipped JSON files with the following structure:

```json
{
  "day": "2025-01-15",
  "data": [
    {
      "sensor": "sensor_id_1",
      "measurements": [
        {
          "time": "2025-01-15T00:00:00Z",
          "measurement": 5.2,
          "qc_flags": 0,
          "imputation_method": null
        },
        {
          "time": "2025-01-15T00:10:00Z",
          "measurement": 5.8,
          "qc_flags": 0,
          "imputation_method": "ARIMA"
        }
      ]
    },
    {
      "sensor": "sensor_id_2",
      "measurements": [...]
    }
  ]
}
```

### Archive Storage Structure

Archives are organized by year and month:

```
archives/
  └── 2025/
      ├── 01/
      │   ├── archive-2025-01-01.json.gz
      │   ├── archive-2025-01-02.json.gz
      │   └── ...
      ├── 02/
      │   └── ...
      └── ...
```

## Configuration

Set the following environment variables:

### Required

- `DATABASE_URL` - PostgreSQL connection string
- `VERCEL_BLOB_RW_TOKEN` - Vercel Blob storage token
- `VERCEL_BLOB_BASE_URL` - Blob storage base URL

### Optional

- `ARCHIVER_RAW_RETENTION_DAYS` - Days to keep raw measurements (default: 1)
- `ARCHIVER_CLEAN_RETENTION_DAYS` - Days before archiving clean measurements (default: 30)
- `ARCHIVER_BATCH_SIZE` - Number of records to process at once (default: 1000)
- `ARCHIVER_DRY_RUN` - If "true", don't delete or upload (default: false)

## Usage

### Run Manually

```bash
cd services/archiver
python -m archiver.main
```

### Run as Scheduled Task

The service is designed to run once per day. Use cron, systemd timer, or a task scheduler:

#### Cron Example

```cron
# Run daily at 2 AM
0 2 * * * cd /path/to/project && python -m services.archiver.main >> /var/log/archiver.log 2>&1
```

#### Docker Example

```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY services/archiver /app/archiver
COPY .env /app/.env

CMD ["python", "-m", "archiver.main"]
```

Then use a scheduler like Kubernetes CronJob:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: data-archiver
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: archiver
            image: your-registry/archiver:latest
            envFrom:
            - secretRef:
                name: archiver-secrets
          restartPolicy: OnFailure
```

### Test with Dry Run

Test the archiver without making changes:

```bash
export ARCHIVER_DRY_RUN=true
python -m archiver.main
```

## Output

The service logs statistics for each run:

```
================================================================================
Starting Data Archiver Service
Run time: 2025-01-15T02:00:00.000000
================================================================================
Configuration:
  Raw retention: 1 days
  Clean retention: 30 days
  Batch size: 1000
  Dry run: False
Step 1: Deleting old raw measurements...
Deleted 125432 raw measurements older than 2025-01-14T02:00:00
Step 2: Archiving old clean measurements...
Found 89234 clean measurements to archive
Archiving measurements from 2024-12-01 to 2024-12-16
Created archive for 2024-12-01: https://...blob.vercel-storage.com/archives/2024/12/archive-2024-12-01.json.gz
Created archive for 2024-12-02: https://...blob.vercel-storage.com/archives/2024/12/archive-2024-12-02.json.gz
...
Step 3: Deleting archived measurements from database...
Deleted 89234 archived clean measurements
================================================================================
Archiver Service Complete
Statistics:
  Raw measurements deleted: 125432
  Clean measurements archived: 89234
  Clean measurements deleted: 89234
  Archive files created: 16
================================================================================
```

## Error Handling

- If blob upload fails for a day, the service continues with other days
- Database operations are atomic - if deletion fails, data is not lost
- All errors are logged with stack traces
- Service returns exit code 1 on fatal errors

## Monitoring

Monitor the service by:

1. **Exit code** - 0 for success, 1 for failure
2. **Log output** - Check for ERROR level messages
3. **Statistics** - Track counts over time to detect anomalies
4. **Database size** - Monitor database growth to ensure archiving is working

## Recovery

If the service fails:

1. **Check logs** for specific error messages
2. **Verify credentials** - Ensure DATABASE_URL and blob tokens are valid
3. **Check connectivity** - Ensure database and blob storage are accessible
4. **Run in dry-run mode** to test without side effects
5. **Re-run** - The service is idempotent and safe to re-run

## Performance

- Processes measurements in batches (default 1000 records)
- Groups by day before uploading to minimize blob operations
- Uses database indexes on `ts` column for efficient queries
- Typical processing time: ~5-10 minutes for 100k records

## Dependencies

- `psycopg2-binary` - PostgreSQL adapter
- `vercel_blob` - Blob storage client
- `python-dotenv` - Environment variable loading

Install with:

```bash
pip install psycopg2-binary vercel_blob python-dotenv
```

## Architecture

```
┌─────────────────┐
│   main.py       │  Entry point
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  archiver.py    │  Main service logic
└────┬────────────┘
     │
     ├──► db.py              Database operations
     ├──► archive_builder.py  JSON generation
     └──► uploader.py         Blob storage upload
```

## Future Enhancements

- [ ] Add archive metadata table to track what was archived
- [ ] Support multiple blob storage backends (S3, Azure, etc.)
- [ ] Add archive retrieval/restore functionality
- [ ] Implement archive compression levels
- [ ] Add metrics export (Prometheus, etc.)
- [ ] Support incremental archiving (archive as data ages)
