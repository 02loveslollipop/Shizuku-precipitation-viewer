package db

import (
	"context"
	"encoding/json"
	"strconv"
	"strings"
	"time"
)

// SensorAggregate represents aggregated sensor data for a grid run
type SensorAggregate struct {
	SensorID         string   `json:"sensor_id"`
	AvgMmH           float64  `json:"avg_mm_h"`
	MeasurementCount int      `json:"measurement_count"`
	MinValueMm       float64  `json:"min_value_mm"`
	MaxValueMm       float64  `json:"max_value_mm"`
	Sensor           *Sensor  `json:"sensor,omitempty"` // Optional enrichment
}

type GridTimestampResult struct {
	ID             int                `json:"id"`
	Timestamp      time.Time          `json:"timestamp"`
	Resolution     int                `json:"resolution"`
	Status         string             `json:"status"`
	GridJSONURL    *string            `json:"grid_json_url,omitempty"`
	ContoursURL    *string            `json:"contours_url,omitempty"`
	SensorCount    int                `json:"sensor_count"`
	AvgRainfallMmH *float64           `json:"avg_rainfall_mm_h,omitempty"`
	MaxRainfallMmH *float64           `json:"max_rainfall_mm_h,omitempty"`
	CreatedAt      time.Time          `json:"created_at"`
	Sensors        []SensorAggregate  `json:"sensors,omitempty"` // Optional enrichment
}

type GridTimestampsPage struct {
	Grids      []GridTimestampResult `json:"grids"`
	TotalCount int                   `json:"total_count"`
}

func (s *Store) ListGridTimestampsWithAggregates(ctx context.Context, limit, offset int, startTime, endTime *time.Time, includeSensors bool) (*GridTimestampsPage, error) {
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
	gridIDs := make([]int, 0, limit)
	
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
		gridIDs = append(gridIDs, g.ID)
	}

	if err := rows.Err(); err != nil {
		return nil, err
	}

	// If sensor enrichment is requested, fetch sensor aggregates with sensor details
	if includeSensors && len(gridIDs) > 0 {
		if err := s.enrichGridsWithSensors(ctx, grids, gridIDs); err != nil {
			return nil, err
		}
	}

	return &GridTimestampsPage{Grids: grids, TotalCount: totalCount}, nil
}

// enrichGridsWithSensors fetches sensor aggregates and enriches them with sensor metadata
func (s *Store) enrichGridsWithSensors(ctx context.Context, grids []GridTimestampResult, gridIDs []int) error {
	// Build query with IN clause for grid IDs
	query := `
		SELECT gsa.grid_run_id, gsa.sensor_id, gsa.avg_mm_h, gsa.measurement_count, 
		       gsa.min_value_mm, gsa.max_value_mm,
		       s.id, s.name, s.provider_id, s.lat, s.lon, s.city, s.subbasin, s.barrio, s.created_at, s.updated_at
		FROM shizuku.grid_sensor_aggregates gsa
		INNER JOIN shizuku.sensors s ON s.id = gsa.sensor_id
		WHERE gsa.grid_run_id = ANY($1)
		ORDER BY gsa.grid_run_id, gsa.sensor_id
	`

	rows, err := s.pool.Query(ctx, query, gridIDs)
	if err != nil {
		return err
	}
	defer rows.Close()

	// Create map to organize sensors by grid ID
	sensorsByGrid := make(map[int][]SensorAggregate)

	for rows.Next() {
		var gridRunID int
		var agg SensorAggregate
		var sensor Sensor

		if err := rows.Scan(
			&gridRunID,
			&agg.SensorID,
			&agg.AvgMmH,
			&agg.MeasurementCount,
			&agg.MinValueMm,
			&agg.MaxValueMm,
			&sensor.ID,
			&sensor.Name,
			&sensor.ProviderID,
			&sensor.Lat,
			&sensor.Lon,
			&sensor.City,
			&sensor.Subbasin,
			&sensor.Barrio,
			&sensor.CreatedAt,
			&sensor.UpdatedAt,
		); err != nil {
			return err
		}

		agg.Sensor = &sensor
		sensorsByGrid[gridRunID] = append(sensorsByGrid[gridRunID], agg)
	}

	if err := rows.Err(); err != nil {
		return err
	}

	// Attach sensors to their respective grids
	for i := range grids {
		if sensors, ok := sensorsByGrid[grids[i].ID]; ok {
			grids[i].Sensors = sensors
		}
	}

	return nil
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

func (s *Store) GetSensorAggregatesByTimestamp(ctx context.Context, timestamp time.Time) ([]SensorAggregate, error) {
	query := `
		SELECT gsa.sensor_id,
		       gsa.avg_mm_h,
		       gsa.measurement_count,
		       gsa.min_value_mm,
		       gsa.max_value_mm,
		       s.id,
		       s.name,
		       s.provider_id,
		       s.lat,
		       s.lon,
		       s.city,
		       s.subbasin,
		       s.barrio,
		       s.created_at,
		       s.updated_at
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
		var sensor Sensor
		
		if err := rows.Scan(
			&agg.SensorID,
			&agg.AvgMmH,
			&agg.MeasurementCount,
			&agg.MinValueMm,
			&agg.MaxValueMm,
			&sensor.ID,
			&sensor.Name,
			&sensor.ProviderID,
			&sensor.Lat,
			&sensor.Lon,
			&sensor.City,
			&sensor.Subbasin,
			&sensor.Barrio,
			&sensor.CreatedAt,
			&sensor.UpdatedAt,
		); err != nil {
			return nil, err
		}
		
		agg.Sensor = &sensor
		aggregates = append(aggregates, agg)
	}

	return aggregates, rows.Err()
}

func (s *Store) GetSensorAggregatesByGridRunID(ctx context.Context, gridRunID int) ([]SensorAggregate, error) {
	query := `
		SELECT gsa.sensor_id,
		       gsa.avg_mm_h,
		       gsa.measurement_count,
		       gsa.min_value_mm,
		       gsa.max_value_mm,
		       s.id,
		       s.name,
		       s.provider_id,
		       s.lat,
		       s.lon,
		       s.city,
		       s.subbasin,
		       s.barrio,
		       s.created_at,
		       s.updated_at
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
		var sensor Sensor
		
		if err := rows.Scan(
			&agg.SensorID,
			&agg.AvgMmH,
			&agg.MeasurementCount,
			&agg.MinValueMm,
			&agg.MaxValueMm,
			&sensor.ID,
			&sensor.Name,
			&sensor.ProviderID,
			&sensor.Lat,
			&sensor.Lon,
			&sensor.City,
			&sensor.Subbasin,
			&sensor.Barrio,
			&sensor.CreatedAt,
			&sensor.UpdatedAt,
		); err != nil {
			return nil, err
		}
		
		agg.Sensor = &sensor
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
