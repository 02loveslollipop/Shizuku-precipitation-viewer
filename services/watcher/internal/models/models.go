package models

import "time"

// CurrentResponse models the JSON payload returned by the SIATA current feed.
type CurrentResponse struct {
    Stations []Station `json:"estaciones"`
    Network  string    `json:"red"`
}

// Station represents a single station entry from the current feed.
type Station struct {
    Barrio    string   `json:"barrio"`
    City      string   `json:"ciudad"`
    Code      int      `json:"codigo"`
    Comuna    string   `json:"comuna"`
    Latitude  float64  `json:"latitud"`
    Longitude float64  `json:"longitud"`
    Name      string   `json:"nombre"`
    Subbasin  string   `json:"subcuenca"`
    Value     *float64 `json:"valor"`
}

// SensorRow captures the normalized sensor metadata for DB operations.
type SensorRow struct {
    ID         string
    ProviderID string
    Name       string
    Lat        float64
    Lon        float64
    City       string
    Subbasin   string
    Barrio     string
    Metadata   map[string]any
}

// MeasurementCandidate encapsulates a normalized measurement ready for insertion.
type MeasurementCandidate struct {
    SensorID string
    Value    *float64
    TS       time.Time
}

// LastMeasurement represents the most recent stored measurement for comparison.
type LastMeasurement struct {
    Value *float64
    TS    time.Time
}
