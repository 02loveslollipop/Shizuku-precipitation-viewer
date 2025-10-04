package db

import (
	"context"
	"encoding/json"
	"strconv"
	"strings"
	"time"
)

type GridTimestampResult struct {
	ID             int       `json:"id"`
	Timestamp      time.Time `json:"timestamp"`
	Resolution     int       `json:"resolution"`
	Status         string    `json:"status"`
	GridJSONURL    *string   `json:"grid_json_url,omitempty"`
	ContoursURL    *string   `json:"contours_url,omitempty"`
	SensorCount    int       `json:"sensor_count"`
	AvgRainfallMmH *float64  `json:"avg_rainfall_mm_h,omitempty"`
	MaxRainfallMmH *float64  `json:"max_rainfall_mm_h,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
}

type GridTimestampsPage struct {
	Grids      []GridTimestampResult `json:"grids"`
	TotalCount int                   `json:"total_count"`
}

func (s *Store) ListGridTimestampsWithAggregates(ctx context.Context, limit, offset int, startTime, endTime *time.Time) (*GridTimestampsPage, error) {
	conditions := []string{"g.status = 'done'"}
	args := []any{}

	if startTime != nil {
		conditions = append(conditions, "g.ts >= $"+strconv.Itoa(len(args)+1))
		args = append(args, *startTime)
	}
	if endTime != nil {
		conditions = append(conditions, "g.ts <= $"+strconv.Itoa(len(args)+1))
		args = append(args, *endTime)
	}

	whereClause := ""
	if len(conditions) > 0 {
		whereClause = "WHERE " + strings.Join(conditions, " AND ")
	}

	countSQL := "SELECT COUNT(*) FROM shizuku.grid_runs g " + whereClause
	var totalCount int
	if err := s.pool.QueryRow(ctx, countSQL, args...).Scan(&totalCount); err != nil {
		return nil, err
	}

	limitPos := len(args) + 1
	offsetPos := len(args) + 2
	args = append(args, limit, offset)

	query := strings.Builder{}
	query.WriteString("SELECT g.id, g.ts, g.res_m, g.status, g.blob_url_json, g.blob_url_contours, ")
	query.WriteString("COALESCE(COUNT(gsa.sensor_id), 0) AS sensor_count, AVG(gsa.avg_mm_h) AS avg_rainfall, ")
	query.WriteString("MAX(gsa.avg_mm_h) AS max_rainfall, g.created_at ")
	query.WriteString("FROM shizuku.grid_runs g ")
	query.WriteString("LEFT JOIN shizuku.grid_sensor_aggregates gsa ON gsa.grid_run_id = g.id ")
	query.WriteString(whereClause + " ")
	query.WriteString("GROUP BY g.id, g.ts, g.res_m, g.status, g.blob_url_json, g.blob_url_contours, g.created_at ")
	query.WriteString("ORDER BY g.ts DESC ")
	query.WriteString("LIMIT $" + strconv.Itoa(limitPos) + " OFFSET $" + strconv.Itoa(offsetPos))

	rows, err := s.pool.Query(ctx, query.String(), args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	grids := make([]GridTimestampResult, 0, limit)
	for rows.Next() {
		var g GridTimestampResult
		if err := rows.Scan(
			&g.ID,
			&g.Timestamp,
			&g.Resolution,
			&g.Status,
			&g.GridJSONURL,
			&g.ContoursURL,
			&g.SensorCount,
			&g.AvgRainfallMmH,
			&g.MaxRainfallMmH,
			&g.CreatedAt,
		); err != nil {
			return nil, err
		}
		grids = append(grids, g)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	return &GridTimestampsPage{Grids: grids, TotalCount: totalCount}, nil
}

type GridRun struct {
	ID              int       `json:"id"`
	Timestamp       time.Time `json:"timestamp"`
	Resolution      int       `json:"resolution"`
	BBox            []float64 `json:"bbox,omitempty"`
	CRS             string    `json:"crs"`
	BlobURLJSON     *string   `json:"blob_url_json,omitempty"`
	BlobURLContours *string   `json:"blob_url_contours,omitempty"`
	Status          string    `json:"status"`
	Message         *string   `json:"message,omitempty"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

func (s *Store) GetGridRunByTimestamp(ctx context.Context, timestamp time.Time) (*GridRun, error) {
	query := `
		SELECT id, ts, res_m, bbox, crs,
		       blob_url_json, blob_url_contours,
		       status, message, created_at, updated_at
		FROM shizuku.grid_runs
		WHERE ts = $1 AND status = 'done'
		LIMIT 1
	`

	row := s.pool.QueryRow(ctx, query, timestamp)

	var g GridRun
	var bboxJSON []byte
	if err := row.Scan(
		&g.ID,
		&g.Timestamp,
		&g.Resolution,
		&bboxJSON,
		&g.CRS,
		&g.BlobURLJSON,
		&g.BlobURLContours,
		&g.Status,
		&g.Message,
		&g.CreatedAt,
		&g.UpdatedAt,
	); err != nil {
		return nil, err
	}

	if len(bboxJSON) > 0 {
		_ = json.Unmarshal(bboxJSON, &g.BBox)
	}

	return &g, nil
}

type SensorAggregate struct {
	SensorID         string    `json:"sensor_id"`
	SensorName       *string   `json:"sensor_name,omitempty"`
	Lat              float64   `json:"lat"`
	Lon              float64   `json:"lon"`
	AvgMmH           float64   `json:"avg_mm_h"`
	MeasurementCount int       `json:"measurement_count"`
	CreatedAt        time.Time `json:"created_at"`
}

func (s *Store) GetSensorAggregatesByTimestamp(ctx context.Context, timestamp time.Time) ([]SensorAggregate, error) {
	query := `
		SELECT gsa.sensor_id,
		       s.name,
		       s.lat,
		       s.lon,
		       gsa.avg_mm_h,
		       gsa.measurement_count,
		       gsa.created_at
		FROM shizuku.grid_sensor_aggregates gsa
		JOIN shizuku.grid_runs g ON g.id = gsa.grid_run_id
		JOIN shizuku.sensors s ON s.id = gsa.sensor_id
		WHERE g.ts = $1 AND g.status = 'done'
		ORDER BY gsa.avg_mm_h DESC
	`

	rows, err := s.pool.Query(ctx, query, timestamp)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	aggregates := make([]SensorAggregate, 0)
	for rows.Next() {
		var agg SensorAggregate
		if err := rows.Scan(
			&agg.SensorID,
			&agg.SensorName,
			&agg.Lat,
			&agg.Lon,
			&agg.AvgMmH,
			&agg.MeasurementCount,
			&agg.CreatedAt,
		); err != nil {
			return nil, err
		}
		aggregates = append(aggregates, agg)
	}

	return aggregates, rows.Err()
}

func (s *Store) GetSensorAggregatesByGridRunID(ctx context.Context, gridRunID int) ([]SensorAggregate, error) {
	query := `
		SELECT gsa.sensor_id,
		       s.name,
		       s.lat,
		       s.lon,
		       gsa.avg_mm_h,
		       gsa.measurement_count,
		       gsa.created_at
		FROM shizuku.grid_sensor_aggregates gsa
		JOIN shizuku.sensors s ON s.id = gsa.sensor_id
		WHERE gsa.grid_run_id = $1
		ORDER BY gsa.avg_mm_h DESC
	`

	rows, err := s.pool.Query(ctx, query, gridRunID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	aggregates := make([]SensorAggregate, 0)
	for rows.Next() {
		var agg SensorAggregate
		if err := rows.Scan(
			&agg.SensorID,
			&agg.SensorName,
			&agg.Lat,
			&agg.Lon,
			&agg.AvgMmH,
			&agg.MeasurementCount,
			&agg.CreatedAt,
		); err != nil {
			return nil, err
		}
		aggregates = append(aggregates, agg)
	}

	return aggregates, rows.Err()
}

func (s *Store) GetLatestGrid(ctx context.Context) (*GridRun, error) {
	query := `
		SELECT id, ts, res_m, bbox, crs,
		       blob_url_json, blob_url_contours,
		       status, message, created_at, updated_at
		FROM shizuku.grid_runs
		WHERE status = 'done'
		ORDER BY ts DESC
		LIMIT 1
	`

	row := s.pool.QueryRow(ctx, query)

	var g GridRun
	var bboxJSON []byte
	if err := row.Scan(
		&g.ID,
		&g.Timestamp,
		&g.Resolution,
		&bboxJSON,
		&g.CRS,
		&g.BlobURLJSON,
		&g.BlobURLContours,
		&g.Status,
		&g.Message,
		&g.CreatedAt,
		&g.UpdatedAt,
	); err != nil {
		return nil, err
	}

	if len(bboxJSON) > 0 {
		_ = json.Unmarshal(bboxJSON, &g.BBox)
	}

	return &g, nil
}

func (s *Store) GetSensor(ctx context.Context, sensorID string) (*Sensor, error) {
	query := `
		SELECT id, name, provider_id, lat, lon, city, subbasin, barrio, metadata, created_at, updated_at
		FROM shizuku.sensors
		WHERE id = $1
	`

	row := s.pool.QueryRow(ctx, query, sensorID)

	var sensor Sensor
	if err := row.Scan(
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

	return &sensor, nil
}
