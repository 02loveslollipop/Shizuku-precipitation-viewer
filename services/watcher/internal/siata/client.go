package siata

import (
    "context"
    "encoding/json"
    "fmt"
    "net/http"

    "github.com/zerotwo/siata-watcher/services/watcher/internal/models"
)

// FetchCurrentStations retrieves the current SIATA stations payload.
func FetchCurrentStations(ctx context.Context, client *http.Client, url string) (models.CurrentResponse, error) {
    req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
    if err != nil {
        return models.CurrentResponse{}, err
    }

    resp, err := client.Do(req)
    if err != nil {
        return models.CurrentResponse{}, fmt.Errorf("request current feed: %w", err)
    }
    defer resp.Body.Close()

    if resp.StatusCode < 200 || resp.StatusCode >= 300 {
        return models.CurrentResponse{}, fmt.Errorf("unexpected status %s", resp.Status)
    }

    var payload models.CurrentResponse
    if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
        return models.CurrentResponse{}, fmt.Errorf("decode payload: %w", err)
    }

    return payload, nil
}
