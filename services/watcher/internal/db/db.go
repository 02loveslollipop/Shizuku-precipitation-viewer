package db

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/02loveslollipop/Shizuku-precipitation-viewer/services/watcher/internal/models"
)

// UpsertSensors inserts/updates sensor metadata records.
func UpsertSensors(ctx context.Context, pool *pgxpool.Pool, sensors []models.SensorRow) error {
	if len(sensors) == 0 {
		return nil
	}

	batch := &pgx.Batch{}
	query := `INSERT INTO shizuku.sensors (id, name, provider_id, lat, lon, elevation_m, city, subbasin, barrio, metadata, created_at, updated_at)
VALUES ($1,$2,$3,$4,$5,NULL,$6,$7,$8,$9,NOW(),NOW())
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    provider_id = EXCLUDED.provider_id,
    lat = EXCLUDED.lat,
    lon = EXCLUDED.lon,
    city = EXCLUDED.city,
    subbasin = EXCLUDED.subbasin,
    barrio = EXCLUDED.barrio,
    metadata = EXCLUDED.metadata,
    updated_at = NOW()`

	for _, s := range sensors {
		batch.Queue(query, s.ID, s.Name, s.ProviderID, s.Lat, s.Lon, s.City, s.Subbasin, s.Barrio, s.Metadata)
	}

	res := pool.SendBatch(ctx, batch)
	defer res.Close()

	for range sensors {
		if _, err := res.Exec(); err != nil {
			return err
		}
	}

	return nil
}

// FetchLastMeasurements loads the most recent stored values per sensor.
func FetchLastMeasurements(ctx context.Context, pool *pgxpool.Pool, sensorIDs []string) (map[string]models.LastMeasurement, error) {
	result := make(map[string]models.LastMeasurement, len(sensorIDs))
	if len(sensorIDs) == 0 {
		return result, nil
	}

	rows, err := pool.Query(ctx, `
SELECT DISTINCT ON (sensor_id) sensor_id, value_mm, ts
FROM shizuku.raw_measurements
WHERE sensor_id = ANY($1) AND source = 'current'
ORDER BY sensor_id, ts DESC`, sensorIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var sensorID string
		var value *float64
		var ts time.Time
		if err := rows.Scan(&sensorID, &value, &ts); err != nil {
			return nil, err
		}
		result[sensorID] = models.LastMeasurement{Value: value, TS: ts}
	}

	return result, rows.Err()
}

// InsertMeasurements writes new measurement entries to raw_measurements.
func InsertMeasurements(ctx context.Context, pool *pgxpool.Pool, measurements []models.MeasurementCandidate) error {
	if len(measurements) == 0 {
		return nil
	}

	batch := &pgx.Batch{}
	query := `INSERT INTO shizuku.raw_measurements (sensor_id, ts, value_mm, quality, variable, source, ingested_at, created_at, updated_at)
VALUES ($1,$2,$3,NULL,'precipitacion','current',NOW(),NOW(),NOW())
ON CONFLICT (sensor_id, ts, source) DO UPDATE
SET value_mm = EXCLUDED.value_mm,
    updated_at = NOW()`

	for _, m := range measurements {
		batch.Queue(query, m.SensorID, m.TS, m.Value)
	}

	res := pool.SendBatch(ctx, batch)
	defer res.Close()

	for range measurements {
		if _, err := res.Exec(); err != nil {
			return err
		}
	}

	return nil
}
