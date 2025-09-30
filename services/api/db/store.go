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
    FROM sensors
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
    FROM clean_measurements
    WHERE sensor_id = $1
`

const rawMeasurementsBase = `
    SELECT sensor_id, ts, value_mm, NULL::integer AS qc_flags, NULL::text AS imputation_method, quality, source
    FROM raw_measurements
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
    FROM latest_clean_measurements
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
	GridNPZURL  *string   `json:"grid_npz_url,omitempty"`
	ContoursURL *string   `json:"contours_url,omitempty"`
	Status      string    `json:"status"`
	ErrorMsg    *string   `json:"error_msg,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

const availableGridsSQL = `
    SELECT timestamp
    FROM grids
    WHERE status = 'done'
    ORDER BY timestamp DESC
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
    SELECT id, timestamp, resolution, bounds, srid, grid_url, grid_npz_url, contours_url, status, error_msg, created_at, updated_at
    FROM grids
    WHERE timestamp = $1 AND status = 'done'
    LIMIT 1
`

// GetGridByTimestamp returns grid information for a specific timestamp.
func (s *Store) GetGridByTimestamp(ctx context.Context, timestamp time.Time) (*GridInfo, error) {
	row := s.pool.QueryRow(ctx, gridByTimestampSQL, timestamp)
	
	var g GridInfo
	var boundsJSON []byte
	if err := row.Scan(
		&g.ID,
		&g.Timestamp,
		&g.Resolution,
		&boundsJSON,
		&g.SRID,
		&g.GridURL,
		&g.GridNPZURL,
		&g.ContoursURL,
		&g.Status,
		&g.ErrorMsg,
		&g.CreatedAt,
		&g.UpdatedAt,
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
