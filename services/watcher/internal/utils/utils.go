package utils

import (
    "fmt"
    "math"
    "strconv"
    "time"

    "github.com/zerotwo/siata-watcher/services/watcher/internal/models"
)

// BuildSensorRows converts feed stations into database-ready sensor rows.
func BuildSensorRows(stations []models.Station) []models.SensorRow {
    rows := make([]models.SensorRow, 0, len(stations))
    for _, st := range stations {
        id := fmt.Sprintf("pluvio_%d", st.Code)
        metadata := map[string]any{
            "source":   "current",
            "comuna":   st.Comuna,
            "network":  "pluvio",
            "barrio":   st.Barrio,
            "subcuenca": st.Subbasin,
        }
        rows = append(rows, models.SensorRow{
            ID:         id,
            ProviderID: strconv.Itoa(st.Code),
            Name:       st.Name,
            Lat:        st.Latitude,
            Lon:        st.Longitude,
            City:       st.City,
            Subbasin:   st.Subbasin,
            Barrio:     st.Barrio,
            Metadata:   metadata,
        })
    }
    return rows
}

// SensorIDs extracts sensor identifiers from sensor rows.
func SensorIDs(rows []models.SensorRow) []string {
    ids := make([]string, 0, len(rows))
    for _, row := range rows {
        ids = append(ids, row.ID)
    }
    return ids
}

// BuildMeasurementCandidates normalizes station values into measurement candidates.
func BuildMeasurementCandidates(stations []models.Station, retrievalTS time.Time) []models.MeasurementCandidate {
    candidates := make([]models.MeasurementCandidate, 0, len(stations))
    for _, st := range stations {
        id := fmt.Sprintf("pluvio_%d", st.Code)
        value := NormalizeValue(st.Value)
        candidates = append(candidates, models.MeasurementCandidate{
            SensorID: id,
            Value:    value,
            TS:       retrievalTS,
        })
    }
    return candidates
}

// NormalizeValue cleans raw sensor values; -999 sentinel -> nil.
func NormalizeValue(v *float64) *float64 {
    if v == nil {
        return nil
    }
    if *v <= -900 {
        return nil
    }
    val := *v
    return &val
}

// FilterNewMeasurements selects candidates that should be inserted.
func FilterNewMeasurements(
    candidates []models.MeasurementCandidate,
    last map[string]models.LastMeasurement,
    minInterval time.Duration,
    epsilon float64,
) []models.MeasurementCandidate {
    out := make([]models.MeasurementCandidate, 0, len(candidates))
    for _, cand := range candidates {
        prev, ok := last[cand.SensorID]
        if !ok {
            out = append(out, cand)
            continue
        }

        if cand.TS.Sub(prev.TS) >= minInterval {
            out = append(out, cand)
            continue
        }

        if !ValuesEqual(prev.Value, cand.Value, epsilon) {
            out = append(out, cand)
        }
    }
    return out
}

// ValuesEqual compares two optional float values with tolerance.
func ValuesEqual(a, b *float64, epsilon float64) bool {
    switch {
    case a == nil && b == nil:
        return true
    case a == nil || b == nil:
        return false
    default:
        return math.Abs(*a-*b) <= epsilon
    }
}

// ValuePtrString prints pointer values for logging.
func ValuePtrString(v *float64) string {
    if v == nil {
        return "null"
    }
    return fmt.Sprintf("%.3f", *v)
}
