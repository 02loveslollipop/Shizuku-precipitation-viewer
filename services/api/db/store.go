package db

import (
	"context"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"
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
