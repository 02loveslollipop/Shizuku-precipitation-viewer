package db

import (
	"context"
	"encoding/json"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Store wraps database access helpers.
type Store struct {
	pool *pgxpool.Pool
}

// New creates a Store backed by a pgx pool.
func New(ctx context.Context, databaseURL string) (*Store, error) {
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, err
	}
	return &Store{pool: pool}, nil
}

// Close releases the pool resources.
func (s *Store) Close() {
	if s.pool != nil {
		s.pool.Close()
	}
}

// Sensor represents a sensor metadata record.
type Sensor struct {
	ID         string    `json:"id"`
	Name       *string   `json:"name,omitempty"`
	ProviderID *string   `json:"provider_id,omitempty"`
	Lat        float64   `json:"lat"`
	Lon        float64   `json:"lon"`
	City       *string   `json:"city,omitempty"`
	Subbasin   *string   `json:"subbasin,omitempty"`
	Barrio     *string   `json:"barrio,omitempty"`
	Metadata   []byte    `json:"metadata,omitempty"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

const listSensorsSQL = `
    SELECT id, name, provider_id, lat, lon, city, subbasin, barrio, metadata, created_at, updated_at
    FROM shizuku.sensors
    ORDER BY id
`

// ListSensors returns all sensor metadata.
func (s *Store) ListSensors(ctx context.Context) ([]Sensor, error) {
	rows, err := s.pool.Query(ctx, listSensorsSQL)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	sensors := make([]Sensor, 0)
	for rows.Next() {
		var sensor Sensor
		if err := rows.Scan(
			&sensor.ID,
			&sensor.Name,
			&sensor.ProviderID,
			&sensor.Lat,
			&sensor.Lon,
			&sensor.City,
			&sensor.Subbasin,
			&sensor.Barrio,
			&sensor.Metadata,
			&sensor.CreatedAt,
			&sensor.UpdatedAt,
		); err != nil {
			return nil, err
		}
		sensors = append(sensors, sensor)
	}
	return sensors, rows.Err()
}

// Measurement represents either a clean or raw measurement.
type Measurement struct {
	SensorID         string    `json:"sensor_id"`
	Timestamp        time.Time `json:"ts"`
	ValueMM          float64   `json:"value_mm"`
	QCFlags          *int32    `json:"qc_flags,omitempty"`
	ImputationMethod *string   `json:"imputation_method,omitempty"`
	Quality          *float64  `json:"quality,omitempty"`
	Source           *string   `json:"source,omitempty"`
}

// MeasurementQuery holds filters for retrieving measurements.
type MeasurementQuery struct {
	SensorID string
	UseClean bool
	Limit    int
	Since    *time.Time
	Until    *time.Time
}

const cleanMeasurementsBase = `
    SELECT sensor_id, ts, value_mm, qc_flags, imputation_method, NULL::double precision AS quality, NULL::text AS source
    FROM shizuku.clean_measurements
    WHERE sensor_id = $1
`

const rawMeasurementsBase = `
    SELECT sensor_id, ts, value_mm, NULL::integer AS qc_flags, NULL::text AS imputation_method, quality, source
    FROM shizuku.raw_measurements
    WHERE sensor_id = $1
`

// FetchMeasurements returns measurements for a sensor based on the query.
func (s *Store) FetchMeasurements(ctx context.Context, q MeasurementQuery) ([]Measurement, error) {
	base := cleanMeasurementsBase
	if !q.UseClean {
		base = rawMeasurementsBase
	}

	args := []any{q.SensorID}
	clause := ""
	argPos := 2
	if q.Since != nil {
		clause += " AND ts >= $" + strconv.Itoa(argPos)
		args = append(args, *q.Since)
		argPos++
	}
	if q.Until != nil {
		clause += " AND ts <= $" + strconv.Itoa(argPos)
		args = append(args, *q.Until)
		argPos++
	}
	order := " ORDER BY ts"
	limit := ""
	if q.Limit > 0 {
		limit = " LIMIT $" + strconv.Itoa(argPos)
		args = append(args, q.Limit)
	}

	sql := base + clause + order + limit

	rows, err := s.pool.Query(ctx, sql, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	measurements := make([]Measurement, 0)
	for rows.Next() {
		var m Measurement
		if err := rows.Scan(
			&m.SensorID,
			&m.Timestamp,
			&m.ValueMM,
			&m.QCFlags,
			&m.ImputationMethod,
			&m.Quality,
			&m.Source,
		); err != nil {
			return nil, err
		}
		measurements = append(measurements, m)
	}
	return measurements, rows.Err()
}

const latestCleanSQL = `
    SELECT sensor_id, ts, value_mm, qc_flags, imputation_method
    FROM shizuku.latest_clean_measurements
`

// LatestClean returns the latest clean measurement per sensor.
func (s *Store) LatestClean(ctx context.Context) ([]Measurement, error) {
	rows, err := s.pool.Query(ctx, latestCleanSQL)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	data := make([]Measurement, 0)
	for rows.Next() {
		var m Measurement
		if err := rows.Scan(&m.SensorID, &m.Timestamp, &m.ValueMM, &m.QCFlags, &m.ImputationMethod); err != nil {
			return nil, err
		}
		data = append(data, m)
	}
	return data, rows.Err()
}

// GridInfo represents grid metadata from the database.
type GridInfo struct {
	ID          int       `json:"id"`
	Timestamp   time.Time `json:"timestamp"`
	Resolution  int       `json:"resolution"`
	Bounds      []float64 `json:"bounds,omitempty"`
	SRID        string    `json:"srid"`
	GridURL     *string   `json:"grid_url,omitempty"`
	ContoursURL *string   `json:"contours_url,omitempty"`
	Status      string    `json:"status"`
	ErrorMsg    *string   `json:"error_msg,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

const availableGridsSQL = `
	SELECT ts
	FROM shizuku.grid_runs
	WHERE status = 'done'
	ORDER BY ts ASC
`

// GetAvailableGridTimestamps returns timestamps of all completed grids.
func (s *Store) GetAvailableGridTimestamps(ctx context.Context) ([]time.Time, error) {
	rows, err := s.pool.Query(ctx, availableGridsSQL)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	timestamps := make([]time.Time, 0)
	for rows.Next() {
		var ts time.Time
		if err := rows.Scan(&ts); err != nil {
			return nil, err
		}
		timestamps = append(timestamps, ts)
	}
	return timestamps, rows.Err()
}

const gridByTimestampSQL = `
    SELECT id, ts, res_m, bbox, crs, blob_url_json, blob_url_contours, status, message, created_at, updated_at
    FROM shizuku.grid_runs
    WHERE ts = $1 AND status = 'done'
    LIMIT 1
`

// GetGridByTimestamp returns grid information for a specific timestamp.
func (s *Store) GetGridByTimestamp(ctx context.Context, timestamp time.Time) (*GridInfo, error) {
	row := s.pool.QueryRow(ctx, gridByTimestampSQL, timestamp)

	var g GridInfo
	var boundsJSON []byte
	if err := row.Scan(
		&g.ID,
		&g.Timestamp,   // ts
		&g.Resolution,  // res_m
		&boundsJSON,    // bbox
		&g.SRID,        // crs
		&g.GridURL,     // blob_url_json
		&g.ContoursURL, // blob_url_contours
		&g.Status,      // status
		&g.ErrorMsg,    // message
		&g.CreatedAt,   // created_at
		&g.UpdatedAt,   // updated_at
	); err != nil {
		return nil, err
	}

	// Parse bounds JSON array if present
	if len(boundsJSON) > 0 {
		// Bounds is stored as JSON array like [-8533035.968636995, 604561.383004428, -8307053.104129183, 973544.8517950282]
		// We need to parse this JSON array
		if err := json.Unmarshal(boundsJSON, &g.Bounds); err == nil {
			// Successfully parsed bounds
		}
	}

	return &g, nil
}

// SensorSnapshot represents a sensor with an optional measurement at or before
// the requested timestamp.
type SensorSnapshot struct {
	ID         string  `json:"id"`
	Name       *string `json:"name,omitempty"`
	ProviderID *string `json:"provider_id,omitempty"`
	Lat        float64 `json:"lat"`
	Lon        float64 `json:"lon"`
	City       *string `json:"city,omitempty"`

	// Measurement fields (may be nil if no measurement exists <= requested ts)
	Ts         *time.Time `json:"ts,omitempty"`
	ValueMM    *float64   `json:"value_mm,omitempty"`
	QCFlags    *int32     `json:"qc_flags,omitempty"`
	Imputation *string    `json:"imputation_method,omitempty"`
	Quality    *float64   `json:"quality,omitempty"`
	Source     *string    `json:"source,omitempty"`
}

// SnapshotAtTimestamp returns one row per sensor with the latest measurement
// at-or-before the given timestamp. If useClean is true the query reads from
// clean_measurements; otherwise it reads raw_measurements. Measurement fields
// are nullable when no measurement exists.
func (s *Store) SnapshotAtTimestamp(ctx context.Context, ts time.Time, useClean bool) ([]SensorSnapshot, error) {
	// Build lateral subquery depending on clean/raw
	var sub string
	if useClean {
		// clean measurements don't have quality/source in schema; return NULLs for those
		sub = `(
			SELECT sensor_id, ts, value_mm, qc_flags, imputation_method, NULL::double precision AS quality, NULL::text AS source
			FROM shizuku.clean_measurements
			WHERE sensor_id = sensors.id AND ts <= $1
			ORDER BY ts DESC
			LIMIT 1
		)`
	} else {
		sub = `(
			SELECT sensor_id, ts, value_mm, NULL::integer AS qc_flags, NULL::text AS imputation_method, quality, source
			FROM shizuku.raw_measurements
			WHERE sensor_id = sensors.id AND ts <= $1
			ORDER BY ts DESC
			LIMIT 1
		)`
	}

	sql := `SELECT sensors.id, sensors.name, sensors.provider_id, sensors.lat, sensors.lon, sensors.city,
		m.ts, m.value_mm, m.qc_flags, m.imputation_method, m.quality, m.source
		FROM shizuku.sensors
		LEFT JOIN LATERAL ` + sub + ` m ON true
		ORDER BY sensors.id`

	rows, err := s.pool.Query(ctx, sql, ts)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := make([]SensorSnapshot, 0)
	for rows.Next() {
		var rec SensorSnapshot
		var mTs *time.Time
		var mValue *float64
		var mQc *int32
		var mImp *string
		var mQuality *float64
		var mSource *string

		if err := rows.Scan(
			&rec.ID,
			&rec.Name,
			&rec.ProviderID,
			&rec.Lat,
			&rec.Lon,
			&rec.City,
			&mTs,
			&mValue,
			&mQc,
			&mImp,
			&mQuality,
			&mSource,
		); err != nil {
			return nil, err
		}

		rec.Ts = mTs
		rec.ValueMM = mValue
		rec.QCFlags = mQc
		rec.Imputation = mImp
		rec.Quality = mQuality
		rec.Source = mSource

		out = append(out, rec)
	}

	return out, rows.Err()
}

// AveragesResult holds average precipitation values for different windows.
type AveragesResult struct {
	Avg3h  *float64 `json:"3h,omitempty"`
	Avg6h  *float64 `json:"6h,omitempty"`
	Avg12h *float64 `json:"12h,omitempty"`
	Avg24h *float64 `json:"24h,omitempty"`
}

const averagesSQL = `
SELECT
  (SELECT AVG(value_mm) FROM shizuku.clean_measurements WHERE ts >= now() - interval '3 hours') AS avg_3h,
  (SELECT AVG(value_mm) FROM shizuku.clean_measurements WHERE ts >= now() - interval '6 hours') AS avg_6h,
  (SELECT AVG(value_mm) FROM shizuku.clean_measurements WHERE ts >= now() - interval '12 hours') AS avg_12h,
  (SELECT AVG(value_mm) FROM shizuku.clean_measurements WHERE ts >= now() - interval '24 hours') AS avg_24h
`

// GetAverages computes average precipitation (value_mm) across all sensors
// for the last 3, 6, 12 and 24 hours. Null averages are possible when no
// measurements exist in the given window.
func (s *Store) GetAverages(ctx context.Context) (*AveragesResult, error) {
	row := s.pool.QueryRow(ctx, averagesSQL)
	var a3, a6, a12, a24 *float64
	if err := row.Scan(&a3, &a6, &a12, &a24); err != nil {
		return nil, err
	}
	return &AveragesResult{
		Avg3h:  a3,
		Avg6h:  a6,
		Avg12h: a12,
		Avg24h: a24,
	}, nil
}
