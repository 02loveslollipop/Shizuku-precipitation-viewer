package main

import (
    "context"
    "log"
    "net/http"
    "time"

    "github.com/jackc/pgx/v5/pgxpool"

    "github.com/zerotwo/siata-watcher/internal/config"
    "github.com/zerotwo/siata-watcher/internal/db"
    "github.com/zerotwo/siata-watcher/internal/siata"
    "github.com/zerotwo/siata-watcher/internal/utils"
)

func main() {
    if err := run(); err != nil {
        log.Fatalf("watcher failed: %v", err)
    }
}

func run() error {
    cfg, err := config.Load()
    if err != nil {
        return err
    }

    ctx, cancel := context.WithTimeout(context.Background(), cfg.RequestTimeout+10*time.Second)
    defer cancel()

    client := &http.Client{Timeout: cfg.RequestTimeout}
    retrievalTS := time.Now().UTC().Truncate(time.Second)

    payload, err := siata.FetchCurrentStations(ctx, client, cfg.CurrentURL)
    if err != nil {
        return err
    }
    log.Printf("fetched %d stations (network=%s)", len(payload.Stations), payload.Network)

    pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
    if err != nil {
        return err
    }
    defer pool.Close()

    sensorRows := utils.BuildSensorRows(payload.Stations)
    if cfg.DryRun {
        log.Printf("dry-run: skipping sensor upsert (%d candidates)", len(sensorRows))
    } else {
        if err := db.UpsertSensors(ctx, pool, sensorRows); err != nil {
            return err
        }
    }

    sensorIDs := utils.SensorIDs(sensorRows)
    lastMap, err := db.FetchLastMeasurements(ctx, pool, sensorIDs)
    if err != nil {
        return err
    }

    candidates := utils.BuildMeasurementCandidates(payload.Stations, retrievalTS)
    pending := utils.FilterNewMeasurements(candidates, lastMap, cfg.MinInterval, cfg.ValueEpsilon)

    if len(pending) == 0 {
        log.Printf("no new measurements to insert (retrieval=%s)", retrievalTS.Format(time.RFC3339))
        return nil
    }

    log.Printf("prepared %d new measurements (dry-run=%v)", len(pending), cfg.DryRun)

    if cfg.DryRun {
        for _, cand := range pending {
            log.Printf("dry-run: would insert sensor=%s ts=%s value=%s", cand.SensorID, cand.TS.Format(time.RFC3339), utils.ValuePtrString(cand.Value))
        }
        return nil
    }

    if err := db.InsertMeasurements(ctx, pool, pending); err != nil {
        return err
    }

    log.Printf("inserted %d measurements", len(pending))
    return nil
}
